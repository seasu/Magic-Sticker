import 'package:flutter/material.dart';

enum StickerIconPosition { topRight, bottomLeft, bottomRight }

class StickerColorScheme {
  final List<Color> gradient;   // 背景漸層（topLeft → bottomRight）
  final Color accent;           // 強調色（光暈、陰影色調）
  final Color bubbleStart;      // 氣泡漸層上色
  final Color bubbleEnd;        // 氣泡漸層下色（深色）

  const StickerColorScheme({
    required this.gradient,
    required this.accent,
    required this.bubbleStart,
    required this.bubbleEnd,
  });
}

class StickerConfig {
  final StickerIconPosition iconPosition;
  final List<String> iconEmojis;
  final StickerColorScheme colorScheme;

  const StickerConfig({
    required this.iconPosition,
    required this.iconEmojis,
    required this.colorScheme,
  });
}

/// 3 張貼圖的預設配置
const kStickerConfigs = [
  // Sticker 1：Warm Sunshine（深橘 → 陽光黃）
  StickerConfig(
    iconPosition: StickerIconPosition.topRight,
    iconEmojis: ['✨', '⭐'],
    colorScheme: StickerColorScheme(
      gradient: [Color(0xFFFF7043), Color(0xFFFFD54F)],
      accent: Color(0xFFE64A19),
      bubbleStart: Color(0xFFFF8C00),
      bubbleEnd: Color(0xFFE65100),
    ),
  ),
  // Sticker 2：Cherry Blossom（桃粉 → 淡粉）
  StickerConfig(
    iconPosition: StickerIconPosition.bottomLeft,
    iconEmojis: ['💖', '🌸'],
    colorScheme: StickerColorScheme(
      gradient: [Color(0xFFEC407A), Color(0xFFFF80AB)],
      accent: Color(0xFFC2185B),
      bubbleStart: Color(0xFFE91E63),
      bubbleEnd: Color(0xFFC2185B),
    ),
  ),
  // Sticker 3：Aqua Dream（青藍 → 海洋藍）
  StickerConfig(
    iconPosition: StickerIconPosition.bottomRight,
    iconEmojis: ['🌟', '💫'],
    colorScheme: StickerColorScheme(
      gradient: [Color(0xFF26C6DA), Color(0xFF42A5F5)],
      accent: Color(0xFF00838F),
      bubbleStart: Color(0xFF00BCD4),
      bubbleEnd: Color(0xFF0097A7),
    ),
  ),
];
