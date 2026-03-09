import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/sticker_shape.dart';
import '../models/sticker_config.dart';
import '../models/sticker_font.dart';

// ─── 選取目標（公開，供 StickerEditSheet 外部控制）────────────────────────────

enum StickerEditTarget { none, image, text }

// ─── 選取框顏色常數 ───────────────────────────────────────────────────────────

const _kHandleColor = Color(0xFF29B6F6); // Blue-400

/// LINE 貼圖畫布
///
/// 互動模式（enableTextGestures = false，主卡片）：
///   - 雙指捏合：縮放 AI 圖片
///   - 點圖：觸發 onTap（打開編輯 Sheet）
///
/// 選取模式（enableTextGestures = true，編輯 Sheet）：
///   - 單指點選文字 / 圖片 → 顯示選取框
///   - 選取後單指拖動：移動物件
///   - 選取後雙指捏合：縮放物件
///   - 選取後雙指旋轉：旋轉物件
///
/// 畫布比例 1:1（正方形）→ 圓形輸出 370×370 px，方形同尺寸
class StickerCanvas extends StatefulWidget {
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final StickerShape stickerShape;
  final String text;
  final StickerConfig config;

  /// 初始圖片縮放值
  final double initialScale;

  /// 初始圖片位移量
  final Offset initialOffset;

  /// 初始圖片旋轉角度（弧度）
  final double initialImageAngle;

  /// 字型索引（對應 kStickerFonts）
  final int fontIndex;

  /// 字體大小倍率（0.3–3.0）
  final double fontSizeScale;

  /// 文字水平對齊（-1.5=左, 0=中, 1.5=右）
  final double textXAlign;

  /// 文字垂直對齊（-1.5=上, 0=中, 1.5=下）
  final double textYAlign;

  /// 文字旋轉角度（弧度）
  final double textAngle;

  /// true → 啟用選取模式（編輯 Sheet），false → 主卡片模式
  final bool enableTextGestures;

  /// 外部顯式指定選取目標（由 StickerEditSheet 的模式按鈕控制）
  /// 設定後 canvas 不再透過 tap 自行切換 _EditTarget
  final StickerEditTarget? externalTarget;

  /// 主卡片模式點圖回呼（打開編輯 popup）
  final VoidCallback? onTap;

  /// 圖片 transform 變化回呼（scale, offset, angle）
  final void Function(double scale, Offset offset, double angle)?
      onTransformChanged;

  /// 文字 transform 變化回呼（xAlign, yAlign, angle, sizeScale）
  final void Function(
    double xAlign,
    double yAlign,
    double angle,
    double sizeScale,
  )? onTextGestureChanged;

  static const double aspectRatio = 1.0; // 正方形畫布

  const StickerCanvas({
    super.key,
    this.subjectBytes,
    this.generatedImage,
    this.stickerShape = StickerShape.circle,
    required this.text,
    required this.config,
    this.initialScale = 1.0,
    this.initialOffset = Offset.zero,
    this.initialImageAngle = 0.0,
    this.fontIndex = 0,
    this.fontSizeScale = 1.0,
    this.textXAlign = 0.0,
    this.textYAlign = 0.85,
    this.textAngle = 0.0,
    this.enableTextGestures = false,
    this.externalTarget,
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
  late double _imgAngle;
  double _imgStartScale = 1.0;
  Offset _imgStartFocal = Offset.zero;
  Offset _imgStartOffset = Offset.zero;
  double _imgStartAngle = 0.0;

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

  // ── 選取狀態（externalTarget 為 null 時由 tap 自行維護）─────────────────
  StickerEditTarget _internalSelected = StickerEditTarget.none;

  /// 實際生效的選取目標：外部優先，否則用內部狀態
  StickerEditTarget get _effective =>
      widget.externalTarget ?? _internalSelected;

  // ── 手勢 tap 偵測（在 scale handler 內判斷）──────────────────────────────
  Offset _gestureStartFocal = Offset.zero;
  bool _wasTap = false;

  // 畫布實際尺寸（LayoutBuilder 填入）
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _imgScale = widget.initialScale;
    _imgOffset = widget.initialOffset;
    _imgAngle = widget.initialImageAngle;
    _textXAlign = widget.textXAlign;
    _textYAlign = widget.textYAlign;
    _textAngle = widget.textAngle;
    _textSizeScale = widget.fontSizeScale;
  }

  @override
  void didUpdateWidget(StickerCanvas old) {
    super.didUpdateWidget(old);

    // 圖片首次到達時重置視角
    if (old.generatedImage == null && widget.generatedImage != null) {
      _imgOffset = Offset.zero;
      _imgScale = 1.0;
      _imgAngle = 0.0;
    }

    // 父層更新圖片 transform 時同步（popup 關閉後）
    if (old.initialScale != widget.initialScale ||
        old.initialOffset != widget.initialOffset ||
        old.initialImageAngle != widget.initialImageAngle) {
      setState(() {
        _imgScale = widget.initialScale;
        _imgOffset = widget.initialOffset;
        _imgAngle = widget.initialImageAngle;
      });
    }

    // 文字 transform：手勢進行中不覆寫本地狀態
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

  // ── 手勢處理（統一 Handler）────────────────────────────────────────────────

  void _onScaleStart(ScaleStartDetails d) {
    _gestureStartFocal = d.localFocalPoint;
    _wasTap = true;

    if (!widget.enableTextGestures || _effective == StickerEditTarget.image) {
      // 主卡片圖片縮放 or 編輯模式圖片選取
      _imgStartScale = _imgScale;
      _imgStartFocal = d.localFocalPoint;
      _imgStartOffset = _imgOffset;
      _imgStartAngle = _imgAngle;
    } else if (_effective == StickerEditTarget.text) {
      _textGestureActive = true;
      _txtStartXAlign = _textXAlign;
      _txtStartYAlign = _textYAlign;
      _txtStartAngle = _textAngle;
      _txtStartScale = _textSizeScale;
      _txtStartFocal = d.localFocalPoint;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // 判斷是否為「真實手勢」（非 tap）
    if ((d.scale - 1.0).abs() > 0.04 ||
        d.rotation.abs() > 0.04 ||
        (d.localFocalPoint - _gestureStartFocal).distance > 8) {
      _wasTap = false;
    }

    if (!widget.enableTextGestures || _effective == StickerEditTarget.image) {
      // 圖片：縮放 + 位移（編輯模式下加旋轉）
      setState(() {
        _imgScale = (_imgStartScale * d.scale).clamp(0.5, 4.0);
        _imgOffset = _imgStartOffset + (d.localFocalPoint - _imgStartFocal);
        if (widget.enableTextGestures) {
          _imgAngle = _imgStartAngle + d.rotation;
        }
      });
      widget.onTransformChanged?.call(_imgScale, _imgOffset, _imgAngle);
    } else if (_effective == StickerEditTarget.text) {
      // 文字：移動 + 縮放 + 旋轉
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
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _textGestureActive = false;

    if (_wasTap) {
      if (widget.enableTextGestures &&
          _canvasSize != Size.zero &&
          widget.externalTarget == null) {
        // 僅在無外部控制時才允許 tap 自行切換選取目標
        _handleSelectionTap(_gestureStartFocal);
      } else if (!widget.enableTextGestures) {
        // 主卡片：呼叫 onTap 打開編輯 Sheet
        widget.onTap?.call();
      }
    }
  }

  /// 依點擊座標決定選取圖片或文字（僅 externalTarget == null 時呼叫）
  void _handleSelectionTap(Offset pos) {
    final cx = _canvasSize.width * (1 + _textXAlign) / 2;
    final cy = _canvasSize.height * (1 + _textYAlign) / 2;
    final dist = (pos - Offset(cx, cy)).distance;

    // 命中範圍：以字體大小倍率調整（最小 44px，最大畫布寬一半）
    final hitR =
        (_canvasSize.width * 0.28 * _textSizeScale).clamp(44.0, _canvasSize.width * 0.5);

    final next = dist < hitR ? StickerEditTarget.text : StickerEditTarget.image;
    if (next != _internalSelected) {
      HapticFeedback.selectionClick();
      setState(() => _internalSelected = next);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
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
    final content = ClipRect(
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          _canvasSize = constraints.biggest;

          // ── 圖片層（縮放 + 位移 + 旋轉）────────────────────────────────
          final imageContent = Transform.translate(
            offset: _imgOffset,
            child: Transform.scale(
              scale: _imgScale,
              child: Transform.rotate(
                angle: _imgAngle,
                child: Image.memory(
                  widget.generatedImage!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          );

          // ── 文字層（位移 + 旋轉 + 選取框）──────────────────────────────
          final textLayer = Align(
            alignment: Alignment(_textXAlign, _textYAlign),
            child: Transform.rotate(
              angle: _textAngle,
              child: _TextSelectionWidget(
                text: widget.text,
                config: widget.config,
                fontIndex: widget.fontIndex,
                fontSizeScale: _textSizeScale,
                isSelected:
                    widget.enableTextGestures && _effective == StickerEditTarget.text,
              ),
            ),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              // 白色底，防止 AI 圖片透明區域（圓形外）在 app 預覽或匯出時顯示棋盤格
              const ColoredBox(color: Colors.white),

              imageContent,

              // ── 人物層（ML Kit 去背，疊在 AI 背景上，同步 transform）──
              if (widget.subjectBytes != null)
                Transform.translate(
                  offset: _imgOffset,
                  child: Transform.scale(
                    scale: _imgScale,
                    child: Transform.rotate(
                      angle: _imgAngle,
                      child: Image.memory(
                        widget.subjectBytes!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),

              // 圖片選取框（編輯模式下圖片被選中時）
              if (widget.enableTextGestures && _effective == StickerEditTarget.image)
                _ImageSelectionOverlay(canvasSize: _canvasSize),

              textLayer,

              // 提示文字（無外部控制且尚未選取任何物件時顯示）
              if (widget.enableTextGestures &&
                  widget.externalTarget == null &&
                  _internalSelected == StickerEditTarget.none)
                const _SelectionHint(),
            ],
          );
        },
      ),
    );
    // 圓形模式：預覽時加 ClipOval（不影響 RepaintBoundary 擷取）
    if (widget.stickerShape == StickerShape.circle) {
      return ClipOval(child: content);
    }
    return content;
  }

  Widget _buildFailedPlaceholder() {
    final color = widget.config.colorScheme.borderColor;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildFallback() {
    final color = widget.config.colorScheme.borderColor;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

// ─── 文字 + 選取框 ─────────────────────────────────────────────────────────────

class _TextSelectionWidget extends StatelessWidget {
  final String text;
  final StickerConfig config;
  final int fontIndex;
  final double fontSizeScale;
  final bool isSelected;

  const _TextSelectionWidget({
    required this.text,
    required this.config,
    required this.fontIndex,
    required this.fontSizeScale,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    const double handleR = 8.0;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: isSelected
          ? BoxDecoration(
              border: Border.all(color: _kHandleColor, width: 2),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: _OutlinedStickerText(
        text: text,
        config: config,
        fontIndex: fontIndex,
        fontSizeScale: fontSizeScale,
      ),
    );

    if (!isSelected) return content;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        content,

        // 旋轉控制點（文字上方：24px 圓圈 + 20px 連接線，4px 間距）
        Positioned(
          top: -(24 + 20 + 4).toDouble(), // 頂部留出 handle 高度 + 4px 間距
          child: const _RotationHandle(),
        ),

        // 四角縮放控制點
        Positioned(top: -handleR, left: -handleR, child: const _CircleHandle()),
        Positioned(top: -handleR, right: -handleR, child: const _CircleHandle()),
        Positioned(bottom: -handleR, left: -handleR, child: const _CircleHandle()),
        Positioned(bottom: -handleR, right: -handleR, child: const _CircleHandle()),
      ],
    );
  }
}

class _RotationHandle extends StatelessWidget {
  const _RotationHandle();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kHandleColor,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(
            Icons.rotate_right_rounded,
            size: 14,
            color: Colors.white,
          ),
        ),
        Container(
          width: 2,
          height: 20,
          color: _kHandleColor.withValues(alpha: 0.75),
        ),
      ],
    );
  }
}

class _CircleHandle extends StatelessWidget {
  const _CircleHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kHandleColor,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
    );
  }
}

// ─── 圖片選取框（全畫布角落控制點）──────────────────────────────────────────

class _ImageSelectionOverlay extends StatelessWidget {
  final Size canvasSize;

  const _ImageSelectionOverlay({required this.canvasSize});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 邊框 + 角落控制點（CustomPainter）
          CustomPaint(painter: _ImageSelectionPainter()),

          // 中心旋轉提示圓圈
          Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.88),
                border: Border.all(color: _kHandleColor, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6)
                ],
              ),
              child: const Icon(
                Icons.open_with_rounded,
                size: 22,
                color: _kHandleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSelectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = _kHandleColor.withValues(alpha: 0.85)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // 畫面邊框
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(4, 4, size.width - 4, size.height - 4),
        const Radius.circular(4),
      ),
      borderPaint,
    );

    // 四角控制點
    final fillPaint = Paint()
      ..color = _kHandleColor
      ..style = PaintingStyle.fill;
    final whitePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (final pt in [
      const Offset(4, 4),
      Offset(size.width - 4, 4),
      Offset(4, size.height - 4),
      Offset(size.width - 4, size.height - 4),
    ]) {
      canvas.drawCircle(pt, 8, fillPaint);
      canvas.drawCircle(pt, 8, whitePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── 操作提示（尚未選取任何物件時）─────────────────────────────────────────

class _SelectionHint extends StatelessWidget {
  const _SelectionHint();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, 0.92),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_rounded, size: 13, color: Colors.white),
            SizedBox(width: 5),
            Text(
              '點選圖片或文字來編輯',
              style: TextStyle(fontSize: 11, color: Colors.white),
            ),
          ],
        ),
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
