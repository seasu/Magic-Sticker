import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:http/http.dart' as http;

import '../models/sticker_spec.dart';
import 'firebase_service.dart';

/// Gemini 2.0 Flash 圖片生成服務
///
/// 接收由 GeminiService.generateStickerSpecs() 取得的 AI 自由規格，
/// 生成對應的圓形 LINE 貼圖圖片（卡通頭像 + 彩色背景 + 嵌入文字）。
///
/// 注意：需在 dart-define 設定 GEMINI_API_KEY
class StickerGenerationService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta'
      '/models/gemini-2.0-flash-exp:generateContent';

  /// 並行生成全部 8 張貼圖
  Future<List<Uint8List?>> generateAll(
    Uint8List photoBytes,
    List<StickerSpec> specs,
  ) async {
    FirebaseService.log('StickerGenerationService.generateAll: start (8 stickers)');
    final results = await Future.wait(
      List.generate(specs.length, (i) => generateOne(photoBytes, specs[i], i)),
    );
    await FirebaseAnalytics.instance
        .logEvent(name: 'sticker_images_generated');
    return results;
  }

  /// 生成單張貼圖，規格由 AI 自由決定的 [spec] 提供
  Future<Uint8List?> generateOne(
    Uint8List photoBytes,
    StickerSpec spec,
    int index,
  ) async {
    FirebaseService.log(
        'StickerGenerationService.generateOne: #$index "${spec.text}"');
    try {
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _buildPrompt(spec)},
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
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        FirebaseService.log(
          'StickerGenerationService: HTTP ${response.statusCode} '
          'for #$index — ${response.body.substring(0, 200)}',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final parts =
          json['candidates'][0]['content']['parts'] as List<dynamic>;

      for (final part in parts) {
        if (part is Map<String, dynamic> &&
            part.containsKey('inlineData')) {
          final mimeType = part['inlineData']['mimeType'] as String;
          if (mimeType.startsWith('image/')) {
            final bytes =
                base64Decode(part['inlineData']['data'] as String);
            FirebaseService.log(
                'StickerGenerationService: #$index done '
                '(${bytes.lengthInBytes} bytes)');
            return bytes;
          }
        }
      }

      FirebaseService.log(
          'StickerGenerationService: no image part for #$index');
      return null;
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'sticker_image_gen_failed',
      );
      return null;
    }
  }

  /// 根據 AI 自由規格建立 Gemini 圖片生成 prompt
  String _buildPrompt(StickerSpec spec) => '''
You are a professional LINE sticker illustrator. Create ONE circular LINE sticker based on the person's face in the provided photo.

STICKER DESIGN SPECIFICATIONS:
- Canvas: 370 × 370 px square, pure WHITE background outside the circle
- Main shape: A large filled circle (340px diameter, centered) with solid background color: ${spec.bgColor}
- Face: Draw a CUTE CHIBI/Q-VERSION cartoon face of the person in the photo
  * Simplify the face into rounded cute features: big sparkly eyes, small nose, chubby cheeks
  * The cartoon face should fill about 60-70% of the circle area (upper portion)
  * Expression: ${spec.emotion}
  * Style: clean flat illustration, thick outlines (2-3px), no photo-realism
- Chinese text: Write "${spec.text}" in bold rounded Chinese font
  * Position: bottom 25% area INSIDE the circle
  * Text color: WHITE with dark drop shadow for readability
  * Font size: large (approx 36-40px equivalent), bold, clearly legible
- Decorations inside the circle: add 3-5 small sparkle/star elements (✦ ★ ✨ small hearts or themed icons matching the emotion)
  * Scatter around the face and near the text
  * Colors should complement the background

STYLE REFERENCES: LINE Friends, Chiikawa, Molang — professional sticker quality with clean illustration
IMPORTANT: The circle must have a thick white outline (4px) to separate it from white background. Do NOT add text outside the circle. Keep design simple and cute.

Output: The sticker image only. No captions or explanations.
''';
}
