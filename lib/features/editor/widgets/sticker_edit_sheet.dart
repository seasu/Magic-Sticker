import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/sticker_config.dart';
import 'sticker_canvas.dart';

/// 點圖後彈出的編輯 Bottom Sheet
///
/// 提供三種編輯功能：
/// - 圖片縮放/位移（pinch-zoom + pan）
/// - 文字編輯
/// - 配色選擇（8 組預設色系）
class StickerEditSheet extends StatefulWidget {
  final int stickerIndex;
  final String initialText;
  final int initialSchemeIndex;
  final double initialScale;
  final Offset initialOffset;
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<int> onSchemeChanged;
  final void Function(double scale, Offset offset) onTransformChanged;

  const StickerEditSheet({
    super.key,
    required this.stickerIndex,
    required this.initialText,
    required this.initialSchemeIndex,
    required this.initialScale,
    required this.initialOffset,
    this.subjectBytes,
    this.generatedImage,
    required this.onTextChanged,
    required this.onSchemeChanged,
    required this.onTransformChanged,
  });

  @override
  State<StickerEditSheet> createState() => _StickerEditSheetState();
}

class _StickerEditSheetState extends State<StickerEditSheet> {
  late final TextEditingController _textCtrl;
  late int _schemeIndex;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _schemeIndex = widget.initialSchemeIndex;
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
                  Text(
                    '文字',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
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

            // ── 配色選擇 ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '配色',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(kStickerConfigs.length, (i) {
                      final c = kStickerConfigs[i].colorScheme;
                      final isSelected = i == _schemeIndex;
                      return GestureDetector(
                        onTap: () {
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
