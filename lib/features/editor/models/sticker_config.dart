import 'package:flutter/material.dart';

enum StickerIconPosition { topRight, bottomLeft, bottomRight }

class StickerColorScheme {
  final Color bubbleColor;
  final Color textColor;

  const StickerColorScheme({
    required this.bubbleColor,
    required this.textColor,
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

/// 3 張貼圖的預設配置（圖示位置 / emoji / 配色）
const kStickerConfigs = [
  // Sticker 1：暖橘 / 陽光黃
  StickerConfig(
    iconPosition: StickerIconPosition.topRight,
    iconEmojis: ['⭐', '✨'],
    colorScheme: StickerColorScheme(
      bubbleColor: Color(0xFFFF9800),
      textColor: Colors.white,
    ),
  ),
  // Sticker 2：粉紅 / 珊瑚色
  StickerConfig(
    iconPosition: StickerIconPosition.bottomLeft,
    iconEmojis: ['🌸', '❤️'],
    colorScheme: StickerColorScheme(
      bubbleColor: Color(0xFFE91E63),
      textColor: Colors.white,
    ),
  ),
  // Sticker 3：薄荷綠 / 天空藍
  StickerConfig(
    iconPosition: StickerIconPosition.bottomRight,
    iconEmojis: ['✨', '😊'],
    colorScheme: StickerColorScheme(
      bubbleColor: Color(0xFF43A047),
      textColor: Colors.white,
    ),
  ),
];
