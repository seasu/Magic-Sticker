import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/sticker_config.dart';

/// 單張 LINE 貼圖合成畫布
///
/// 設計層次（由下到上）：
///   漸層背景 → 裝飾光圈 → 主體（去背 PNG）→ emoji 圖示 → 光暈文字氣泡
///
/// 畫布比例 740:640（LINE 高解析標準）。
class StickerCanvas extends StatelessWidget {
  final Uint8List? subjectBytes;
  final String text;
  final StickerConfig config;

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
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: config.colorScheme.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 裝飾光圈（背景層）────────────────────────────────────
            ..._buildBgCircles(),

            // ── 主體層：去背 PNG ──────────────────────────────────────
            _buildSubject(),

            // ── 裝飾 emoji ───────────────────────────────────────────
            ..._buildIconOverlays(),

            // ── 文字氣泡 ─────────────────────────────────────────────
            Positioned(
              left: 14,
              right: 14,
              bottom: 10,
              child: _GlowBubble(text: text, config: config),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubject() {
    if (subjectBytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      bottom: 72,
      child: Container(
        // 以強調色製造光暈陰影，增加主體立體感
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: config.colorScheme.accent.withOpacity(0.30),
              blurRadius: 32,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Image.memory(
          subjectBytes!,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }

  List<Widget> _buildBgCircles() {
    return [
      Positioned(
        top: -30,
        right: -30,
        child: _Circle(size: 110, opacity: 0.16),
      ),
      Positioned(
        top: 28,
        right: 14,
        child: _Circle(size: 38, opacity: 0.10),
      ),
      Positioned(
        bottom: 78,
        left: -22,
        child: _Circle(size: 70, opacity: 0.12),
      ),
      Positioned(
        bottom: 90,
        right: 38,
        child: _Circle(size: 22, opacity: 0.09),
      ),
    ];
  }

  List<Widget> _buildIconOverlays() {
    final results = <Widget>[];
    for (int i = 0; i < config.iconEmojis.length; i++) {
      final shift = i * 34.0;
      double? top, bottom, left, right;
      switch (config.iconPosition) {
        case StickerIconPosition.topRight:
          top = 8 + shift;
          right = 8;
        case StickerIconPosition.bottomLeft:
          bottom = 70 + shift;
          left = 8;
        case StickerIconPosition.bottomRight:
          bottom = 70 + shift;
          right = 8;
      }
      results.add(
        Positioned(
          top: top,
          bottom: bottom,
          left: left,
          right: right,
          child: Text(
            config.iconEmojis[i],
            style: const TextStyle(
              fontSize: 34,
              height: 1,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(1, 2),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return results;
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final double opacity;

  const _Circle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
      ),
    );
  }
}

/// 帶漸層 + 光暈陰影的文字氣泡
class _GlowBubble extends StatelessWidget {
  final String text;
  final StickerConfig config;

  const _GlowBubble({required this.text, required this.config});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            config.colorScheme.bubbleStart,
            config.colorScheme.bubbleEnd,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withOpacity(0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: config.colorScheme.accent.withOpacity(0.55),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 21,
          fontWeight: FontWeight.w900,
          height: 1.3,
          shadows: [
            Shadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}
