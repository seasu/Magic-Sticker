import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:http/http.dart' as http;

import '../models/sticker_spec.dart';
import '../models/sticker_style.dart';
import 'firebase_service.dart';

/// Gemini 貼圖生成服務
///
/// 每張貼圖獨立呼叫 API（1 call per sticker），不再依賴 grid 切割。
/// 好處：Gemini 不需要遵守多欄/多列排版，每次只畫 1 個圓形貼圖，結果最穩定。
///
/// 注意：需在 dart-define 設定 GEMINI_API_KEY
class StickerGenerationService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta'
      '/models/gemini-2.5-flash-image:generateContent';

  /// 生成單張貼圖，回傳 PNG bytes；失敗回傳 null
  ///
  /// [styleIndex] 對應 [StickerStyle.values] 的索引（預設 0 = Q版卡通）
  Future<Uint8List?> generateSingle(
    Uint8List photoBytes,
    StickerSpec spec, {
    int index = 0,
    int styleIndex = 0,
  }) async {
    final style = StickerStyle.values[styleIndex.clamp(0, StickerStyle.values.length - 1)];
    FirebaseService.log(
      'StickerGenerationService.generateSingle: index=$index '
      'emotion=${spec.emotion} style=${style.label}',
    );

    const maxRetries = 3;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final body = jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': _buildSinglePrompt(spec, style)},
                {
                  'inlineData': {
                    'mimeType': 'image/jpeg',
                    'data': base64Encode(photoBytes),
                  }
                },
              ],
            }
          ],
          'generationConfig': {
            'responseModalities': ['IMAGE', 'TEXT'],
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
              'StickerGenerationService: rate-limited index=$index, '
              'retry ${attempt + 1}/$maxRetries in ${delay.inSeconds}s',
            );
            await Future.delayed(delay);
            continue;
          }
          _logApiError(429, response.body, attempt, index: index);
          throw StickerApiException(429, response.body);
        }

        if (response.statusCode != 200) {
          _logApiError(response.statusCode, response.body, attempt,
              index: index);
          if (response.statusCode >= 500 && attempt < maxRetries) {
            await Future.delayed(Duration(seconds: (attempt + 1) * 5));
            continue;
          }
          throw StickerApiException(response.statusCode, response.body);
        }

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final parts =
            json['candidates'][0]['content']['parts'] as List<dynamic>;

        for (final part in parts) {
          if (part is Map<String, dynamic> && part.containsKey('inlineData')) {
            final mimeType = part['inlineData']['mimeType'] as String;
            if (mimeType.startsWith('image/')) {
              final bytes =
                  base64Decode(part['inlineData']['data'] as String);
              FirebaseService.log(
                'StickerGenerationService: index=$index OK '
                '(${bytes.lengthInBytes} bytes)',
              );
              await FirebaseAnalytics.instance
                  .logEvent(name: 'sticker_image_generated');
              return bytes;
            }
          }
        }

        _logApiError(200, response.body, attempt,
            index: index, label: 'no image part');
        throw StickerApiException(
            200, 'API 回傳無圖片 index=$index:\n${response.body}');
      } catch (e, stack) {
        if (e is StickerApiException) rethrow;
        await FirebaseService.recordError(
          e, stack,
          reason: 'sticker_single_gen_failed_index$index',
        );
        return null;
      }
    }

    return null;
  }

  // ─── private ────────────────────────────────────────────────────────────

  /// 單張貼圖 prompt：只產生一個圓形貼圖，最簡單最穩定
  String _buildSinglePrompt(StickerSpec spec, StickerStyle style) {
    return '''
You are a professional LINE sticker illustrator. Draw ONE single circular sticker based on the person's face in the reference photo.

DESIGN REQUIREMENTS:
- A single large filled circle, centered, occupying ~90% of the square canvas
- Circle background color: ${spec.bgColor}
- Character expression / pose: ${spec.emotion}
- ${style.characterDesc}
- DO NOT draw any text or letters inside the image
- 3–5 small sparkles / stars scattered inside the circle
- White outline (4 px) around the circle
- White background outside the circle

OUTPUT: A single square image containing exactly this ONE sticker.
STYLE: ${style.promptSuffix}
''';
  }

  /// API 錯誤時寫入 Crashlytics log
  static void _logApiError(
    int statusCode,
    String body,
    int attempt, {
    int index = -1,
    String label = '',
  }) {
    const maxLen = 4000;
    final truncated = body.length > maxLen;
    final bodySnippet =
        truncated ? '${body.substring(0, maxLen)}…[truncated]' : body;
    final tag = [
      if (index >= 0) 'index=$index',
      if (label.isNotEmpty) label,
    ].join(' ');
    FirebaseService.log(
      '[API ERROR] HTTP $statusCode attempt=${attempt + 1}'
      '${tag.isNotEmpty ? " ($tag)" : ""}\n$bodySnippet',
    );
  }

  /// 從 Gemini 錯誤訊息解析「retry in X.Xs」秒數
  static Duration? _parseRetryDelay(String body) {
    final m = RegExp(r'retry in (\d+(?:\.\d+)?)s', caseSensitive: false)
        .firstMatch(body);
    if (m == null) return null;
    final seconds = double.tryParse(m.group(1)!);
    if (seconds == null) return null;
    return Duration(milliseconds: ((seconds + 1) * 1000).round());
  }
}

/// Gemini API 呼叫失敗時拋出，攜帶完整錯誤資訊供 UI 顯示
class StickerApiException implements Exception {
  final int statusCode;
  final String body;

  const StickerApiException(this.statusCode, this.body);

  @override
  String toString() => 'StickerApiException HTTP $statusCode:\n$body';
}
