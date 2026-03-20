import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app.dart';
import '../../../core/models/emotion_category.dart';
import '../../../core/models/sticker_shape.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/billing/providers/pro_purchase_provider.dart';
import '../../../shared/widgets/pro_unlock_sheet.dart';

/// 步驟 3／3：使用者選擇情緒種類後，帶著選擇結果進入 EditorScreen。
///
/// - 預設選中 8 種（[kDefaultCategoryIds]）
/// - 最少 1 種，最多 12 種
/// - 確認後帶 categoryIds 傳入 /editor
class EmotionSelectionScreen extends ConsumerStatefulWidget {
  final String imagePath;
  final int styleIndex;
  final StickerShape stickerShape;
  final String? customStyleDesc;

  const EmotionSelectionScreen({
    super.key,
    required this.imagePath,
    required this.styleIndex,
    this.stickerShape = StickerShape.circle,
    this.customStyleDesc,
  });

  @override
  ConsumerState<EmotionSelectionScreen> createState() =>
      _EmotionSelectionScreenState();
}

class _EmotionSelectionScreenState extends ConsumerState<EmotionSelectionScreen>
    with SingleTickerProviderStateMixin {
  late final List<String> _selected;
  late final AnimationController _entryCtrl;
  final _proEmotionCtrl = TextEditingController();

  static const _kMin = 1;
  static const _kMax = 12;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(kDefaultCategoryIds);
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _proEmotionCtrl.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        if (_selected.length <= _kMin) {
          HapticFeedback.heavyImpact();
          return;
        }
        _selected.remove(id);
      } else {
        if (_selected.length >= _kMax) {
          _selected.removeAt(0); // 移除最舊的，加入新的
        }
        _selected.add(id);
      }
      HapticFeedback.selectionClick();
    });
  }

  void _resetToDefault() {
    setState(() {
      _selected
        ..clear()
        ..addAll(kDefaultCategoryIds);
    });
    HapticFeedback.mediumImpact();
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    final customEmotionDesc = _proEmotionCtrl.text.trim();
    context.pushReplacement(
      '/editor',
      extra: EditorArgs(
        imagePath: widget.imagePath,
        styleIndex: widget.styleIndex,
        stickerShape: widget.stickerShape,
        categoryIds: List<String>.from(_selected),
        customStyleDesc: widget.customStyleDesc,
        customEmotionDesc: customEmotionDesc.isNotEmpty ? customEmotionDesc : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    final canConfirm = count >= _kMin && count <= _kMax;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: AnimatedBuilder(
                animation: _entryCtrl,
                builder: (_, child) => Opacity(
                  opacity: _entryCtrl.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - _entryCtrl.value)),
                    child: child,
                  ),
                ),
                child: _buildGrid(),
              ),
            ),
            _buildBottomBar(count, canConfirm, bottom),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            style: IconButton.styleFrom(foregroundColor: Colors.black87),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '選擇情緒種類',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  '每種情緒各生成一張，可選 1–12 種',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // 步驟 badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '步驟 3／3',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 情緒格子 ─────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    final isPro = ref.watch(isProUnlockedProvider).valueOrNull ?? false;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // Pro 自訂情緒卡片
              _ProCustomEmotionCard(
                isPro: isPro,
                controller: _proEmotionCtrl,
                hint: '輸入任意情緒，例：淡定無語、興奮尖叫',
                onLockedTap: () => ProUnlockSheet.show(context),
              ),
              const SizedBox(height: 12),
              // 分隔標籤
              _Divider(
                label: isPro ? '或從 24 種情緒中選（可多選）' : '從 24 種情緒中選（可多選）',
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.88,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final cat = kEmotionCategories[i];
                final isSelected = _selected.contains(cat.id);
                final order = isSelected ? _selected.indexOf(cat.id) + 1 : null;
                return _EmotionCard(
                  category: cat,
                  isSelected: isSelected,
                  selectionOrder: order,
                  onTap: () => _toggle(cat.id),
                );
              },
              childCount: kEmotionCategories.length,
            ),
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }

  // ── 底部確認列 ────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(int count, bool canConfirm, double bottomPadding) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottomPadding),
      child: Row(
        children: [
          // 已選數量 + 重設預設
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$count',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: canConfirm
                            ? const Color(0xFFFF5864)
                            : Colors.orange,
                      ),
                    ),
                    TextSpan(
                      text: ' 種情緒',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _resetToDefault,
                child: const Text(
                  '重設預設 8 種',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black38,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.black26,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // 開始製作按鈕
          Expanded(
            child: AnimatedOpacity(
              opacity: canConfirm ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: canConfirm ? _confirm : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: canConfirm ? AppColors.gradient : null,
                    color: canConfirm ? null : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: canConfirm
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF5864).withValues(alpha: 0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    '開始製作 $count 款貼圖 ✨',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: canConfirm ? Colors.white : Colors.black38,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pro 自訂情緒卡片 ─────────────────────────────────────────────────────────

class _ProCustomEmotionCard extends StatelessWidget {
  final bool isPro;
  final TextEditingController controller;
  final String hint;
  final VoidCallback onLockedTap;

  const _ProCustomEmotionCard({
    required this.isPro,
    required this.controller,
    required this.hint,
    required this.onLockedTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isPro ? null : onLockedTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: isPro ? const Color(0xFFFFFDE7) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPro ? const Color(0xFFFFD700) : Colors.black12,
            width: isPro ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: isPro
                    ? const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isPro ? null : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                size: 20,
                color: isPro ? Colors.white : Colors.black38,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: isPro
                  ? TextField(
                      controller: controller,
                      maxLength: 15,
                      maxLines: 1,
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Colors.black38,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pro 自訂情緒',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '點擊解鎖，NT\$49 · 一次性永久使用',
                          style: TextStyle(fontSize: 11, color: Colors.black38),
                        ),
                      ],
                    ),
            ),
            if (isPro)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, val, __) => Text(
                  '${val.text.length}/15',
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
              )
            else
              const Icon(Icons.lock_outline_rounded,
                  size: 18, color: Colors.black38),
          ],
        ),
      ),
    );
  }
}

// ─── 分隔標籤 ─────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  final String label;
  const _Divider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Colors.black12)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black38),
          ),
        ),
        const Expanded(child: Divider(color: Colors.black12)),
      ],
    );
  }
}

// ─── 情緒卡片 ─────────────────────────────────────────────────────────────────

class _EmotionCard extends StatelessWidget {
  final EmotionCategory category;
  final bool isSelected;
  final int? selectionOrder; // 選取順序（1-based），null = 未選
  final VoidCallback onTap;

  const _EmotionCard({
    required this.category,
    required this.isSelected,
    required this.selectionOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFFFF5864);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isSelected
              ? brand.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? brand : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: brand.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.emoji,
                    style: const TextStyle(fontSize: 30),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? brand : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            // 選取順序角標
            if (isSelected && selectionOrder != null)
              Positioned(
                top: 5,
                right: 5,
                child: AnimatedScale(
                  scale: isSelected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.elasticOut,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: brand,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Colors.white,
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
