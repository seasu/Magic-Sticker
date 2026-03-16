import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app.dart';
import '../../../core/models/sticker_shape.dart';
import '../../../core/models/sticker_style.dart';
import '../../../core/theme/app_colors.dart';

/// 步驟 2／3：選擇貼圖風格與形狀。
///
/// 與 EmotionSelectionScreen 採用一致的全螢幕樣式與標頭。
class StyleSelectionScreen extends StatefulWidget {
  final String imagePath;

  const StyleSelectionScreen({super.key, required this.imagePath});

  @override
  State<StyleSelectionScreen> createState() => _StyleSelectionScreenState();
}

class _StyleSelectionScreenState extends State<StyleSelectionScreen>
    with SingleTickerProviderStateMixin {
  int? _selectedStyleIndex;
  StickerShape _shape = StickerShape.circle;
  late final AnimationController _entryCtrl;

  static const _descs = [
    '可愛 Q 版插畫',   // chibi
    '普普風鮮豔色彩', // popArt
    '復古像素點陣',   // pixel
    '手繪素描質感',   // sketch
    '夢幻水彩風格',   // watercolor
    '韓系扁平插畫',   // webtoon
    '日系動漫賽璐璐', // celshade
    '3D 皮克斯風格',  // pixar3d
    '毛絨玩偶質感',   // plush
  ];

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_selectedStyleIndex == null) return;
    HapticFeedback.mediumImpact();
    context.pushReplacement(
      '/emotion-select',
      extra: EmotionSelectArgs(
        imagePath: widget.imagePath,
        styleIndex: _selectedStyleIndex!,
        stickerShape: _shape,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _selectedStyleIndex != null;
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
                child: _buildContent(),
              ),
            ),
            _buildBottomBar(canConfirm, bottom),
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
                  '選擇貼圖風格',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  '先選外框形狀，再選最喜歡的視覺風格',
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
              '步驟 2／3',
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

  // ── 內容（形狀切換 + 風格格子） ────────────────────────────────────────────

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // 形狀切換
          _ShapeToggle(
            selected: _shape,
            onChanged: (s) => setState(() => _shape = s),
          ),
          const SizedBox(height: 16),
          // 風格格子
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.92,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: StickerStyle.values.length,
            itemBuilder: (_, i) {
              final style = StickerStyle.values[i];
              final isSelected = _selectedStyleIndex == i;
              return _StyleCard(
                style: style,
                description: _descs[i],
                isSelected: isSelected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedStyleIndex = i);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ── 底部確認列 ────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(bool canConfirm, double bottomPadding) {
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
          // 提示文字
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedStyleIndex != null
                    ? StickerStyle.values[_selectedStyleIndex!].label
                    : '未選擇',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: canConfirm
                      ? const Color(0xFFFF5864)
                      : Colors.black38,
                ),
              ),
              Text(
                _selectedStyleIndex != null
                    ? _descs[_selectedStyleIndex!]
                    : '點一下卡片即可選取',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black38,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // 下一步按鈕
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
                              color: const Color(0xFFFF5864)
                                  .withValues(alpha: 0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    '確認風格，選情緒 →',
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

// ─── 形狀切換 ──────────────────────────────────────────────────────────────────

class _ShapeToggle extends StatelessWidget {
  final StickerShape selected;
  final ValueChanged<StickerShape> onChanged;

  const _ShapeToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _ShapeOption(
            label: '⭕ 圓形',
            isSelected: selected == StickerShape.circle,
            onTap: () => onChanged(StickerShape.circle),
          ),
          _ShapeOption(
            label: '▪ 方形',
            isSelected: selected == StickerShape.square,
            onTap: () => onChanged(StickerShape.square),
          ),
        ],
      ),
    );
  }
}

class _ShapeOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ShapeOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? Colors.black87 : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 風格卡片 ─────────────────────────────────────────────────────────────────

class _StyleCard extends StatefulWidget {
  final StickerStyle style;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _StyleCard({
    required this.style,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_StyleCard> createState() => _StyleCardState();
}

class _StyleCardState extends State<_StyleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.0,
      upperBound: 0.07,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFFFF5864);

    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - _press.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? brand.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.isSelected ? brand : Colors.transparent,
              width: 2,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: brand.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/preview_${widget.style.name}.png',
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Text(
                          widget.style.emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.style.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: widget.isSelected ? brand : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: widget.isSelected
                            ? brand.withValues(alpha: 0.70)
                            : AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              // 選取勾選角標
              if (widget.isSelected)
                Positioned(
                  top: 5,
                  right: 5,
                  child: AnimatedScale(
                    scale: 1.0,
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
      ),
    );
  }
}
