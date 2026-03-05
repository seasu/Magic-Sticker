import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import 'firebase_service.dart';

const _kFallbackTexts = ['好棒！', '讚喔', '超可愛✨'];

class GeminiService {
  static const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
    );
  }

  /// 依照照片內容，生成 3 組符合情境的 LINE 貼圖短文字（2–6 字）
  ///
  /// 回傳長度固定為 3；API 失敗或逾時（10 秒）時自動使用 Fallback。
  Future<List<String>> generateStickerTexts(Uint8List imageBytes) async {
    FirebaseService.log('GeminiService.generateStickerTexts: start');
    try {
      final response = await _model.generateContent([
        Content.multi([
          TextPart(
            '你是 LINE 貼圖文字設計師。\n'
            '請根據這張照片的內容與氛圍，產出 3 組繁體中文短文字，格式如下：\n'
            '- 每組 2–6 字，口語化、有趣、適合貼圖\n'
            '- 風格：正向、可愛、日常\n'
            '- 禁止重複\n'
            '- 僅回傳 JSON 陣列，例如：["好棒喔！", "讚啦", "超可愛✨"]',
          ),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(const Duration(seconds: 10));

      final raw = response.text ?? '';
      // 從回傳文字中擷取 JSON 陣列（允許前後有說明文字）
      final match = RegExp(r'\[.*?\]', dotAll: true).firstMatch(raw);
      if (match != null) {
        final list = (jsonDecode(match.group(0)!) as List).cast<String>();
        if (list.length >= 3) {
          FirebaseService.log('GeminiService.generateStickerTexts: done');
          await FirebaseAnalytics.instance.logEvent(name: 'ai_text_generated');
          return list.take(3).toList();
        }
      }
      throw FormatException('Unexpected response format: $raw');
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'gemini_sticker_texts_failed',
      );
      await FirebaseAnalytics.instance.logEvent(name: 'ai_text_fallback');
      return List.from(_kFallbackTexts);
    }
  }
}
