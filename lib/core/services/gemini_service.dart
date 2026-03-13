import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/emotion_category.dart';
import '../models/sticker_spec.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

/// 8 組預設 fallback（Cloud Function 失敗時使用）
///
/// 與 kDefaultCategoryIds 順序一致，含 categoryId。
const _kFallbackSpecs = [
  {'categoryId': 'greeting', 'text': '哈囉！',    'emotion': 'cheerfully waving hello',            'bgColor': 'warm peach #F4A261'},
  {'categoryId': 'praise',   'text': '太棒了！',  'emotion': 'excited thumbs-up with sparkles',    'bgColor': 'sky blue #74C0FC'},
  {'categoryId': 'surprise', 'text': '真的嗎？',  'emotion': 'shocked wide eyes, question marks',  'bgColor': 'golden yellow #FFD43B'},
  {'categoryId': 'awkward',  'text': '尷尬了...', 'emotion': 'embarrassed blushing, sweat drop',   'bgColor': 'soft pink #FFB3C6'},
  {'categoryId': 'angry',    'text': '哼！',      'emotion': 'angry frowning with flames',         'bgColor': 'deep red #FF6B6B'},
  {'categoryId': 'happy',    'text': '開心！',    'emotion': 'joyful laughing, rainbow confetti',  'bgColor': 'mint green #63E6BE'},
  {'categoryId': 'thinking', 'text': '我想想...', 'emotion': 'thoughtful chin-rubbing, thought bubble', 'bgColor': 'lavender #C084FC'},
  {'categoryId': 'farewell', 'text': '再見囉！',  'emotion': 'waving goodbye with sunglasses',     'bgColor': 'baby blue #ADE8F4'},
];

class GeminiService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1');

  /// 呼叫 Cloud Function `generateStickerSpecs`。
  ///
  /// [categoryIds] 指定要生成的情感類別（不傳則使用預設 8 種）。
  /// Spec 預覽免費，不扣點。失敗時回傳 fallback specs。
  Future<List<StickerSpec>> generateStickerSpecs(
    Uint8List imageBytes, {
    List<String>? categoryIds,
  }) async {
    FirebaseService.log('GeminiService.generateStickerSpecs: start');

    // 解析請求的情感類別（若未指定則使用預設 8 種）
    final ids = (categoryIds != null && categoryIds.isNotEmpty)
        ? categoryIds
        : kDefaultCategoryIds;

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
          'categoryIds': ids,
        });

        final data = result.data;
        final rawSpecs = (data['specs'] as List).cast<Map<String, dynamic>>();
        final specs = rawSpecs.take(ids.length).map(StickerSpec.fromJson).toList();

        FirebaseService.log('GeminiService.generateStickerSpecs: done (${specs.length} specs)');
        await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_generated');

        return specs;
      } on FirebaseFunctionsException catch (e, stack) {
        if (e.code == 'unauthenticated' && attempt < maxRetries) {
          if (_isIamBlock(e)) {
            FirebaseService.log(
              'GeminiService: Cloud Run IAM 拒絕（msg=UNAUTHENTICATED）'
              ' — token retry 無效，請重新部署 Functions with invoker:public',
            );
            await FirebaseService.recordError(
              e, stack, reason: 'gemini_specs_fn_iam_blocked',
            );
            await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
            return _buildFallback(ids);
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
        return _buildFallback(ids);
      } catch (e, stack) {
        await FirebaseService.recordError(
          e, stack, reason: 'gemini_specs_unexpected_failed',
        );
        await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
        return _buildFallback(ids);
      }
    }

    return _buildFallback(ids);
  }

  // ─── private ──────────────────────────────────────────────────────────────

  /// 依請求的 categoryIds 建立 fallback specs。
  ///
  /// 若某 id 有預設 fallback spec 則用之；否則從 kEmotionCategories 生成最小規格。
  static List<StickerSpec> _buildFallback(List<String> ids) {
    final fallbackMap = {
      for (final m in _kFallbackSpecs) m['categoryId'] as String: m,
    };
    return ids.map((id) {
      final m = fallbackMap[id];
      if (m != null) return StickerSpec.fromJson(m);
      // 找不到預設 fallback → 從 kEmotionCategories 取 promptHint 當 emotion
      final cat = findCategory(id);
      return StickerSpec(
        text: cat?.label ?? id,
        emotion: cat?.promptHint ?? id,
        bgColor: 'soft blue #74C0FC',
        categoryId: id,
      );
    }).toList();
  }

  /// Cloud Run IAM 攔截的特徵：錯誤碼 unauthenticated + 訊息為全大寫 'UNAUTHENTICATED'。
  ///
  /// resolveUid 拒絕時訊息是 "No Authorization header..." 或 "Token verification failed..."。
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
