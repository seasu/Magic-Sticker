import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/sticker_spec.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

/// 8 組預設 fallback（Cloud Function 失敗時使用）
const _kFallbackSpecs = [
  {'text': '哈囉！',    'emotion': 'cheerfully waving hello',            'bgColor': 'warm peach #F4A261'},
  {'text': '太棒了！',  'emotion': 'excited thumbs-up with sparkles',    'bgColor': 'sky blue #74C0FC'},
  {'text': '真的嗎？',  'emotion': 'shocked wide eyes, question marks',  'bgColor': 'golden yellow #FFD43B'},
  {'text': '尷尬了...', 'emotion': 'embarrassed blushing, sweat drop',   'bgColor': 'soft pink #FFB3C6'},
  {'text': '哼！',      'emotion': 'angry frowning with flames',         'bgColor': 'deep red #FF6B6B'},
  {'text': '開心！',    'emotion': 'joyful laughing, rainbow confetti',  'bgColor': 'mint green #63E6BE'},
  {'text': '我想想...', 'emotion': 'thoughtful chin-rubbing, thought bubble', 'bgColor': 'lavender #C084FC'},
  {'text': '再見囉！',  'emotion': 'waving goodbye with sunglasses',     'bgColor': 'baby blue #ADE8F4'},
];

class GeminiService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1');

  /// 呼叫 Cloud Function `generateStickerSpecs`。
  ///
  /// Spec 預覽免費，不扣點。
  /// 失敗時回傳 fallback specs，確保使用者仍能看到預覽。
  Future<List<StickerSpec>> generateStickerSpecs(Uint8List imageBytes) async {
    FirebaseService.log('GeminiService.generateStickerSpecs: start');

    // 確保有有效的 auth session + token
    await AuthService.ensureValidToken();

    const maxRetries = 2;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final callable = _fn.httpsCallable(
          'generateStickerSpecs',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 65)),
        );

        final result = await callable.call<Map<String, dynamic>>({
          'photoBase64': base64Encode(imageBytes),
        });

        final data = result.data;
        final rawSpecs = (data['specs'] as List).cast<Map<String, dynamic>>();
        final specs = rawSpecs.take(8).map(StickerSpec.fromJson).toList();

        FirebaseService.log('GeminiService.generateStickerSpecs: done');
        await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_generated');

        return specs;
      } on FirebaseFunctionsException catch (e, stack) {
        if (e.code == 'unauthenticated' && attempt < maxRetries) {
          // 區分兩種 unauthenticated：
          //   msg == 'UNAUTHENTICATED'（全大寫）→ Cloud Run IAM 在 function 前攔截
          //   其他訊息 → resolveUid 拒絕（token 問題，retry 有效）
          if (_isIamBlock(e)) {
            FirebaseService.log(
              'GeminiService: Cloud Run IAM 拒絕（msg=UNAUTHENTICATED）'
              ' — token retry 無效，請重新部署 Functions with invoker:public',
            );
            // IAM 問題，retry 沒用，直接 break
            await FirebaseService.recordError(
              e, stack, reason: 'gemini_specs_fn_iam_blocked',
            );
            await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
            return _kFallbackSpecs.map(StickerSpec.fromJson).toList();
          }

          FirebaseService.log(
            'GeminiService: token rejected, refreshing '
            'attempt ${attempt + 1}/$maxRetries',
          );
          await Future.delayed(Duration(seconds: 1 << attempt));
          await _forceReAuth();
          continue;
        }

        FirebaseService.log(
          'GeminiService: Cloud Function error code=${e.code} msg=${e.message}',
        );
        await FirebaseService.recordError(
          e, stack,
          reason: _isIamBlock(e) ? 'gemini_specs_fn_iam_blocked' : 'gemini_specs_fn_failed',
        );
        await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
        return _kFallbackSpecs.map(StickerSpec.fromJson).toList();
      } catch (e, stack) {
        await FirebaseService.recordError(
          e, stack, reason: 'gemini_specs_unexpected_failed',
        );
        await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
        return _kFallbackSpecs.map(StickerSpec.fromJson).toList();
      }
    }

    return _kFallbackSpecs.map(StickerSpec.fromJson).toList();
  }

  // ─── private ──────────────────────────────────────────────────────────────

  /// Cloud Run IAM 攔截的特徵：錯誤碼 unauthenticated + 訊息為全大寫 'UNAUTHENTICATED'。
  ///
  /// 若是 resolveUid 拒絕，訊息會是 "No Authorization header..." 或
  /// "Token verification failed: ..."。
  /// 兩者修復方式完全不同：IAM 問題需重新部署；token 問題 retry 即可。
  static bool _isIamBlock(FirebaseFunctionsException e) =>
      e.code == 'unauthenticated' && e.message == 'UNAUTHENTICATED';

  /// Force re-authentication: refresh the ID token; if the token is
  /// unrecoverable (null/empty or getIdToken throws), sign out the anonymous
  /// session and create a new one.  Social-login users are only force-refreshed
  /// (signing them out would require re-presenting the social login UI).
  static Future<void> _forceReAuth() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      await AuthService.signInAnonymouslyIfNeeded();
      return;
    }

    try {
      final token = await user.getIdToken(true);
      if (token != null && token.isNotEmpty) {
        FirebaseService.log('GeminiService._forceReAuth: token refreshed uid=${user.uid}');
        return;
      }
    } catch (e) {
      FirebaseService.log('GeminiService._forceReAuth: getIdToken failed: $e');
    }

    // Token unrecoverable — recreate anonymous session (social users keep
    // their current state; signing them out would lock them out entirely).
    if (user.isAnonymous) {
      FirebaseService.log('GeminiService._forceReAuth: signing out broken anonymous session');
      await FirebaseAuth.instance.signOut();
      await AuthService.signInAnonymouslyIfNeeded();
    }
  }
}
