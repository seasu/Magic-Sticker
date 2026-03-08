import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sticker_config.dart';
import '../models/sticker_font.dart';
import 'sticker_canvas.dart';

/// 點圖後彈出的編輯 Bottom Sheet
///
/// 提供四種編輯功能：
///   1. 文字編輯（即時預覽）
///   2. 字型選擇（5 種繁中字體）
///   3. 配色選擇（8 組預設色系）
///   4. 文字拖拉 / 捏合縮放 / 旋轉（直接在預覽上操作）
///
/// 產圖風格已移至主畫面的風格選擇列。
class StickerEditSheet extends StatefulWidget {
  final int stickerIndex;
  final String initialText;
  final int initialSchemeIndex;
  final double initialScale;
  final Offset initialOffset;
  final int initialFontIndex;

  /// 文字初始位置與角度（手勢控制，無滑桿）
  final double initialTextXAlign;
  final double initialTextYAlign;
  final double initialTextAngle;
  final double initialFontSizeScale;

  /// 圖片初始旋轉角度（弧度）
  final double initialImageAngle;

  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;

  final ValueChanged<String> onTextChanged;
  final ValueChanged<int> onSchemeChanged;
  final void Function(double scale, Offset offset, double angle) onTransformChanged;
  final ValueChanged<int> onFontChanged;

  /// 文字手勢回呼：拖拉/捏合/旋轉後觸發，傳回最新的 (xAlign, yAlign, angle, sizeScale)
  final void Function(
    double xAlign,
    double yAlign,
    double angle,
    double sizeScale,
  ) onTextGestureChanged;

  const StickerEditSheet({
    super.key,
    required this.stickerIndex,
    required this.initialText,
    required this.initialSchemeIndex,
    required this.initialScale,
    required this.initialOffset,
    this.initialFontIndex = 0,
    this.initialTextXAlign = 0.0,
    this.initialTextYAlign = 0.85,
    this.initialTextAngle = 0.0,
    this.initialFontSizeScale = 1.0,
    this.initialImageAngle = 0.0,
    this.subjectBytes,
    this.generatedImage,
    required this.onTextChanged,
    required this.onSchemeChanged,
    required this.onTransformChanged,
    required this.onFontChanged,
    required this.onTextGestureChanged,
  });

  @override
  State<StickerEditSheet> createState() => _StickerEditSheetState();
}

class _StickerEditSheetState extends State<StickerEditSheet> {
  late final TextEditingController _textCtrl;
  late int _schemeIndex;
  late int _fontIndex;
  late double _textXAlign;
  late double _textYAlign;
  late double _textAngle;
  late double _textSizeScale;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _schemeIndex = widget.initialSchemeIndex;
    _fontIndex = widget.initialFontIndex;
    _textXAlign = widget.initialTextXAlign;
    _textYAlign = widget.initialTextYAlign;
    _textAngle = widget.initialTextAngle;
    _textSizeScale = widget.initialFontSizeScale;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    final config = kStickerConfigs[_schemeIndex];

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ────────────────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // ── 標題 ───────────────────────────────────────────────────
            Text(
              '貼圖 ${widget.stickerIndex + 1} 編輯',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 14),

            // ── 貼圖預覽（文字可拖拉/捏合/旋轉）+ 虛線邊界框 ──────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Stack(
                children: [
                  CustomPaint(
                    foregroundPainter: const _BoundaryPainter(),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: StickerCanvas(
                        subjectBytes: widget.subjectBytes,
                        generatedImage: widget.generatedImage,
                        text: _textCtrl.text,
                        config: config,
                        initialScale: widget.initialScale,
                        initialOffset: widget.initialOffset,
                        initialImageAngle: widget.initialImageAngle,
                        fontIndex: _fontIndex,
                        fontSizeScale: _textSizeScale,
                        textXAlign: _textXAlign,
                        textYAlign: _textYAlign,
                        textAngle: _textAngle,
                        enableTextGestures: true,
                        onTransformChanged: widget.onTransformChanged,
                        onTextGestureChanged: (xAlign, yAlign, angle, scale) {
                          setState(() {
                            _textXAlign = xAlign;
                            _textYAlign = yAlign;
                            _textAngle = angle;
                            _textSizeScale = scale;
                          });
                          widget.onTextGestureChanged(
                              xAlign, yAlign, angle, scale);
                        },
                      ),
                    ),
                  ),
                  // 操作提示（選取物件後可移動・縮放・旋轉）
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '點選物件 → 移動・縮放・旋轉',
                        style: TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 文字編輯 ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('文字'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _textCtrl,
                    maxLines: 1,
                    maxLength: 10,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '輸入 2–6 字…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                      counterText: '',
                    ),
                    onChanged: (val) {
                      setState(() {});
                      widget.onTextChanged(val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 字型選擇 ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('字型'),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(kStickerFonts.length, (i) {
                        final font = kStickerFonts[i];
                        final isSelected = i == _fontIndex;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _fontIndex = i);
                            widget.onFontChanged(i);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.black87
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.black87
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Text(
                              font.label,
                              style: font.apply(TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                              )),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 配色選擇 ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('配色'),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(kStickerConfigs.length, (i) {
                      final c = kStickerConfigs[i].colorScheme;
                      final isSelected = i == _schemeIndex;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _schemeIndex = i);
                          widget.onSchemeChanged(i);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.borderColor,
                            border: isSelected
                                ? Border.all(
                                    color: Colors.black87, width: 2.5)
                                : Border.all(
                                    color: Colors.transparent, width: 2.5),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color:
                                          c.borderColor.withOpacity(0.5),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 完成按鈕 ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '完成',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─── 貼圖最大邊界虛線框 ──────────────────────────────────────────────────────

class _BoundaryPainter extends CustomPainter {
  const _BoundaryPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBBBBBB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashLen = 5.0;
    const gapLen = 4.0;
    const radius = 16.0;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(radius),
      ));

    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final end = (dist + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
