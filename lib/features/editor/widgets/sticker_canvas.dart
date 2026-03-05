import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/sticker_config.dart';

/// LINE 貼圖風格畫布
///
/// 設計語言：
/// - 白底透明背景（符合 LINE 貼圖 PNG 規格）
/// - 彩色粗外框線（6px rounded rect border）
/// - 主體去背圖像居中
/// - 大字、粗外框 outline 文字（類 LINE 貼圖感）
/// - 散落裝飾符號（emoji/unicode，微旋轉）
///
/// 畫布比例 740 : 640（LINE 高解析標準）
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
        color: Colors.white,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 彩色粗外框 ─────────────────────────────────────────
            _BorderFrame(color: config.colorScheme.borderColor),

            // ── 背景裝飾（主體後方） ──────────────────────────────
            ..._buildDecorations(foreground: false),

            // ── 主體去背圖像 ─────────────────────────────────────
            _buildSubject(),

            // ── 前景裝飾（主體前方，部分重疊） ───────────────────
            ..._buildDecorations(foreground: true),

            // ── LINE 貼圖風格大字 ─────────────────────────────────
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: _OutlinedStickerText(text: text, config: config),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubject() {
    if (subjectBytes == null) {
      return Center(
        child: CircularProgressIndicator(
          color: config.colorScheme.borderColor,
        ),
      );
    }
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      bottom: 62,
      child: Image.memory(
        subjectBytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }

  List<Widget> _buildDecorations({required bool foreground}) {
    // 偶數索引 = 背景層；奇數索引 = 前景層
    final results = <Widget>[];
    for (int i = 0; i < config.decorations.length; i++) {
      final isForeground = i.isOdd;
      if (isForeground != foreground) continue;

      final d = config.decorations[i];
      results.add(
        Positioned(
          top: d.top > 0 ? d.top : null,
          bottom: d.bottom != null ? d.bottom : null,
          left: d.left,
          right: d.right,
          child: Transform.rotate(
            angle: d.angle,
            child: Text(
              d.symbol,
              style: TextStyle(
                fontSize: d.size,
                height: 1,
                color: config.colorScheme.accentColor,
              ),
            ),
          ),
        ),
      );
    }
    return results;
  }
}

// ─── 彩色外框 ─────────────────────────────────────────────────────────────

class _BorderFrame extends StatelessWidget {
  final Color color;

  const _BorderFrame({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 5),
      ),
    );
  }
}

// ─── LINE 貼圖風格：粗 outline 文字 ──────────────────────────────────────

/// 外框文字效果：
///   1. 先畫 Paint.stroke（白色粗框）
///   2. 再畫 Paint.fill（主色填充）
///   3. 整體放在彩色膠囊背景上
class _OutlinedStickerText extends StatelessWidget {
  final String text;
  final StickerConfig config;

  const _OutlinedStickerText({required this.text, required this.config});

  static const _kFontSize = 26.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: config.colorScheme.borderColor,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: config.colorScheme.borderColor.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 白色粗外框（stroke）
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _kFontSize,
              fontWeight: FontWeight.w900,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 6
                ..strokeJoin = StrokeJoin.round
                ..color = Colors.white,
            ),
          ),
          // 主色填充（fill）
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _kFontSize,
              fontWeight: FontWeight.w900,
              color: config.colorScheme.textFill,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
