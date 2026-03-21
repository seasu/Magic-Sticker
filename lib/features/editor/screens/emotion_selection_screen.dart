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
import '../../../shared/widgets/cat_loading_widget.dart';
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
    // 讓自訂情緒輸入也能驅動底部列重建
    _proEmotionCtrl.addListener(_onEmotionChanged);
  }

  void _onEmotionChanged() => setState(() {});

  @override
  void dispose() {
    _proEmotionCtrl.removeListener(_onEmotionChanged);
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
    final hasCustomEmotion = customEmotionDesc.isNotEmpty;
    context.pushReplacement(
      '/editor',
      extra: EditorArgs(
        imagePath: widget.imagePath,
        styleIndex: widget.styleIndex,
        stickerShape: widget.stickerShape,
        // 有客製情緒時傳預設 categoryIds（CF 要求 ≥4 個，provider 只取第 1 個 spec）
        categoryIds: hasCustomEmotion
            ? List<String>.from(kDefaultCategoryIds)
            : List<String>.from(_selected),
        customStyleDesc: widget.customStyleDesc,
        customEmotionDesc: hasCustomEmotion ? customEmotionDesc : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    final hasCustomEmotion = _proEmotionCtrl.text.trim().isNotEmpty;
    // 有自訂情緒輸入時也視為可確認（即使卡片數在邊界外，但實際上 min=1 保證 count≥1）
    final canConfirm = (count >= _kMin && count <= _kMax) || hasCustomEmotion;
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
                child: _buildGrid(hasCustomEmotion),
              ),
            ),
            _buildBottomBar(count, canConfirm, hasCustomEmotion, bottom),
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

  Widget _buildGrid(bool hasCustomEmotion) {
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
              // 有客製情緒時：隱藏 24 張卡格，改顯示說明卡 + Pro 特權提示
              if (hasCustomEmotion) ...[
                _CustomEmotionInfoCard(desc: _proEmotionCtrl.text.trim()),
                const SizedBox(height: 20),
                const _ProStandbyHint(),
                const SizedBox(height: 16),
              ] else ...[
                // 分隔標籤
                _Divider(
                  label: isPro ? '或從 24 種情緒中選（可多選）' : '從 24 種情緒中選（可多選）',
                ),
                const SizedBox(height: 12),
              ],
            ]),
          ),
        ),
        // 無客製情緒時才顯示 24 張情緒卡
        if (!hasCustomEmotion)
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

  Widget _buildBottomBar(
      int count, bool canConfirm, bool hasCustomEmotion, double bottomPadding) {
    final btnLabel = hasCustomEmotion
        ? '確認描述，開始 AI →'
        : '開始製作 $count 款貼圖 ✨';

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
          // 左側：客製情緒模式顯示標籤，否則顯示數量 + 重設
          if (hasCustomEmotion)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '客製情緒',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7B5215),
                  ),
                ),
                const Text(
                  'AI 將專為此情緒生成 1 款',
                  style: TextStyle(fontSize: 11, color: Colors.black38),
                ),
              ],
            )
          else
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
                      const TextSpan(
                        text: ' 種情緒',
                        style: TextStyle(
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
                    gradient: canConfirm
                        ? (hasCustomEmotion
                            ? const LinearGradient(
                                colors: [Color(0xFFC9A84C), Color(0xFFA07828)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              )
                            : AppColors.gradient)
                        : null,
                    color: canConfirm ? null : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: canConfirm
                        ? [
                            BoxShadow(
                              color: hasCustomEmotion
                                  ? const Color(0xFFC9A84C).withValues(alpha: 0.40)
                                  : const Color(0xFFFF5864).withValues(alpha: 0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    btnLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: hasCustomEmotion ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      color: canConfirm
                          ? (hasCustomEmotion
                              ? const Color(0xFF7B5215)
                              : Colors.white)
                          : Colors.black38,
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
          color: isPro ? const Color(0xFFFAFAF5) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPro ? const Color(0xFFC9A84C) : Colors.black12,
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
                        colors: [Color(0xFFC9A84C), Color(0xFFA07828)],
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

// ─── 客製情緒說明卡 ────────────────────────────────────────────────────────────

class _CustomEmotionInfoCard extends StatefulWidget {
  final String desc;
  const _CustomEmotionInfoCard({required this.desc});

  @override
  State<_CustomEmotionInfoCard> createState() => _CustomEmotionInfoCardState();
}

class _CustomEmotionInfoCardState extends State<_CustomEmotionInfoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFAFAF5), Color(0xFFF5EDD8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC9A84C), width: 1.5),
      ),
      child: Column(
        children: [
          // 香檳金貓咪動畫（取代靜態 ✦）
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              size: const Size(140, 100),
              painter: RunningCatPainter(
                t: _ctrl.value,
                colors: CatColorScheme.proChampagne,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'AI 將以「${widget.desc}」為核心',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7B5215),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '自由生成一款您的專屬貼圖',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFFA07828),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pro 待命提示（填補空白區域）──────────────────────────────────────────────────

class _ProStandbyHint extends StatelessWidget {
  const _ProStandbyHint();

  @override
  Widget build(BuildContext context) {
    const features = ['完全自由的情緒詮釋', 'AI 不受預設框架限制', '生成獨一無二的專屬貼圖'];
    return Column(
      children: [
        const Text(
          'Pro 模式特權',
          style: TextStyle(fontSize: 12, color: Colors.black38),
        ),
        const SizedBox(height: 12),
        ...features.map(
          (text) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFC9A84C).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '✦ ',
                    style: TextStyle(
                      color: Color(0xFFC9A84C),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    text,
                    style: const TextStyle(
                      color: Color(0xFF7B5215),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
