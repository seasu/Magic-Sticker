import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/sticker_style.dart';
import '../models/sticker_config.dart';
import '../models/sticker_font.dart';
import 'sticker_canvas.dart';

/// 點圖後彈出的編輯 Bottom Sheet
///
/// 提供五種編輯功能：
/// - 圖片縮放/位移（pinch-zoom + pan）
/// - 文字編輯（即時預覽）
/// - 字型選擇（5 種繁中字體）
/// - 配色選擇（8 組預設色系）
/// - 產圖風格（Q版卡通 / 普普風 / 像素風 / 素描 / 水彩）
class StickerEditSheet extends StatefulWidget {
  final int stickerIndex;
  final String initialText;
  final int initialSchemeIndex;
  final double initialScale;
  final Offset initialOffset;
  final int initialFontIndex;
  final int initialStyleIndex;
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<int> onSchemeChanged;
  final void Function(double scale, Offset offset) onTransformChanged;
  final ValueChanged<int> onFontChanged;
  final ValueChanged<int> onStyleChanged;

  const StickerEditSheet({
    super.key,
    required this.stickerIndex,
    required this.initialText,
    required this.initialSchemeIndex,
    required this.initialScale,
    required this.initialOffset,
    this.initialFontIndex = 0,
    this.initialStyleIndex = 0,
    this.subjectBytes,
    this.generatedImage,
    required this.onTextChanged,
    required this.onSchemeChanged,
    required this.onTransformChanged,
    required this.onFontChanged,
    required this.onStyleChanged,
  });

  @override
  State<StickerEditSheet> createState() => _StickerEditSheetState();
}

class _StickerEditSheetState extends State<StickerEditSheet> {
  late final TextEditingController _textCtrl;
  late int _schemeIndex;
  late int _fontIndex;
  late int _styleIndex;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _schemeIndex = widget.initialSchemeIndex;
    _fontIndex = widget.initialFontIndex;
    _styleIndex = widget.initialStyleIndex;
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
            // ── Drag handle ───────────────────────────────────────────
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

            // ── 標題 ──────────────────────────────────────────────────
            Text(
              '貼圖 ${widget.stickerIndex + 1} 編輯',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // ── 貼圖預覽（可縮放/拖曳）────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: StickerCanvas(
                  subjectBytes: widget.subjectBytes,
                  generatedImage: widget.generatedImage,
                  text: _textCtrl.text,
                  config: config,
                  initialScale: widget.initialScale,
                  initialOffset: widget.initialOffset,
                  fontIndex: _fontIndex,
                  onTransformChanged: widget.onTransformChanged,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── 文字編輯 ──────────────────────────────────────────────
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
                      setState(() {}); // 即時更新預覽
                      widget.onTextChanged(val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── 字型選擇 ──────────────────────────────────────────────
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

            // ── 配色選擇 ──────────────────────────────────────────────
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
                                ? Border.all(color: Colors.black87, width: 2.5)
                                : Border.all(
                                    color: Colors.transparent, width: 2.5),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: c.borderColor.withOpacity(0.5),
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
            const SizedBox(height: 20),

            // ── 產圖風格 ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel('產圖風格'),
                  const SizedBox(height: 4),
                  Text(
                    '變更後將重新生成貼圖',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(StickerStyle.values.length, (i) {
                        final style = StickerStyle.values[i];
                        final isSelected = i == _styleIndex;
                        return GestureDetector(
                          onTap: () {
                            if (i == _styleIndex) return;
                            HapticFeedback.mediumImpact();
                            setState(() => _styleIndex = i);
                            widget.onStyleChanged(i);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(style.emoji,
                                    style: const TextStyle(fontSize: 15)),
                                const SizedBox(width: 6),
                                Text(
                                  style.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── 完成按鈕 ──────────────────────────────────────────────
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
