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
  final List<_StickerDecor> decorations;

  const StickerConfig({
    required this.colorScheme,
    required this.decorations,
  });
}

/// 單一裝飾元素（位置、內容、旋轉）
class _StickerDecor {
  final String symbol;   // emoji 或 unicode 符號
  final double top;
  final double? right;
  final double? left;
  final double? bottom;
  final double angle;   // 旋轉角度（radians）
  final double size;

  const _StickerDecor({
    required this.symbol,
    this.top = 0,
    this.right,
    this.left,
    this.bottom,
    this.angle = 0,
    this.size = 26,
  });
}

/// 3 張貼圖配置
const kStickerConfigs = [
  // Sticker 1：暖橘活力
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFFF6B35),
      accentColor: Color(0xFFFF9F1C),
      textFill: Color(0xFFFF6B35),
      sparkColor: Color(0xFFFFCC02),
    ),
    decorations: [
      _StickerDecor(symbol: '⭐', top: 10, right: 10, angle: 0.3, size: 28),
      _StickerDecor(symbol: '✨', top: 36, right: 8, angle: -0.2, size: 20),
      _StickerDecor(symbol: '✦', top: 12, left: 12, angle: 0.5, size: 16),
      _StickerDecor(symbol: '！', bottom: 64, right: 14, angle: 0.15, size: 22),
      _StickerDecor(symbol: '★', bottom: 68, left: 16, angle: -0.4, size: 18),
    ],
  ),
  // Sticker 2：粉嫩甜心
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFFE91E8C),
      accentColor: Color(0xFFFF4FA1),
      textFill: Color(0xFFE91E8C),
      sparkColor: Color(0xFFFF80C8),
    ),
    decorations: [
      _StickerDecor(symbol: '💕', top: 8, right: 8, angle: 0.2, size: 26),
      _StickerDecor(symbol: '🌸', top: 10, left: 10, angle: -0.3, size: 24),
      _StickerDecor(symbol: '♥', top: 38, right: 6, angle: 0.4, size: 18),
      _StickerDecor(symbol: '✿', bottom: 66, right: 12, angle: -0.2, size: 20),
      _StickerDecor(symbol: '·', bottom: 62, left: 18, angle: 0.1, size: 28),
    ],
  ),
  // Sticker 3：清新天藍
  StickerConfig(
    colorScheme: StickerColorScheme(
      borderColor: Color(0xFF0096C7),
      accentColor: Color(0xFF00B4D8),
      textFill: Color(0xFF0096C7),
      sparkColor: Color(0xFF90E0EF),
    ),
    decorations: [
      _StickerDecor(symbol: '🌟', top: 8, right: 10, angle: -0.2, size: 26),
      _StickerDecor(symbol: '💫', top: 10, left: 8, angle: 0.3, size: 24),
      _StickerDecor(symbol: '✦', top: 36, right: 8, angle: 0.5, size: 16),
      _StickerDecor(symbol: '◎', bottom: 66, right: 14, angle: -0.3, size: 18),
      _StickerDecor(symbol: '✧', bottom: 64, left: 16, angle: 0.4, size: 20),
    ],
  ),
];
