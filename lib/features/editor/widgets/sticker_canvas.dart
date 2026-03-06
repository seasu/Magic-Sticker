import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/sticker_config.dart';

/// LINE 貼圖風格畫布（支援雙指縮放 + 拖曳移位）
///
/// 設計語言：
/// - 透明背景（符合 LINE Creators Market PNG 規格：透明底 + 10px 留白）
/// - 彩色粗外框線（6px rounded rect border），作為貼圖輪廓設計元素
/// - 主體去背圖像居中；支援 pinch-to-zoom + drag
/// - 大字、粗外框 outline 文字（類 LINE 貼圖感）
/// - 散落裝飾符號（emoji/unicode，微旋轉）
///
/// 畫布比例 740 : 640 → 輸出 370×320 px（LINE Creators Market 規格）
class StickerCanvas extends StatefulWidget {
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final String text;
  final StickerConfig config;

  static const double aspectRatio = 740 / 640;

  const StickerCanvas({
    super.key,
    required this.subjectBytes,
    this.generatedImage,
    required this.text,
    required this.config,
  });

  @override
  State<StickerCanvas> createState() => _StickerCanvasState();
}

class _StickerCanvasState extends State<StickerCanvas> {
  Offset _offset = Offset.zero;
  double _scale = 1.0;

  // 手勢開始時的快照
  double _startScale = 1.0;
  Offset _startFocalPoint = Offset.zero;
  Offset _startOffset = Offset.zero;

  @override
  void didUpdateWidget(StickerCanvas old) {
    super.didUpdateWidget(old);
    // AI 圖首次到達時重置位置，避免用上一張的偏移
    if (old.generatedImage == null && widget.generatedImage != null) {
      _offset = Offset.zero;
      _scale = 1.0;
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startFocalPoint = d.localFocalPoint;
    _startOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_startScale * d.scale).clamp(0.25, 4.0);
      _offset = _startOffset + (d.localFocalPoint - _startFocalPoint);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: StickerCanvas.aspectRatio,
      child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.generatedImage != null) ...[
              // ── AI 生成插圖（可縮放拖曳）────────────────────────────
              ClipRect(
                child: GestureDetector(
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  child: Transform.translate(
                    offset: _offset,
                    child: Transform.scale(
                      scale: _scale,
                      child: Image.memory(
                        widget.generatedImage!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
            ] else ...[
              // ── 彩色粗外框 ─────────────────────────────────────────
              _BorderFrame(color: widget.config.colorScheme.borderColor),

              // ── 背景裝飾（主體後方） ──────────────────────────────
              ..._buildDecorations(foreground: false),

              // ── 主體去背圖像（可縮放拖曳） ──────────────────────
              _buildSubject(),

              // ── 前景裝飾（主體前方，部分重疊） ───────────────────
              ..._buildDecorations(foreground: true),
            ],

            // ── LINE 貼圖風格大字（永遠疊在最上層）──────────────────
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: _OutlinedStickerText(
                  text: widget.text, config: widget.config),
            ),
          ],
      ),
    );
  }

  Widget _buildSubject() {
    if (widget.subjectBytes == null) {
      return Center(
        child: CircularProgressIndicator(
          color: widget.config.colorScheme.borderColor,
        ),
      );
    }
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      bottom: 62,
      child: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: Transform.translate(
          offset: _offset,
          child: Transform.scale(
            scale: _scale,
            child: Image.memory(
              widget.subjectBytes!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDecorations({required bool foreground}) {
    // 偶數索引 = 背景層；奇數索引 = 前景層
    final results = <Widget>[];
    for (int i = 0; i < widget.config.decorations.length; i++) {
      final isForeground = i.isOdd;
      if (isForeground != foreground) continue;

      final d = widget.config.decorations[i];
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
                color: widget.config.colorScheme.accentColor,
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
