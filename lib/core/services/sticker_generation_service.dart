import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:http/http.dart' as http;

import 'firebase_service.dart';

/// Gemini 2.0 Flash 圖片生成服務
///
/// 針對使用者上傳的照片，呼叫 Gemini 2.0 Flash Experimental 產生
/// 3 種配色的 LINE 貼圖插圖（**不含文字**；文字由 Flutter 疊上）。
///
/// API 文件：
/// https://ai.google.dev/gemini-api/docs/image-generation
///
/// 注意：需在 dart-define 設定 GEMINI_API_KEY
class StickerGenerationService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta'
      '/models/gemini-2.0-flash-exp:generateContent';

  /// 每種貼圖的主色調描述（傳入 prompt 影響配色）
  static const _kPalettes = [
    'warm orange and sunny yellow — energetic, bright, cheerful',
    'soft cherry pink and coral — cute, sweet, kawaii',
    'fresh cyan blue and aqua — cool, playful, refreshing',
  ];

  /// 同時生成 3 張貼圖插圖，各自獨立，若某張失敗回傳 null（使用 Flutter fallback）
  ///
  /// 呼叫者應在背景執行，不阻塞 UI。
  Future<List<Uint8List?>> generateAll(Uint8List photoBytes) async {
    FirebaseService.log('StickerGenerationService.generateAll: start');
    // 3 張並行生成（speed > 3× sequential）
    final results = await Future.wait(
      List.generate(3, (i) => generateOne(photoBytes, i)),
    );
    await FirebaseAnalytics.instance
        .logEvent(name: 'sticker_images_generated');
    return results;
  }

  /// 生成單張貼圖插圖，[styleIndex] 決定配色（0=橘、1=粉、2=藍）
  Future<Uint8List?> generateOne(Uint8List photoBytes, int styleIndex) async {
    FirebaseService.log(
        'StickerGenerationService.generateOne: style=$styleIndex');
    try {
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _buildPrompt(_kPalettes[styleIndex % 3])},
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
          // IMAGE 輸出需明確指定 responseModalities
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
          'for style=$styleIndex — ${response.body.substring(0, 200)}',
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
                'StickerGenerationService: style=$styleIndex done '
                '(${bytes.lengthInBytes} bytes)');
            return bytes;
          }
        }
      }

      FirebaseService.log(
          'StickerGenerationService: no image part for style=$styleIndex');
      return null;
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'sticker_image_gen_failed',
      );
      return null;
    }
  }

  /// Gemini prompt：要求生成 LINE 貼圖插圖（**不含文字**）
  ///
  /// 關鍵設計原則：
  /// 1. 明確要求白底
  /// 2. Q 版/Chibi 卡通風格
  /// 3. 不要在圖中放文字（文字由 Flutter 疊加）
  /// 4. 四周保留 80px 空間給文字氣泡
  /// 5. 加入 LINE 貼圖特有的裝飾（閃光、外框線）
  String _buildPrompt(String palette) => '''
You are a professional LINE sticker illustrator. Draw ONE cute LINE sticker illustration based on the subject in the provided photo.

Art direction:
- Color palette: $palette
- Pure WHITE background (mandatory — no gradients, no patterns)
- Illustrate the main subject (person, pet, or object) in a cute chibi/Q-version cartoon style
- The subject should be simplified, round, with big expressive eyes and exaggerated cute features
- Add sparkle decorations (✦ ✨ ★ small stars/hearts) scattered around the subject
- Draw a thick colored rounded-rectangle border (5–6 px) matching the palette
- Canvas aspect ratio: 740 wide : 640 tall
- Leave the bottom 80px of the canvas EMPTY (white) — this space is reserved for text overlay
- Do NOT draw any text or letters anywhere in the image
- Style references: LINE Friends, Molang, Gudetama, Chiikawa — clean professional sticker quality

Output: The sticker illustration image only. No captions, no explanations.
''';
}
