import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:http/http.dart' as http;

import '../models/sticker_spec.dart';
import 'firebase_service.dart';

/// Imagen 3 貼圖生成服務（生圖專用）
///
/// 分析照片用 GeminiService（vision），生圖用本服務（Imagen）。
/// 逐一呼叫 Imagen API 產出 8 張獨立貼圖，回傳 List<Uint8List?>。
///
/// 注意：需在 dart-define 設定 GEMINI_API_KEY
class StickerGenerationService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta'
      '/models/imagen-3.0-generate-002:predict';

  /// 生成 8 張貼圖，逐一呼叫 Imagen API
  ///
  /// [photoBytes] 保留參數以維持呼叫介面相容性（Imagen 為純文字生圖，照片不送入 API）
  /// 回傳長度固定為 8，對應索引 0–7；失敗時對應位置為 null。
  Future<List<Uint8List?>> generateAllAsGrid(
    Uint8List photoBytes,
    List<StickerSpec> specs,
  ) async {
    assert(specs.length == 8, 'generateAllAsGrid expects exactly 8 specs');
    FirebaseService.log('StickerGenerationService.generateAllAsGrid: start (Imagen 3)');

    final results = <Uint8List?>[];
    for (int i = 0; i < specs.length; i++) {
      final imageBytes = await _generateOne(i, specs[i]);
      results.add(imageBytes);
    }

    final successCount = results.where((b) => b != null).length;
    FirebaseService.log(
      'StickerGenerationService.generateAllAsGrid: done ($successCount/8 succeeded)',
    );
    if (successCount > 0) {
      await FirebaseAnalytics.instance.logEvent(name: 'sticker_images_generated');
    }
    return results;
  }

  // ─── private ────────────────────────────────────────────────────────────

  /// 單張貼圖生成（含重試）
  Future<Uint8List?> _generateOne(int index, StickerSpec spec) async {
    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final body = jsonEncode({
          'instances': [
            {'prompt': _buildStickerPrompt(spec)},
          ],
          'parameters': {
            'sampleCount': 1,
            'aspectRatio': '1:1',
            'outputOptions': {'mimeType': 'image/png'},
          },
        });

        final response = await http
            .post(
              Uri.parse('$_endpoint?key=$_apiKey'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 429) {
          if (attempt < maxRetries) {
            final delay = _parseRetryDelay(response.body) ??
                Duration(seconds: (attempt + 1) * 15);
            FirebaseService.log(
              'StickerGenerationService: sticker[$index] rate-limited, '
              'retry ${attempt + 1}/$maxRetries in ${delay.inSeconds}s',
            );
            await Future.delayed(delay);
            continue;
          }
          _logApiError(429, response.body, attempt, label: 'sticker[$index]');
          return null;
        }

        if (response.statusCode != 200) {
          _logApiError(
            response.statusCode, response.body, attempt,
            label: 'sticker[$index]',
          );
          if (response.statusCode >= 500 && attempt < maxRetries) {
            await Future.delayed(Duration(seconds: (attempt + 1) * 5));
            continue;
          }
          return null;
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final predictions = json['predictions'] as List<dynamic>?;
        if (predictions == null || predictions.isEmpty) {
          _logApiError(
            200, response.body, attempt,
            label: 'sticker[$index] no predictions',
          );
          return null;
        }

        final encoded = predictions[0]['bytesBase64Encoded'] as String?;
        if (encoded == null) {
          _logApiError(
            200, response.body, attempt,
            label: 'sticker[$index] no bytes',
          );
          return null;
        }

        final bytes = base64Decode(encoded);
        FirebaseService.log(
          'StickerGenerationService._generateOne[$index]: ${bytes.lengthInBytes} bytes',
        );
        return bytes;

      } catch (e, stack) {
        await FirebaseService.recordError(
          e, stack, reason: 'sticker_imagen_failed_index_$index',
        );
        return null;
      }
    }

    return null;
  }

  /// API 錯誤時寫入 Crashlytics log（body 超過 4000 字元截斷）
  static void _logApiError(
    int statusCode,
    String body,
    int attempt, {
    String label = '',
  }) {
    const maxLen = 4000;
    final truncated = body.length > maxLen;
    final bodySnippet =
        truncated ? '${body.substring(0, maxLen)}…[truncated]' : body;
    final tag = label.isNotEmpty ? ' ($label)' : '';
    FirebaseService.log(
      '[API ERROR] HTTP $statusCode attempt=${attempt + 1}$tag\n$bodySnippet',
    );
  }

  /// 從錯誤訊息解析「retry in X.Xs」秒數
  static Duration? _parseRetryDelay(String body) {
    final m = RegExp(r'retry in (\d+(?:\.\d+)?)s', caseSensitive: false)
        .firstMatch(body);
    if (m == null) return null;
    final seconds = double.tryParse(m.group(1)!);
    if (seconds == null) return null;
    return Duration(milliseconds: ((seconds + 1) * 1000).round());
  }

  /// 建立單張貼圖的 Imagen prompt
  String _buildStickerPrompt(StickerSpec spec) {
    return 'A single cute chibi LINE sticker illustration. '
        'Circular design with ${spec.bgColor} solid background filling the circle. '
        'Cartoon chibi character with big sparkly eyes, small nose, chubby cheeks, '
        'showing "${spec.emotion}" expression. '
        'Bold rounded Chinese text "${spec.text}" centered at the bottom inside the circle. '
        '3 to 5 small sparkles or themed icons inside the circle. '
        'White 4px outline around the circle. Pure white outside the circle. '
        'Clean flat illustration, thick outlines, no photo-realism. '
        'LINE Friends / Chiikawa quality sticker.';
  }
}

/// Imagen API 呼叫失敗時拋出，攜帶完整錯誤資訊
class StickerApiException implements Exception {
  final int statusCode;
  final String body;

  const StickerApiException(this.statusCode, this.body);

  @override
  String toString() => 'StickerApiException HTTP $statusCode:\n$body';
}
