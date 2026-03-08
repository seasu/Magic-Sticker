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
///
/// 文字手勢（enableTextGestures: true 時啟用）：
///   - 單指拖拉：移動文字位置
///   - 雙指捏合：縮放文字大小
///   - 雙指旋轉：旋轉文字角度
class StickerCanvas extends StatefulWidget {
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final String text;
  final StickerConfig config;

  /// 初始圖片縮放值（由父層傳入）
  final double initialScale;

  /// 初始圖片位移量（由父層傳入）
  final Offset initialOffset;

  /// 字型索引（對應 kStickerFonts，0 = 黑體預設）
  final int fontIndex;

  /// 字體大小倍率（0.3–3.0，預設 1.0）
  final double fontSizeScale;

  /// 文字水平對齊（-1.5=左, 0=中, 1.5=右，預設 0.0）
  final double textXAlign;

  /// 文字垂直對齊（-1.5=上, 0=中, 1.5=下，預設 0.85 接近底部）
  final double textYAlign;

  /// 文字旋轉角度（弧度，預設 0.0）
  final double textAngle;

  /// 啟用文字手勢互動（拖拉/捏合/旋轉）
  /// - true：整個畫布的手勢都驅動文字，圖片靜止（用於編輯 sheet）
  /// - false：手勢驅動圖片縮放/位移（用於主卡片畫面）
  final bool enableTextGestures;

  /// 點圖回呼（用於打開編輯 popup）
  final VoidCallback? onTap;

  /// 圖片縮放/位移變化後的回呼（enableTextGestures=false 時有效）
  final void Function(double scale, Offset offset)? onTransformChanged;

  /// 文字手勢變化後的回呼（enableTextGestures=true 時觸發）
  final void Function(
    double xAlign,
    double yAlign,
    double angle,
    double sizeScale,
  )? onTextGestureChanged;

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
    this.fontSizeScale = 1.0,
    this.textXAlign = 0.0,
    this.textYAlign = 0.85,
    this.textAngle = 0.0,
    this.enableTextGestures = false,
    this.onTap,
    this.onTransformChanged,
    this.onTextGestureChanged,
  });

  @override
  State<StickerCanvas> createState() => _StickerCanvasState();
}

class _StickerCanvasState extends State<StickerCanvas> {
  // ── 圖片 transform ──────────────────────────────────────────────────────────
  late double _imgScale;
  late Offset _imgOffset;
  double _imgStartScale = 1.0;
  Offset _imgStartFocal = Offset.zero;
  Offset _imgStartOffset = Offset.zero;

  // ── 文字 transform ──────────────────────────────────────────────────────────
  late double _textXAlign;
  late double _textYAlign;
  late double _textAngle;
  late double _textSizeScale;
  double _txtStartXAlign = 0.0;
  double _txtStartYAlign = 0.0;
  double _txtStartAngle = 0.0;
  double _txtStartScale = 1.0;
  Offset _txtStartFocal = Offset.zero;
  bool _textGestureActive = false;

  // 畫布實際尺寸（由 LayoutBuilder 填入，供手勢坐標轉換用）
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _imgScale = widget.initialScale;
    _imgOffset = widget.initialOffset;
    _textXAlign = widget.textXAlign;
    _textYAlign = widget.textYAlign;
    _textAngle = widget.textAngle;
    _textSizeScale = widget.fontSizeScale;
  }

  @override
  void didUpdateWidget(StickerCanvas old) {
    super.didUpdateWidget(old);

    // 圖片首次到達時重置圖片視角
    if (old.generatedImage == null && widget.generatedImage != null) {
      _imgOffset = Offset.zero;
      _imgScale = 1.0;
    }

    // 父層更新圖片 transform 時同步（popup 關閉後）
    if (old.initialScale != widget.initialScale ||
        old.initialOffset != widget.initialOffset) {
      setState(() {
        _imgScale = widget.initialScale;
        _imgOffset = widget.initialOffset;
      });
    }

    // 文字 transform：手勢進行中時不覆寫本地狀態
    if (!_textGestureActive) {
      if (old.textXAlign != widget.textXAlign) {
        setState(() => _textXAlign = widget.textXAlign);
      }
      if (old.textYAlign != widget.textYAlign) {
        setState(() => _textYAlign = widget.textYAlign);
      }
      if (old.textAngle != widget.textAngle) {
        setState(() => _textAngle = widget.textAngle);
      }
      if (old.fontSizeScale != widget.fontSizeScale) {
        setState(() => _textSizeScale = widget.fontSizeScale);
      }
    }
  }

  // ── 圖片手勢（enableTextGestures = false 時使用）─────────────────────────

  void _onImgScaleStart(ScaleStartDetails d) {
    _imgStartScale = _imgScale;
    _imgStartFocal = d.localFocalPoint;
    _imgStartOffset = _imgOffset;
  }

  void _onImgScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _imgScale = (_imgStartScale * d.scale).clamp(0.5, 4.0);
      _imgOffset = _imgStartOffset + (d.localFocalPoint - _imgStartFocal);
    });
    widget.onTransformChanged?.call(_imgScale, _imgOffset);
  }

  // ── 文字手勢（enableTextGestures = true 時使用）──────────────────────────

  void _onTextScaleStart(ScaleStartDetails d) {
    _textGestureActive = true;
    _txtStartXAlign = _textXAlign;
    _txtStartYAlign = _textYAlign;
    _txtStartAngle = _textAngle;
    _txtStartScale = _textSizeScale;
    _txtStartFocal = d.localFocalPoint;
  }

  void _onTextScaleUpdate(ScaleUpdateDetails d) {
    if (_canvasSize == Size.zero) return;
    final delta = d.localFocalPoint - _txtStartFocal;
    final halfW = _canvasSize.width / 2;
    final halfH = _canvasSize.height / 2;
    setState(() {
      _textXAlign = (_txtStartXAlign + delta.dx / halfW).clamp(-1.5, 1.5);
      _textYAlign = (_txtStartYAlign + delta.dy / halfH).clamp(-1.5, 1.5);
      _textAngle = _txtStartAngle + d.rotation;
      _textSizeScale = (_txtStartScale * d.scale).clamp(0.3, 3.0);
    });
    widget.onTextGestureChanged
        ?.call(_textXAlign, _textYAlign, _textAngle, _textSizeScale);
  }

  void _onTextScaleEnd(ScaleEndDetails d) {
    _textGestureActive = false;
  }

  // ── Build ────────────────────────────────────────────────────────────────

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

  bool get _hasFailed =>
      widget.generatedImage != null && widget.generatedImage!.isEmpty;

  Widget _buildAiImage() {
    return ClipRect(
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          _canvasSize = constraints.biggest;

          // ── 圖片層 ────────────────────────────────────────────────────
          final imageContent = Transform.translate(
            offset: _imgOffset,
            child: Transform.scale(
              scale: _imgScale,
              child: Image.memory(
                widget.generatedImage!,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                filterQuality: FilterQuality.high,
              ),
            ),
          );

          final imageLayer = widget.enableTextGestures
              ? imageContent // 文字編輯模式：圖片靜止
              : GestureDetector(
                  onScaleStart: _onImgScaleStart,
                  onScaleUpdate: _onImgScaleUpdate,
                  child: imageContent,
                );

          // ── 文字層 ────────────────────────────────────────────────────
          final textLayer = Align(
            alignment: Alignment(_textXAlign, _textYAlign),
            child: Transform.rotate(
              angle: _textAngle,
              child: Container(
                // 編輯模式：顯示白色選取外框提示使用者可互動
                decoration: widget.enableTextGestures
                    ? BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withOpacity(0.80),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      )
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 3,
                ),
                child: _OutlinedStickerText(
                  text: widget.text,
                  config: widget.config,
                  fontIndex: widget.fontIndex,
                  fontSizeScale: _textSizeScale,
                ),
              ),
            ),
          );

          Widget canvas = Stack(
            fit: StackFit.expand,
            children: [imageLayer, textLayer],
          );

          // 文字編輯模式：整個畫布套上手勢偵測器
          if (widget.enableTextGestures) {
            canvas = GestureDetector(
              onScaleStart: _onTextScaleStart,
              onScaleUpdate: _onTextScaleUpdate,
              onScaleEnd: _onTextScaleEnd,
              child: canvas,
            );
          }

          return canvas;
        },
      ),
    );
  }

  Widget _buildFailedPlaceholder() {
    final color = widget.config.colorScheme.borderColor;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

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

// ─── LINE 貼圖風格：粗 outline 文字 ──────────────────────────────────────────

class _OutlinedStickerText extends StatelessWidget {
  final String text;
  final StickerConfig config;
  final int fontIndex;
  final double fontSizeScale;

  const _OutlinedStickerText({
    required this.text,
    required this.config,
    this.fontIndex = 0,
    this.fontSizeScale = 1.0,
  });

  static const _kBaseFontSize = 36.0;

  @override
  Widget build(BuildContext context) {
    final fontSize = _kBaseFontSize * fontSizeScale;
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.15,
    );
    final font = kStickerFonts[fontIndex.clamp(0, kStickerFonts.length - 1)];
    final styledBase = font.apply(baseStyle);

    final outlineText = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: styledBase.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (fontSize * 0.14).clamp(3.0, 7.0)
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      ),
    );
    final fillText = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: styledBase.copyWith(color: config.colorScheme.textFill),
    );

    return Stack(
      alignment: Alignment.center,
      textDirection: TextDirection.ltr,
      children: [outlineText, fillText],
    );
  }
}
