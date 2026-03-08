import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/sticker_style.dart';
import '../models/sticker_config.dart';
import '../models/sticker_font.dart';
import 'sticker_canvas.dart';

export 'sticker_canvas.dart' show StickerEditTarget;

/// 點圖後彈出的編輯 Bottom Sheet
///
/// 提供五種編輯功能：
///   1. 文字編輯（即時預覽）
///   2. 字型選擇（5 種繁中字體）
///   3. 配色選擇（8 組預設色系）
///   4. 產圖風格（切換後確認重新生成）
///   5. 圖片 / 文字點選後拖拉 / 捏合縮放 / 旋轉
class StickerEditSheet extends StatefulWidget {
  final int stickerIndex;
  final String initialText;
  final int initialSchemeIndex;
  final double initialScale;
  final Offset initialOffset;
  final int initialFontIndex;

  /// 產圖風格索引（切換後需確認再重新生成）
  final int initialStyleIndex;

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

  /// 產圖風格變更回呼（async，切換後重新生成圖片）
  final Future<void> Function(int styleIndex) onStyleChanged;

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
    this.initialStyleIndex = 0,
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
    required this.onStyleChanged,
    required this.onTextGestureChanged,
  });

  @override
  State<StickerEditSheet> createState() => _StickerEditSheetState();
}

class _StickerEditSheetState extends State<StickerEditSheet> {
  late final TextEditingController _textCtrl;
  late int _schemeIndex;
  late int _fontIndex;
  late int _styleIndex;
  late double _textXAlign;
  late double _textYAlign;
  late double _textAngle;
  late double _textSizeScale;
  bool _isRegenerating = false;

  /// 顯式選取模式：由下方模式按鈕控制，再按一次同個按鈕即取消選取
  StickerEditTarget _editTarget = StickerEditTarget.none;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _schemeIndex = widget.initialSchemeIndex;
    _fontIndex = widget.initialFontIndex;
    _styleIndex = widget.initialStyleIndex;
    _textXAlign = widget.initialTextXAlign;
    _textYAlign = widget.initialTextYAlign;
    _textAngle = widget.initialTextAngle;
    _textSizeScale = widget.initialFontSizeScale;
  }

  /// 使用者點選新風格 → 確認對話框 → 呼叫 API 重新生成
  Future<void> _onStyleTap(int newIdx) async {
    if (newIdx == _styleIndex || _isRegenerating) return;
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切換產圖風格'),
        content: Text(
          '將切換為「${StickerStyle.values[newIdx].emoji} '
          '${StickerStyle.values[newIdx].label}」風格並重新生成本張貼圖，確定嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確定重新生成'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isRegenerating = true);
    await widget.onStyleChanged(newIdx);
    if (!mounted) return;
    setState(() {
      _styleIndex = newIdx;
      _isRegenerating = false;
    });
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

    return Stack(
      children: [
        // ── 主內容 ─────────────────────────────────────────────────────
        Column(
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

            // ── 貼圖預覽（固定，不在 ScrollView 內，避免手勢衝突）─────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: CustomPaint(
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
                    externalTarget: _editTarget,
                    onTransformChanged: widget.onTransformChanged,
                    onTextGestureChanged: (xAlign, yAlign, angle, scale) {
                      setState(() {
                        _textXAlign = xAlign;
                        _textYAlign = yAlign;
                        _textAngle = angle;
                        _textSizeScale = scale;
                      });
                      widget.onTextGestureChanged(xAlign, yAlign, angle, scale);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── 顯式模式切換（取代 tap-to-select，解決無法取消選取問題）─
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.image_search_rounded,
                      label: '調整圖片',
                      isActive: _editTarget == StickerEditTarget.image,
                      activeColor: const Color(0xFF2196F3),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _editTarget =
                            _editTarget == StickerEditTarget.image
                                ? StickerEditTarget.none
                                : StickerEditTarget.image);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.text_fields_rounded,
                      label: '調整文字',
                      isActive: _editTarget == StickerEditTarget.text,
                      activeColor: const Color(0xFFFF9800),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _editTarget =
                            _editTarget == StickerEditTarget.text
                                ? StickerEditTarget.none
                                : StickerEditTarget.text);
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── 操作說明（依模式顯示不同提示）──────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: _editTarget == StickerEditTarget.none
                  ? const SizedBox(height: 8)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                      child: Text(
                        _editTarget == StickerEditTarget.image
                            ? '單指拖動調整位置・雙指縮放或旋轉・再按「調整圖片」取消'
                            : '單指拖動調整位置・雙指縮放或旋轉・再按「調整文字」取消',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                        textAlign: TextAlign.center,
                      ),
                    ),
            ),
            const SizedBox(height: 8),

            // ── 可捲動的編輯控制區 ─────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: insets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // ── 文字編輯 ─────────────────────────────────────
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

                    // ── 字型選擇 ─────────────────────────────────────
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

                    // ── 配色選擇 ─────────────────────────────────────
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
                                            color: Colors.transparent,
                                            width: 2.5),
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
                    const SizedBox(height: 20),

                    // ── 產圖風格 ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel('產圖風格'),
                          const SizedBox(height: 4),
                          Text(
                            '切換後將確認並重新生成本張貼圖',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade400),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: List.generate(
                                  StickerStyle.values.length, (i) {
                                final style = StickerStyle.values[i];
                                final isSelected = i == _styleIndex;
                                return GestureDetector(
                                  onTap: () => _onStyleTap(i),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 13, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.black87
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(20),
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
                                            style: const TextStyle(
                                                fontSize: 14)),
                                        const SizedBox(width: 5),
                                        Text(
                                          style.label,
                                          style: TextStyle(
                                            fontSize: 12,
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

                    // ── 完成按鈕 ─────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isRegenerating
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
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
            ),
          ],
        ),

        // ── 重新生成中 Loading 遮罩 ─────────────────────────────────────
        if (_isRegenerating)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.90),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🐱', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 4),
                  const Text('🐭', style: TextStyle(fontSize: 36)),
                  const SizedBox(height: 16),
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'AI 重新生成中…',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
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

// ─── 模式切換按鈕 ────────────────────────────────────────────────────────────

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.10) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? activeColor : Colors.grey.shade200,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 17,
                color: isActive ? activeColor : Colors.grey.shade500),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? activeColor : Colors.grey.shade600,
              ),
            ),
          ],
        ),
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
