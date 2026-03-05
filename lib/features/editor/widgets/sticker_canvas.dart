import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/sticker_config.dart';

/// 單張 LINE 貼圖合成畫布
///
/// 層次（由下到上）：主體層 → 裝飾圖示層 → 文字氣泡層
/// 背景為透明，符合 LINE 貼圖 PNG 規格。
/// 畫布比例 740:640（LINE 高解析標準）。
class StickerCanvas extends StatelessWidget {
  final Uint8List? subjectBytes;
  final String text;
  final StickerConfig config;

  /// LINE 貼圖標準比例 740 : 640
  static const double aspectRatio = 740 / 640;

  const StickerCanvas({
    super.key,
    required this.subjectBytes,
    required this.text,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 主體層：去背後透明底 PNG，底部留空給文字氣泡 ──────────
          if (subjectBytes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
              child: Image.memory(subjectBytes!, fit: BoxFit.contain),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // ── 裝飾圖示層 ─────────────────────────────────────────
          ..._buildIconOverlays(),

          // ── 文字氣泡層 ─────────────────────────────────────────
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _TextBubble(text: text, config: config),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildIconOverlays() {
    final results = <Widget>[];
    for (int i = 0; i < config.iconEmojis.length; i++) {
      results.add(_buildIcon(config.iconEmojis[i], config.iconPosition, i));
    }
    return results;
  }

  Widget _buildIcon(String emoji, StickerIconPosition pos, int index) {
    // 第二個圖示稍微偏移，避免重疊
    final shift = index * 28.0;
    double? top, bottom, left, right;

    switch (pos) {
      case StickerIconPosition.topRight:
        top = 8 + shift;
        right = 8;
      case StickerIconPosition.bottomLeft:
        bottom = 58 + shift; // 58 = 高於文字氣泡
        left = 8;
      case StickerIconPosition.bottomRight:
        bottom = 58 + shift;
        right = 8;
    }

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Text(
        emoji,
        style: const TextStyle(fontSize: 30, height: 1),
      ),
    );
  }
}

class _TextBubble extends StatelessWidget {
  final String text;
  final StickerConfig config;

  const _TextBubble({required this.text, required this.config});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: config.colorScheme.bubbleColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: config.colorScheme.textColor,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          height: 1.25,
        ),
      ),
    );
  }
}
