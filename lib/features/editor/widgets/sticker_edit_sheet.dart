import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/sticker_shape.dart';
import '../models/sticker_config.dart';
import '../models/sticker_font.dart';
import 'sticker_canvas.dart';
import 'sticker_canvas_frame.dart';

export 'sticker_canvas.dart' show StickerEditTarget;

/// 目前開啟的編輯面板類型
enum _PanelMode { none, image, text, color }

/// 點圖後彈出的編輯 Bottom Sheet
///
/// 三個模式按鈕（調整圖片 / 調整文字 / 配色），
/// 按下後下方只顯示對應的設定項目。
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
  final StickerShape stickerShape;

  final ValueChanged<String> onTextChanged;
  final ValueChanged<int> onSchemeChanged;
  final void Function(double scale, Offset offset, double angle)
      onTransformChanged;
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
    this.stickerShape = StickerShape.circle,
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
  late double _textXAlign;
  late double _textYAlign;
  late double _textAngle;
  late double _textSizeScale;

  /// 目前開啟的面板（預設進入即為圖片編輯模式）
  _PanelMode _panelMode = _PanelMode.image;

  /// Canvas 編輯模式由面板衍生
  StickerEditTarget get _editTarget => switch (_panelMode) {
        _PanelMode.image => StickerEditTarget.image,
        _PanelMode.text => StickerEditTarget.text,
        _ => StickerEditTarget.none,
      };

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

  void _togglePanel(_PanelMode mode) {
    HapticFeedback.selectionClick();
    setState(() => _panelMode = _panelMode == mode ? _PanelMode.none : mode);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final insets = MediaQuery.of(context).viewInsets;
    final config = kStickerConfigs[_schemeIndex];

    return SizedBox(
      // 90% 螢幕高度：讓 canvas 佔滿，控制列縮到底部
      height: screenH * 0.90,
      child: Column(
        children: [
          // ── Drag handle ──────────────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),

          // ── 標題 ─────────────────────────────────────────────────
          Text(
            '貼圖 ${widget.stickerIndex + 1} 編輯',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),

          // ── 貼圖預覽（填滿剩餘高度，正方形置中）─────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LayoutBuilder(
                builder: (ctx, box) {
                  // 取寬/高最小值，確保正方形在任何比例下都能完整顯示
                  final side = box.maxWidth < box.maxHeight
                      ? box.maxWidth
                      : box.maxHeight;
                  return Center(
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: StickerCanvasFrame(
                        stickerShape: widget.stickerShape,
                        showBoundary: true,
                        child: StickerCanvas(
                          subjectBytes: widget.subjectBytes,
                          generatedImage: widget.generatedImage,
                          text: _textCtrl.text,
                          config: config,
                          stickerShape: widget.stickerShape,
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
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ── 三個模式按鈕 ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    icon: Icons.image_search_rounded,
                    label: '調整圖片',
                    isActive: _panelMode == _PanelMode.image,
                    activeColor: const Color(0xFF2196F3),
                    onTap: () => _togglePanel(_PanelMode.image),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    icon: Icons.text_fields_rounded,
                    label: '調整文字',
                    isActive: _panelMode == _PanelMode.text,
                    activeColor: const Color(0xFFFF9800),
                    onTap: () => _togglePanel(_PanelMode.text),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    icon: Icons.palette_outlined,
                    label: '配色',
                    isActive: _panelMode == _PanelMode.color,
                    activeColor: const Color(0xFFE91E63),
                    onTap: () => _togglePanel(_PanelMode.color),
                  ),
                ),
              ],
            ),
          ),

          // ── Canvas 操作提示（圖片 / 文字模式才顯示）─────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: (_panelMode == _PanelMode.image ||
                    _panelMode == _PanelMode.text)
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                    child: Text(
                      _panelMode == _PanelMode.image
                          ? '單指拖動調整位置・雙指縮放或旋轉・再按「調整圖片」取消'
                          : '單指拖動調整位置・雙指縮放或旋轉・再按「調整文字」取消',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500),
                      textAlign: TextAlign.center,
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── 面板內容（固定高度，不可捲動）────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(
              key: ValueKey(_panelMode),
              child: _buildPanel(),
            ),
          ),

          // ── 完成按鈕（固定在底部）───────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + insets.bottom),
            child: _buildDoneButton(),
          ),
        ],
      ),
    );
  }

  // ─── 面板內容 ──────────────────────────────────────────────────────────────

  Widget _buildPanel() {
    return switch (_panelMode) {
      _PanelMode.none => _buildNonePanel(),
      _PanelMode.image => const SizedBox.shrink(),
      _PanelMode.text => _buildTextPanel(),
      _PanelMode.color => _buildColorPanel(),
    };
  }

  /// 未選模式時的空狀態提示
  Widget _buildNonePanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app_rounded,
              size: 30, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            '點選上方按鈕開始編輯',
            style:
                TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  /// 配色 → 色盤選擇
  Widget _buildColorPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('配色'),
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
                              color: c.borderColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// 調整文字 → 文字輸入 + 字型選擇
  Widget _buildTextPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('文字'),
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
          const SizedBox(height: 20),
          const _SectionLabel('字型'),
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
    );
  }

  Widget _buildDoneButton() {
    return SizedBox(
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
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

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

// ─── 模式切換按鈕 ─────────────────────────────────────────────────────────────

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
          color: isActive
              ? activeColor.withValues(alpha: 0.10)
              : Colors.grey.shade100,
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
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
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


