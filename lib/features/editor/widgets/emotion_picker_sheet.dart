import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/emotion_category.dart';
import '../../../core/theme/app_colors.dart';

/// 情感類別選擇器
///
/// 4×4 格子顯示 16 個情感選項，使用者可選 4–12 種。
/// 預設選中的 8 種為 [defaultOn = true] 的項目。
class EmotionPickerSheet extends StatefulWidget {
  final List<String> selectedIds;
  final void Function(List<String> ids) onConfirm;

  const EmotionPickerSheet({
    super.key,
    required this.selectedIds,
    required this.onConfirm,
  });

  @override
  State<EmotionPickerSheet> createState() => _EmotionPickerSheetState();
}

class _EmotionPickerSheetState extends State<EmotionPickerSheet> {
  late final List<String> _selected;

  static const _kMin = 4;
  static const _kMax = 12;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selectedIds);
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        if (_selected.length <= _kMin) {
          HapticFeedback.heavyImpact();
          return; // 已達最低限制
        }
        _selected.remove(id);
      } else {
        if (_selected.length >= _kMax) {
          // 超出上限：移除最舊的（第一個），加入新的
          _selected.removeAt(0);
        }
        _selected.add(id);
      }
      HapticFeedback.selectionClick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    final canConfirm = count >= _kMin && count <= _kMax;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 拖曳把手 ──────────────────────────────────────────────────────
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── 標題列 ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text(
                  '選擇情感類型',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                Text(
                  '$_kMin–$_kMax 種',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),

          // ── 4×4 情感格子 ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 1.0,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: kEmotionCategories.length,
              itemBuilder: (_, i) {
                final cat = kEmotionCategories[i];
                final isSelected = _selected.contains(cat.id);
                return _EmotionCell(
                  category: cat,
                  isSelected: isSelected,
                  onTap: () => _toggle(cat.id),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // ── 確認按鈕 ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: AnimatedOpacity(
                opacity: canConfirm ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: canConfirm
                      ? () {
                          HapticFeedback.mediumImpact();
                          widget.onConfirm(List<String>.from(_selected));
                        }
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: canConfirm
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFF5864).withValues(alpha: 0.30),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      '確認（$count 種情感）',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _EmotionCell extends StatelessWidget {
  final EmotionCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  const _EmotionCell({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF5864).withValues(alpha: 0.10)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF5864)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.emoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFFFF5864)
                          : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            // 勾選角標
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF5864),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
