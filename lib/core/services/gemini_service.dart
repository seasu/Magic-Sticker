import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/sticker_spec.dart';
import 'firebase_service.dart';

/// 8 組預設 fallback（API 失敗時使用）
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
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
    );
  }

  /// 根據照片，讓 AI 自由決定 8 張貼圖的【情感主題、中文標語、背景色】
  ///
  /// AI 會分析照片中人物的氛圍、個性、場景，創意發揮 8 種情感組合。
  /// 回傳 List<StickerSpec>（長度固定 8）；失敗時使用 fallback。
  Future<List<StickerSpec>> generateStickerSpecs(Uint8List imageBytes) async {
    FirebaseService.log('GeminiService.generateStickerSpecs: start');
    try {
      final response = await _model.generateContent([
        Content.multi([
          TextPart(
            '你是一位創意 LINE 貼圖設計師，擅長根據照片人物的個性與氛圍，'
            '設計出最適合的貼圖情感組合。\n\n'
            '請仔細觀察照片中人物的外型、氣質、表情與場景，'
            '為他們設計專屬的 8 張 LINE 貼圖規格。\n\n'
            '每張貼圖請【自由發揮】，無需使用固定情感模板。'
            '可以根據人物特色選擇有趣、幽默、溫馨或獨特的情感表達。\n\n'
            '輸出格式：僅回傳 JSON 陣列（8 個物件），每個物件包含：\n'
            '- "text": 繁體中文標語（2–6 字，口語化有趣，適合貼圖）\n'
            '- "emotion": 英文情感描述（用於繪製卡通表情，例如 "laughing with tears", "smugly confident"）\n'
            '- "bgColor": 背景色描述（英文色名 + hex，例如 "coral red #FF6B6B"）\n\n'
            '範例格式（不要照抄，請根據照片創作）：\n'
            '[{"text":"哈囉！","emotion":"cheerfully waving hello","bgColor":"warm peach #F4A261"}]',
          ),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(const Duration(seconds: 15));

      final raw = response.text ?? '';
      final match = RegExp(r'\[.*?\]', dotAll: true).firstMatch(raw);
      if (match != null) {
        final list = (jsonDecode(match.group(0)!) as List)
            .cast<Map<String, dynamic>>();
        if (list.length >= 8) {
          final specs = list.take(8).map(StickerSpec.fromJson).toList();
          FirebaseService.log('GeminiService.generateStickerSpecs: done');
          await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_generated');
          return specs;
        }
      }
      throw FormatException('Unexpected response format: $raw');
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'gemini_sticker_specs_failed',
      );
      await FirebaseAnalytics.instance.logEvent(name: 'ai_specs_fallback');
      return _kFallbackSpecs.map(StickerSpec.fromJson).toList();
    }
  }
}
