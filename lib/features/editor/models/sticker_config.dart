import 'package:flutter/material.dart';

enum StickerIconPosition { topRight, topLeft, bottomRight }

class StickerColorScheme {
  final Color borderColor;   // 外框 & 文字 stroke 顏色
  final Color accentColor;   // 裝飾元素（星星、愛心）填色
  final Color textFill;      // 主文字填色
  final Color sparkColor;    // 小sparkle元素顏色

  const StickerColorScheme({
    required this.borderColor,
    required this.accentColor,
    required this.textFill,
    required this.sparkColor,
  });
}

class StickerConfig {
  final StickerColorScheme colorScheme;
  final List<StickerDecor> decorations;

  const StickerConfig({
    required this.colorScheme,
    required this.decorations,
  });
}

/// 單一裝飾元素（位置、內容、旋轉）
class StickerDecor {
  final String symbol;   // emoji 或 unicode 符號
  final double top;
  final double? right;
  final double? left;
  final double? bottom;
  final double angle;   // 旋轉角度（radians）
  final double size;

  const StickerDecor({
    required this.symbol,
    this.top = 0,
    this.right,
    this.left,
    this.bottom,
    this.angle = 0,
    this.size = 26,
  });
}

/// 8 張貼圖 fallback 配置（對應 8 種情感）
/// 僅在 AI 圖生成失敗時使用
const kStickerConfigs = [
  // Sticker 1：哈囉！— 暖橘活力
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFF4A261),
      accentColor: Color(0xFFFF9F1C),
      textFill: Color(0xFFF4A261),
      sparkColor: Color(0xFFFFCC02),
    ),
    decorations: [
      StickerDecor(symbol: '👋', top: 10, right: 10, angle: 0.3, size: 28),
      StickerDecor(symbol: '✨', top: 36, right: 8, angle: -0.2, size: 20),
      StickerDecor(symbol: '✦', top: 12, left: 12, angle: 0.5, size: 16),
      StickerDecor(symbol: '⭐', bottom: 64, right: 14, angle: 0.15, size: 22),
      StickerDecor(symbol: '★', bottom: 68, left: 16, angle: -0.4, size: 18),
    ],
  ),
  // Sticker 2：太棒了！— 天空藍
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFF74C0FC),
      accentColor: Color(0xFF4DABF7),
      textFill: Color(0xFF1971C2),
      sparkColor: Color(0xFFBBD8FB),
    ),
    decorations: [
      StickerDecor(symbol: '👍', top: 8, right: 10, angle: 0.2, size: 28),
      StickerDecor(symbol: '✨', top: 10, left: 8, angle: -0.3, size: 24),
      StickerDecor(symbol: '★', top: 36, right: 6, angle: 0.4, size: 18),
      StickerDecor(symbol: '✦', bottom: 66, right: 12, angle: -0.2, size: 18),
      StickerDecor(symbol: '⭐', bottom: 62, left: 18, angle: 0.1, size: 22),
    ],
  ),
  // Sticker 3：真的嗎？— 金黃驚訝
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFFFD43B),
      accentColor: Color(0xFFFFA94D),
      textFill: Color(0xFFE67700),
      sparkColor: Color(0xFFFFEC99),
    ),
    decorations: [
      StickerDecor(symbol: '❓', top: 8, right: 8, angle: 0.2, size: 28),
      StickerDecor(symbol: '❓', top: 10, left: 10, angle: -0.3, size: 22),
      StickerDecor(symbol: '❕', top: 38, right: 6, angle: 0.4, size: 20),
      StickerDecor(symbol: '💭', bottom: 66, right: 12, angle: -0.2, size: 24),
      StickerDecor(symbol: '✦', bottom: 62, left: 18, angle: 0.1, size: 16),
    ],
  ),
  // Sticker 4：尷尬了...— 粉嫩害羞
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFE91E8C),
      accentColor: Color(0xFFFF4FA1),
      textFill: Color(0xFFE91E8C),
      sparkColor: Color(0xFFFF80C8),
    ),
    decorations: [
      StickerDecor(symbol: '💦', top: 8, right: 8, angle: 0.2, size: 26),
      StickerDecor(symbol: '😅', top: 10, left: 10, angle: -0.3, size: 24),
      StickerDecor(symbol: '💧', top: 38, right: 6, angle: 0.4, size: 18),
      StickerDecor(symbol: '✿', bottom: 66, right: 12, angle: -0.2, size: 20),
      StickerDecor(symbol: '·', bottom: 62, left: 18, angle: 0.1, size: 28),
    ],
  ),
  // Sticker 5：哼！— 火焰憤怒
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFFF6B6B),
      accentColor: Color(0xFFFF4444),
      textFill: Color(0xFFC92A2A),
      sparkColor: Color(0xFFFFAA00),
    ),
    decorations: [
      StickerDecor(symbol: '🔥', top: 8, right: 8, angle: 0.1, size: 28),
      StickerDecor(symbol: '🔥', top: 10, left: 10, angle: -0.2, size: 24),
      StickerDecor(symbol: '💢', top: 36, right: 6, angle: 0.3, size: 22),
      StickerDecor(symbol: '⚡', bottom: 66, right: 12, angle: -0.1, size: 20),
      StickerDecor(symbol: '💥', bottom: 62, left: 16, angle: 0.2, size: 22),
    ],
  ),
  // Sticker 6：開心！— 清新薄荷
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFF63E6BE),
      accentColor: Color(0xFF38D9A9),
      textFill: Color(0xFF099268),
      sparkColor: Color(0xFFC3FAE8),
    ),
    decorations: [
      StickerDecor(symbol: '🌈', top: 8, right: 10, angle: -0.2, size: 28),
      StickerDecor(symbol: '🎉', top: 10, left: 8, angle: 0.3, size: 24),
      StickerDecor(symbol: '✨', top: 36, right: 8, angle: 0.5, size: 18),
      StickerDecor(symbol: '🎊', bottom: 66, right: 14, angle: -0.3, size: 20),
      StickerDecor(symbol: '★', bottom: 64, left: 16, angle: 0.4, size: 20),
    ],
  ),
  // Sticker 7：我想想...— 薰衣草沉思
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFC084FC),
      accentColor: Color(0xFFAE3EC9),
      textFill: Color(0xFF862E9C),
      sparkColor: Color(0xFFEECEFF),
    ),
    decorations: [
      StickerDecor(symbol: '💭', top: 8, right: 10, angle: -0.2, size: 28),
      StickerDecor(symbol: '❓', top: 10, left: 8, angle: 0.3, size: 22),
      StickerDecor(symbol: '✦', top: 36, right: 8, angle: 0.5, size: 16),
      StickerDecor(symbol: '🔮', bottom: 66, right: 14, angle: -0.3, size: 20),
      StickerDecor(symbol: '✧', bottom: 64, left: 16, angle: 0.4, size: 18),
    ],
  ),
  // Sticker 8：再見囉！— 嬰兒藍道別
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFADE8F4),
      accentColor: Color(0xFF90E0EF),
      textFill: Color(0xFF0077B6),
      sparkColor: Color(0xFFCAF0F8),
    ),
    decorations: [
      StickerDecor(symbol: '👋', top: 8, right: 10, angle: -0.2, size: 28),
      StickerDecor(symbol: '😎', top: 10, left: 8, angle: 0.3, size: 24),
      StickerDecor(symbol: '✦', top: 36, right: 8, angle: 0.5, size: 16),
      StickerDecor(symbol: '✨', bottom: 66, right: 14, angle: -0.3, size: 20),
      StickerDecor(symbol: '★', bottom: 64, left: 16, angle: 0.4, size: 18),
    ],
  ),
];
