import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../constants/build_config.dart';
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

    // 確保呼叫前有 Firebase Auth session + 有效 token
    final preflightOk = await _ensureValidAuth(index);
    if (!preflightOk) {
      return (bytes: null, remainingCredits: -1);
    }

    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final callable = _fn.httpsCallable(
          'generateStickerImage',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 125)),
        );

        final prompt = _buildSinglePrompt(spec, style, shape);

        if (kDebugMode) {
          debugPrint(
            '\n══════════════════════════════════\n'
            '🎨 Sticker Prompt [index=$index style=${style.name}]\n'
            '══════════════════════════════════\n'
            '$prompt'
            '══════════════════════════════════\n',
          );
        }

        final result = await callable.call<Map<String, dynamic>>({
          'photoBase64': base64Encode(photoBytes),
          'prompt': prompt,
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
        if (e.code == 'unauthenticated' && attempt < maxRetries) {
          // Cloud Run IAM 攔截（msg 為全大寫 'UNAUTHENTICATED'）→ retry 無效，立即放棄
          if (_isIamBlock(e)) {
            FirebaseService.log(
              'StickerGenerationService: Cloud Run IAM 拒絕 index=$index'
              ' — 請重新部署 Functions with invoker:public',
            );
            await FirebaseService.recordError(
              e, stack, reason: 'sticker_single_gen_fn_iam_blocked_index$index',
            );
            return (bytes: null, remainingCredits: -1);
          }

          // Token 問題 → retry with re-auth
          FirebaseService.log(
            'StickerGenerationService: unauthenticated index=$index, '
            'attempt ${attempt + 1}/$maxRetries — re-authenticating',
          );
          // 退避等待：2s → 4s → 8s，讓 Firebase Auth 後端完成 token rotation
          await Future.delayed(Duration(seconds: 2 << attempt));
          final ok = await _ensureValidAuth(index);
          if (!ok) {
            await FirebaseService.recordError(
              e, stack, reason: 'sticker_single_gen_fn_failed_no_auth_index$index',
            );
            return (bytes: null, remainingCredits: -1);
          }
          continue;
        }
        if (e.code == 'unauthenticated') {
          await FirebaseService.recordError(
            e, stack,
            reason: _isIamBlock(e)
                ? 'sticker_single_gen_fn_iam_blocked_index$index'
                : 'sticker_single_gen_fn_failed_index$index',
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

  /// 確保有有效的 Firebase Auth session 和 ID token。
  ///
  /// 回傳 true = 就緒可呼叫 Cloud Function；false = 認證失敗，放棄。
  Future<bool> _ensureValidAuth(int index) async {
    var user = FirebaseAuth.instance.currentUser;

    // 沒有 user → 嘗試匿名登入
    if (user == null) {
      FirebaseService.log('StickerGenerationService: no auth session, signing in');
      await AuthService.signInAnonymouslyIfNeeded();
      user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        FirebaseService.log('StickerGenerationService: sign-in failed, aborting index=$index');
        return false;
      }
    }

    // 強制刷新 ID token，確保不過期
    try {
      final token = await user.getIdToken(true);
      if (token == null || token.isEmpty) {
        FirebaseService.log('StickerGenerationService: getIdToken returned null/empty, re-signing');
        // token 無法取得 → 登出後重新匿名登入
        await FirebaseAuth.instance.signOut();
        await AuthService.signInAnonymouslyIfNeeded();
        final retryUser = FirebaseAuth.instance.currentUser;
        if (retryUser == null) return false;
        final retryToken = await retryUser.getIdToken(true);
        return retryToken != null && retryToken.isNotEmpty;
      }
      return true;
    } catch (e) {
      FirebaseService.log('StickerGenerationService: token refresh failed: $e, re-signing');
      // token 刷新失敗（網路問題或 auth 狀態損壞） → 完整 re-auth
      try {
        await FirebaseAuth.instance.signOut();
        await AuthService.signInAnonymouslyIfNeeded();
        final retryUser = FirebaseAuth.instance.currentUser;
        if (retryUser == null) return false;
        final retryToken = await retryUser.getIdToken(true);
        return retryToken != null && retryToken.isNotEmpty;
      } catch (e2) {
        FirebaseService.log('StickerGenerationService: re-auth also failed: $e2');
        return false;
      }
    }
  }

  // ─── private ────────────────────────────────────────────────────────────

  String _buildSinglePrompt(
      StickerSpec spec, StickerStyle style, StickerShape shape) {
    if (shape == StickerShape.circle) {
      if (kStickerBgChromaKey) {
        return '''
你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張正方形貼圖。

【畫布規格 — Chroma Key 去背模式】
背景是純技術用遮罩色，與插畫風格完全無關，必須嚴格遵守以下規則：
- 所有背景區域（角色與裝飾以外的全部畫面）一律以電腦純色平塗填充為 #00FF00（R=0, G=255, B=0）
- 背景禁止任何藝術加工：無光暈、無漸層、無反光、無筆觸、無紋理、無陰影投射、無霧感
- 角色或裝飾的陰影禁止落在背景上
- 角色人物及所有裝飾元素禁止使用任何綠色系顏色（包含服裝、頭髮、裝飾、星星等所有部位）
- 四個角落像素必須為精確的 #00FF00

【角色設計】
- 根據參考照片，繪製可愛 Q 版卡通人物
- 表情 / 動作：${spec.emotion}
- ${style.characterDesc}
- 將角色完整置於畫布中央偏上（約佔畫布高度的上方 65%，水平置中）
- 角色頭頂保留至少 5% 的上邊距，雙腳或身體下緣保留至少 5% 的下邊距，確保角色不被任何邊緣裁切
- 角色左右兩側保留約 10% 邊距
- 嚴禁角色的任何部位（頭頂、耳朵、手臂、腳等）被畫布邊緣截斷
- 禁止出現任何文字、英文字母或數字

【裝飾】在角色周圍點綴 2–4 個小閃光或星星（集中在角色周邊，不接觸背景邊緣）

【輸出】單一正方形 PNG，背景為純平塗 #00FF00，無任何光影處理。
風格：${style.promptSuffix}
''';
      } else {
        return '''
你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張正方形貼圖。

【畫布規格】
- 整個正方形畫布以 ${spec.bgColor} 填色作為背景（含四個角落，不得有透明像素）
- 禁止出現任何透明區域、白色邊框或描邊

【角色設計】
- 根據參考照片，繪製可愛 Q 版卡通人物
- 表情 / 動作：${spec.emotion}
- ${style.characterDesc}
- 將角色完整置於畫布中央偏上（約佔畫布高度的上方 65%，水平置中）
- 角色頭頂保留至少 5% 的上邊距，雙腳或身體下緣保留至少 5% 的下邊距，確保角色不被任何邊緣裁切
- 角色左右兩側保留約 10% 邊距
- 嚴禁角色的任何部位（頭頂、耳朵、手臂、腳等）被畫布邊緣截斷
- 禁止出現任何文字、英文字母或數字

【裝飾】在角色周圍點綴 2–4 個小閃光或星星（集中在畫布中央區域）

【配色】背景色：${spec.bgColor}

【輸出】單一正方形 PNG，背景完全不透明。
風格：${style.promptSuffix}
''';
      }
    } else {
      if (kStickerBgChromaKey) {
        return '''
你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張方形貼圖。

【畫布規格 — Chroma Key 去背模式】
背景是純技術用遮罩色，與插畫風格完全無關，必須嚴格遵守以下規則：
- 所有背景區域（角色與裝飾以外的全部畫面）一律以電腦純色平塗填充為 #00FF00（R=0, G=255, B=0）
- 背景禁止任何藝術加工：無光暈、無漸層、無反光、無筆觸、無紋理、無陰影投射、無霧感
- 角色或裝飾的陰影禁止落在背景上
- 角色人物及所有裝飾元素禁止使用任何綠色系顏色（包含服裝、頭髮、裝飾、星星等所有部位）
- 四個角落像素必須為精確的 #00FF00

【角色設計】
- 根據參考照片，繪製可愛 Q 版卡通人物
- 表情 / 動作：${spec.emotion}
- ${style.characterDesc}
- 角色完整呈現於畫布中央，頭頂與身體下緣各保留至少 5% 邊距，左右各保留約 10% 邊距
- 嚴禁角色的任何部位（頭頂、耳朵、手臂、腳等）被畫布邊緣截斷
- 畫面內禁止出現任何文字或英文字母
- 角色周圍點綴 3–5 個小閃光或星星（集中在角色周邊，不接觸背景邊緣）

【輸出】單一正方形 PNG，背景為純平塗 #00FF00，無任何光影處理。
風格：${style.promptSuffix}
''';
      } else {
        return '''
你是一位專業的 LINE 貼圖插畫師。請根據參考照片，繪製一張方形貼圖。

【設計規格】
- 整個正方形畫布以 ${spec.bgColor} 填色作為背景
- 角色表情 / 動作：${spec.emotion}
- ${style.characterDesc}
- 角色完整呈現於畫布中央，頭頂與身體下緣各保留至少 5% 邊距，左右各保留約 10% 邊距
- 嚴禁角色的任何部位（頭頂、耳朵、手臂、腳等）被畫布邊緣截斷
- 畫面內禁止出現任何文字或英文字母
- 背景中點綴 3–5 個小閃光或星星
- 禁止出現任何白色邊框或白色描邊

【輸出】單一正方形 PNG，無白色背景。
風格：${style.promptSuffix}
''';
      }
    }
  }

  /// 基礎設施層拒絕的特徵：錯誤碼 unauthenticated，且訊息不含 function 層自訂文字。
  ///
  /// - Cloud Run IAM 攔截（invoker 未設為 public）：訊息為全大寫 'UNAUTHENTICATED'
  /// - App Check 強制驗證（enforceAppCheck: true，token 無效/遺失）：訊息為 'Unauthenticated'
  ///
  /// resolveUid 拒絕時訊息是 "No Authorization header..." 或 "Token verification failed..."，
  /// 不符合此判斷，會進入正常重試流程。
  static bool _isIamBlock(FirebaseFunctionsException e) =>
      e.code == 'unauthenticated' &&
      (e.message == 'UNAUTHENTICATED' || e.message == 'Unauthenticated');

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
