import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/sticker_config.dart';
import '../models/sticker_font.dart';

/// LINE 貼圖畫布
///
/// - AI 圖到達時：直接全幅顯示，不疊加任何 Flutter 元素
/// - AI 圖未到達時（loading fallback）：簡單彩色背景 + 文字標籤
///
/// 畫布比例 740 : 640 → 輸出 370×320 px（LINE Creators Market 規格）
class StickerCanvas extends StatefulWidget {
  final Uint8List? subjectBytes; // 保留供 fallback 顯示（選用）
  final Uint8List? generatedImage;
  final String text;
  final StickerConfig config; // 僅 fallback 模式使用配色

  /// 初始縮放值（由父層傳入，用於跨 popup 保留位移/縮放狀態）
  final double initialScale;

  /// 初始位移量（由父層傳入）
  final Offset initialOffset;

  /// 字型索引（對應 kStickerFonts，0 = 黑體預設）
  final int fontIndex;

  /// 點圖回呼（用於打開編輯 popup）
  final VoidCallback? onTap;

  /// 縮放/位移變化後的回呼（用於持久化狀態）
  final void Function(double scale, Offset offset)? onTransformChanged;

  static const double aspectRatio = 740 / 640;

  const StickerCanvas({
    super.key,
    this.subjectBytes,
    this.generatedImage,
    required this.text,
    required this.config,
    this.initialScale = 1.0,
    this.initialOffset = Offset.zero,
    this.fontIndex = 0,
    this.onTap,
    this.onTransformChanged,
  });

  @override
  State<StickerCanvas> createState() => _StickerCanvasState();
}

class _StickerCanvasState extends State<StickerCanvas> {
  late double _scale;
  late Offset _offset;
  double _startScale = 1.0;
  Offset _startFocalPoint = Offset.zero;
  Offset _startOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _scale = widget.initialScale;
    _offset = widget.initialOffset;
  }

  @override
  void didUpdateWidget(StickerCanvas old) {
    super.didUpdateWidget(old);
    // 圖片首次到達時重置視角
    if (old.generatedImage == null && widget.generatedImage != null) {
      _offset = Offset.zero;
      _scale = 1.0;
      return;
    }
    // 父層（popup 關閉後）更新 transform 時同步
    if (old.initialScale != widget.initialScale ||
        old.initialOffset != widget.initialOffset) {
      setState(() {
        _scale = widget.initialScale;
        _offset = widget.initialOffset;
      });
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startFocalPoint = d.localFocalPoint;
    _startOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _scale = (_startScale * d.scale).clamp(0.5, 4.0);
      _offset = _startOffset + (d.localFocalPoint - _startFocalPoint);
    });
    widget.onTransformChanged?.call(_scale, _offset);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AspectRatio(
        aspectRatio: StickerCanvas.aspectRatio,
        child: _hasAiImage
            ? _buildAiImage()
            : _hasFailed
                ? _buildFailedPlaceholder()
                : _buildFallback(),
      ),
    );
  }

  bool get _hasAiImage =>
      widget.generatedImage != null && widget.generatedImage!.isNotEmpty;

  /// generatedImage 不為 null 但是 empty → 生成失敗
  bool get _hasFailed =>
      widget.generatedImage != null && widget.generatedImage!.isEmpty;

  /// AI 圖全幅顯示 + Flutter 文字 overlay（底部 22% 高度）
  /// 文字由 Flutter 渲染，避免 Gemini 中文字亂字問題
  Widget _buildAiImage() {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // AI 插圖（可縮放拖曳）
          GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Transform.translate(
              offset: _offset,
              child: Transform.scale(
                scale: _scale,
                child: Image.memory(
                  widget.generatedImage!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
          // 文字 overlay（底部對齊，Flutter 負責渲染）
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: _OutlinedStickerText(
              text: widget.text,
              config: widget.config,
              fontIndex: widget.fontIndex,
            ),
          ),
        ],
      ),
    );
  }

  /// 生成失敗：純色底，不顯示任何文字泡泡（錯誤 badge 由外層 _CardStack 疊加）
  Widget _buildFailedPlaceholder() {
    final color = widget.config.colorScheme.borderColor;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  /// 生成中 fallback（AI 圖尚未到達）：純色背景，不顯示文字
  /// 載入中的 badge 由外層 _CardStack 疊加，此處保持乾淨
  Widget _buildFallback() {
    final color = widget.config.colorScheme.borderColor;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

// ─── LINE 貼圖風格：粗 outline 文字 ──────────────────────────────────────

class _OutlinedStickerText extends StatelessWidget {
  final String text;
  final StickerConfig config;
  final int fontIndex;

  const _OutlinedStickerText({
    required this.text,
    required this.config,
    this.fontIndex = 0,
  });

  static const _kFontSize = 22.0;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontSize: _kFontSize,
      fontWeight: FontWeight.w900,
      height: 1.2,
    );
    final font = kStickerFonts[fontIndex.clamp(0, kStickerFonts.length - 1)];
    final styledBase = font.apply(baseStyle);

    final outlineText = Text(
      text,
      textAlign: TextAlign.center,
      style: styledBase.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      ),
    );
    final fillText = Text(
      text,
      textAlign: TextAlign.center,
      style: styledBase.copyWith(color: config.colorScheme.textFill),
    );

    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        child: Stack(
          alignment: Alignment.center,
          textDirection: TextDirection.ltr,
          children: [outlineText, fillText],
        ),
      ),
    );
  }
}
