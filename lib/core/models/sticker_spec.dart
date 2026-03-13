/// AI 根據情感類別生成的貼圖規格
///
/// 由 GeminiService.generateStickerSpecs() 取得，
/// 再傳入 StickerGenerationService.generateOne() 用於圖片生成。
class StickerSpec {
  /// 嵌入貼圖圓圈內的中文標語（2–6 字）
  final String text;

  /// 情感描述（英文），用於圖片生成 prompt 的表情指引
  final String emotion;

  /// 圓形背景色描述（含色名 + hex，例如 "warm coral #FF6B6B"）
  final String bgColor;

  /// 對應的情感類別 ID（對應 EmotionCategory.id，例如 "greeting"）
  final String categoryId;

  const StickerSpec({
    required this.text,
    required this.emotion,
    required this.bgColor,
    this.categoryId = '',
  });

  factory StickerSpec.fromJson(Map<String, dynamic> json) => StickerSpec(
        text: (json['text'] as String? ?? '').trim(),
        emotion: (json['emotion'] as String? ?? 'cheerful').trim(),
        bgColor: (json['bgColor'] as String? ?? 'soft blue #74C0FC').trim(),
        categoryId: (json['categoryId'] as String? ?? '').trim(),
      );
}
