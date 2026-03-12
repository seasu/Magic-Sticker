import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/sticker_shape.dart';
import '../models/sticker_spec.dart';
import '../models/sticker_style.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

/// Gemini 貼圖生成服務
///
/// 每張貼圖獨立呼叫 Cloud Function（1 call per sticker）。
/// API Key 保存在 Cloud Function 環境變數，App 內完全不含金鑰。
class StickerGenerationService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1');

  /// 生成單張貼圖，扣 1 點後回傳 PNG bytes 和剩餘點數。
  ///
  /// [bytes] null = 生成失敗；[remainingCredits] -1 = 無法取得（點數已由 Cloud Function 退還）
  Future<({Uint8List? bytes, int remainingCredits})> generateSingle(
    Uint8List photoBytes,
    StickerSpec spec, {
    int index = 0,
    int styleIndex = 0,
    StickerShape shape = StickerShape.circle,
  }) async {
    final style =
        StickerStyle.values[styleIndex.clamp(0, StickerStyle.values.length - 1)];
    FirebaseService.log(
      'StickerGenerationService.generateSingle: index=$index '
      'emotion=${spec.emotion} style=${style.label}',
    );

    // 確保呼叫前有 Firebase Auth session（startup 時若網路失敗可能為 null）
    if (FirebaseAuth.instance.currentUser == null) {
      FirebaseService.log('StickerGenerationService: no auth session, attempting sign-in');
      await AuthService.signInAnonymouslyIfNeeded();
      // sign-in 仍失敗 → 立即結束，無法呼叫 Cloud Function
      if (FirebaseAuth.instance.currentUser == null) {
        FirebaseService.log('StickerGenerationService: sign-in failed, aborting index=$index');
        return (bytes: null, remainingCredits: -1);
      }
    } else {
      // 預先強制刷新 token，避免因 token 過期導致第一次呼叫就 UNAUTHENTICATED
      try {
        await FirebaseAuth.instance.currentUser!.getIdToken(true);
      } catch (e) {
        FirebaseService.log('StickerGenerationService: pre-flight token refresh failed: $e');
        // 繼續嘗試，交由 retry loop 處理
      }
    }

    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final callable = _fn.httpsCallable(
          'generateStickerImage',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 125)),
        );

        final result = await callable.call<Map<String, dynamic>>({
          'photoBase64': base64Encode(photoBytes),
          'prompt': _buildSinglePrompt(spec, style, shape),
        });

        final imageBase64 = result.data['imageBase64'] as String;
        final bytes = base64Decode(imageBase64);
        final remaining = (result.data['remainingCredits'] as num?)?.toInt() ?? -1;

        FirebaseService.log(
          'StickerGenerationService: index=$index OK '
          '(${bytes.lengthInBytes} bytes) remainingCredits=$remaining',
        );
        await FirebaseAnalytics.instance
            .logEvent(name: 'sticker_image_generated');
        return (bytes: bytes, remainingCredits: remaining);
      } on FirebaseFunctionsException catch (e, stack) {
        // 未認證 → 強制刷新 ID token 後 retry（token 過期或 linkWithCredential 後短暫失效）
        // 加入指數退避延遲（1s / 2s / 4s），讓 Firebase Auth 後端有時間完成 token rotation。
        if (e.code == 'unauthenticated' && attempt < maxRetries) {
          FirebaseService.log(
            'StickerGenerationService: unauthenticated index=$index, '
            'refreshing token attempt ${attempt + 1}/$maxRetries',
          );
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await user.getIdToken(true); // 強制刷新，忽略快取
          } else {
            await AuthService.signInAnonymouslyIfNeeded();
            // sign-in 後仍無 session → 無需繼續重試
            if (FirebaseAuth.instance.currentUser == null) {
              await FirebaseService.recordError(
                e, stack, reason: 'sticker_single_gen_fn_failed_no_auth_index$index',
              );
              return (bytes: null, remainingCredits: -1);
            }
          }
          // 退避等待：1s → 2s → 4s，避免在 linkWithCredential token rotation 視窗內立即重試
          await Future.delayed(Duration(seconds: 1 << attempt));
          continue;
        }
        if (e.code == 'unauthenticated') {
          await FirebaseService.recordError(
            e, stack, reason: 'sticker_single_gen_fn_failed_index$index',
          );
          return (bytes: null, remainingCredits: -1);
        }

        final isRateLimit = e.code == 'resource-exhausted';

        // rate-limited without credit message → retry（Cloud Function 已退點）
        if (isRateLimit && e.message?.contains('Rate limited') == true && attempt < maxRetries) {
          final delay = _parseRetryDelay(e.message ?? '') ??
              Duration(seconds: (attempt + 1) * 15);
          FirebaseService.log(
            'StickerGenerationService: rate-limited index=$index, '
            'retry ${attempt + 1}/$maxRetries in ${delay.inSeconds}s',
          );
          await Future.delayed(delay);
          continue;
        }

        // 點數不足 → 直接 rethrow，讓 editor_provider 顯示 paywall
        if (isRateLimit && e.message?.contains('Insufficient') == true) {
          rethrow;
        }

        await FirebaseService.recordError(
          e, stack, reason: 'sticker_single_gen_fn_failed_index$index',
        );
        return (bytes: null, remainingCredits: -1);
      } catch (e, stack) {
        await FirebaseService.recordError(
          e, stack, reason: 'sticker_single_gen_failed_index$index',
        );
        return (bytes: null, remainingCredits: -1);
      }
    }

    return (bytes: null, remainingCredits: -1);
  }

  // ─── private ────────────────────────────────────────────────────────────

  String _buildSinglePrompt(
      StickerSpec spec, StickerStyle style, StickerShape shape) {
    if (shape == StickerShape.circle) {
      return '''
You are a professional LINE sticker illustrator. Draw ONE single circular sticker based on the person's face in the reference photo.

DESIGN REQUIREMENTS:
- A single large filled perfect circle, centered, occupying ~90% of the square canvas
- The circle must be geometrically perfect (equal width and height)
- Circle background color: ${spec.bgColor}
- Character expression / pose: ${spec.emotion}
- ${style.characterDesc}
- DO NOT draw any text or letters inside the image
- 3–5 small sparkles / stars scattered inside the circle
- NO white outline, NO white border around the circle
- The area outside the circle must be completely transparent (alpha = 0), no fill at all

OUTPUT: A single square PNG (equal width and height) with a transparent background outside the circle, containing exactly this ONE circular sticker.
STYLE: ${style.promptSuffix}
''';
    } else {
      return '''
You are a professional LINE sticker illustrator. Draw ONE single square sticker based on the person's face in the reference photo.

DESIGN REQUIREMENTS:
- Fill the entire square canvas with ${spec.bgColor} as the background
- Character expression / pose: ${spec.emotion}
- ${style.characterDesc}
- DO NOT draw any text or letters inside the image
- 3–5 small sparkles / stars scattered in the background
- NO white border or white outline anywhere

OUTPUT: A single square PNG containing exactly this ONE sticker with no white background.
STYLE: ${style.promptSuffix}
''';
    }
  }

  static Duration? _parseRetryDelay(String message) {
    final m = RegExp(r'retry after (\d+(?:\.\d+)?)s', caseSensitive: false)
        .firstMatch(message);
    if (m == null) return null;
    final seconds = double.tryParse(m.group(1)!);
    if (seconds == null) return null;
    return Duration(milliseconds: ((seconds + 1) * 1000).round());
  }
}

/// Cloud Function 呼叫失敗時拋出（保留供外部 catch 識別用）
class StickerApiException implements Exception {
  final int statusCode;
  final String body;
  const StickerApiException(this.statusCode, this.body);

  @override
  String toString() => 'StickerApiException HTTP $statusCode:\n$body';
}
