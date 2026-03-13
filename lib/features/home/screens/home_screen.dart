import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app.dart';
import '../../../core/models/sticker_shape.dart';
import '../../../core/models/sticker_style.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/credit_badge.dart';
import '../widgets/pick_image_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  String _version = '';

  // ── 秘密手勢：連點版本號 5 下開啟 Log ──────────────────────────────────────
  int _tapCount = 0;
  DateTime? _firstTapAt;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version}');
    });
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  void _onVersionTap() {
    final now = DateTime.now();
    if (_firstTapAt == null ||
        now.difference(_firstTapAt!) > const Duration(seconds: 3)) {
      _firstTapAt = now;
      _tapCount = 1;
    } else {
      _tapCount++;
    }

    final remaining = 5 - _tapCount;
    if (remaining > 0 && remaining <= 2) {
      HapticFeedback.selectionClick();
    }

    if (_tapCount >= 5) {
      _tapCount = 0;
      _firstTapAt = null;
      HapticFeedback.mediumImpact();
      context.push('/dev-log');
    }
  }

  /// 兩步流程：先確認點數 → 選圖 → 選風格 → 立即跳 loading
  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    HapticFeedback.mediumImpact();
    FirebaseService.log('HomeScreen._pickImage: source=${source.name}');

    // Spec 預覽免費，直接選圖
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 95);
    if (picked == null || !context.mounted) return;

    // ② 選完圖後彈出風格選擇 sheet
    final result = await showModalBottomSheet<({int styleIndex, StickerShape shape})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _StylePickerSheet(),
    );
    if (result == null || !context.mounted) return;

    // 立即跳 editor，AI Spec 生成馬上開始（免費）
    context.push(
      '/editor',
      extra: EditorArgs(
        imagePath: picked.path,
        styleIndex: result.styleIndex,
        stickerShape: result.shape,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAppBar(),
            Expanded(child: _buildHero()),
            _buildBottomActions(context),
          ],
        ),
      ),
    );
  }

  // ── App Bar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return AnimatedBuilder(
      animation: _entryCtrl,
      builder: (_, child) => Opacity(
        opacity: _entryCtrl.value.clamp(0.0, 1.0),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Row(
          children: [
            ShaderMask(
              shaderCallback: (b) => AppColors.gradient.createShader(b),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 8),
            ShaderMask(
              shaderCallback: (b) => AppColors.gradient.createShader(b),
              child: Text(
                'Magic Sticker',
                style: GoogleFonts.notoSansTc(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const Spacer(),
            // 點數徽章
            const CreditBadge(),
          ],
        ),
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 主標語
          AnimatedBuilder(
            animation: _entryCtrl,
            builder: (_, child) {
              final t = CurvedAnimation(
                parent: _entryCtrl,
                curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
              ).value;
              return Opacity(
                opacity: t,
                child:
                    Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
              );
            },
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (b) => AppColors.gradient.createShader(b),
                  child: Text(
                    'Magic Sticker',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Text(
                  '一鍵生成專屬 LINE 貼圖',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 副標語
          AnimatedBuilder(
            animation: _entryCtrl,
            builder: (_, child) {
              final t = CurvedAnimation(
                parent: _entryCtrl,
                curve: const Interval(0.1, 0.65, curve: Curves.easeOut),
              ).value;
              return Opacity(opacity: t, child: child);
            },
            child: Text(
              '上傳照片 · 選擇風格 · AI 生成 · 即刻下載',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 40),

          // 3 張貼圖預覽卡堆疊
          _StickerPreviewStack(controller: _entryCtrl),
        ],
      ),
    );
  }

  // ── 底部按鈕 ──────────────────────────────────────────────────────────────

  Widget _buildBottomActions(BuildContext context) {
    return AnimatedBuilder(
      animation: _entryCtrl,
      builder: (_, child) {
        final t = CurvedAnimation(
          parent: _entryCtrl,
          curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
        ).value;
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 32 * (1 - t)), child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
        child: Column(
          children: [
            PickImageButton(
              icon: Icons.photo_library_rounded,
              label: '從相簿選取',
              onTap: () => _pickImage(context, ImageSource.gallery),
            ),
            const SizedBox(height: 12),
            PickImageButton(
              icon: Icons.camera_alt_rounded,
              label: '立即拍照',
              onTap: () => _pickImage(context, ImageSource.camera),
              outlined: true,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => FirebaseCrashlytics.instance.crash(),
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: const Text('[DEBUG] 測試 Crashlytics'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],
            if (_version.isNotEmpty) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _onVersionTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _version,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary.withValues(alpha: 0.45),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 風格選擇 Bottom Sheet ──────────────────────────────────────────────────────

class _StylePickerSheet extends StatefulWidget {
  const _StylePickerSheet();

  @override
  State<_StylePickerSheet> createState() => _StylePickerSheetState();
}

class _StylePickerSheetState extends State<_StylePickerSheet> {
  StickerShape _shape = StickerShape.circle;

  // 每個風格的簡短說明
  static const _descs = [
    '可愛 Q 版插畫',    // chibi
    '普普風鮮豔色彩',  // popArt
    '復古像素點陣',    // pixel
    '手繪素描質感',    // sketch
    '夢幻水彩風格',    // watercolor
    '高精細寫實人像',  // photo
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ─────────────────────────────────────────────
          const SizedBox(height: 14),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── 標題 ──────────────────────────────────────────────────
          ShaderMask(
            shaderCallback: (b) => AppColors.gradient.createShader(b),
            child: Text(
              '選擇貼圖風格',
              style: GoogleFonts.notoSansTc(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _FlowStep(icon: '🖼️', label: '選照片'),
                _FlowArrow(),
                _FlowStep(icon: '🆓', label: '分析概念', hint: '免費'),
                _FlowArrow(),
                _FlowStep(icon: '⚡', label: '點選產圖', hint: '各 1 點'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── 形狀選擇：圓形 / 方形 ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _ShapeToggle(
              selected: _shape,
              onChanged: (s) => setState(() => _shape = s),
            ),
          ),
          const SizedBox(height: 20),

          // ── 風格卡片 3×2 Grid ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: List.generate(StickerStyle.values.length, (i) {
                final style = StickerStyle.values[i];
                return _StyleCard(
                  style: style,
                  description: _descs[i],
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).pop(
                      (styleIndex: i, shape: _shape),
                    );
                  },
                );
              }),
            ),
          ),

          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

// ── 流程步驟提示元件 ──────────────────────────────────────────────────────────

class _FlowStep extends StatelessWidget {
  const _FlowStep({required this.icon, required this.label, this.hint});
  final String icon;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 2),
        Text(label,
            style: GoogleFonts.notoSansTc(
                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        if (hint != null)
          Text(hint!,
              style: GoogleFonts.notoSansTc(
                  fontSize: 10, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text('›',
          style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
    );
  }
}

// ── 形狀切換元件（圓形 ⭕ / 方形 ▪）──────────────────────────────────────────

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
                    )
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

class _StyleCard extends StatefulWidget {
  final StickerStyle style;
  final String description;
  final VoidCallback onTap;

  const _StyleCard({
    required this.style,
    required this.description,
    required this.onTap,
  });

  @override
  State<_StyleCard> createState() => _StyleCardState();
}

class _StyleCardState extends State<_StyleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  bool _pressed = false;

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
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        setState(() => _pressed = true);
        _press.forward();
      },
      onTapUp: (_) {
        HapticFeedback.mediumImpact();
        _press.reverse();
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () {
        _press.reverse();
        setState(() => _pressed = false);
      },
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - _press.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            gradient: _pressed ? AppColors.gradient : null,
            color: _pressed ? null : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _pressed ? Colors.transparent : AppColors.divider,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _pressed ? 0.14 : 0.06),
                blurRadius: _pressed ? 18 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/preview_${widget.style.name}.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Text(
                    widget.style.emoji,
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.style.label,
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _pressed ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.description,
                style: GoogleFonts.notoSansTc(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: _pressed
                      ? Colors.white.withValues(alpha: 0.85)
                      : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 3 張貼圖預覽卡堆疊（裝飾性，交錯動畫進場） ──────────────────────────────

class _StickerPreviewStack extends StatelessWidget {
  final AnimationController controller;

  const _StickerPreviewStack({required this.controller});

  static const _cards = [
    _CardData(
      emoji: '🐱',
      text: '哈哈哈！',
      gradientColors: [Color(0xFFFFB347), Color(0xFFFF7F00)],
      angle: -0.14,
    ),
    _CardData(
      emoji: '🐶',
      text: '好棒棒～',
      gradientColors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
      angle: 0.09,
    ),
    _CardData(
      emoji: '🐻',
      text: '早安！',
      gradientColors: [Color(0xFFFD297B), Color(0xFFFF5E5E)],
      angle: 0.0,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(_cards.length, (i) {
          final delay = (_cards.length - 1 - i) * 0.08;
          return AnimatedBuilder(
            animation: controller,
            builder: (_, child) {
              final t = CurvedAnimation(
                parent: controller,
                curve: Interval(
                  (0.25 + delay).clamp(0.0, 0.7),
                  (0.80 + delay).clamp(0.3, 1.0),
                  curve: Curves.easeOutBack,
                ),
              ).value.clamp(0.0, 1.0);
              return Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
              );
            },
            child: Transform.rotate(
              angle: _cards[i].angle,
              child: _MiniStickerCard(data: _cards[i]),
            ),
          );
        }),
      ),
    );
  }
}

class _CardData {
  final String emoji;
  final String text;
  final List<Color> gradientColors;
  final double angle;

  const _CardData({
    required this.emoji,
    required this.text,
    required this.gradientColors,
    required this.angle,
  });
}

class _MiniStickerCard extends StatelessWidget {
  final _CardData data;

  const _MiniStickerCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      height: 178,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: data.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: data.gradientColors.last.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(data.emoji, style: const TextStyle(fontSize: 56)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            data.text,
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
