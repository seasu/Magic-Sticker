import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
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

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    HapticFeedback.mediumImpact();
    FirebaseService.log('HomeScreen._pickImage: source=${source.name}');
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 95);
    if (picked == null || !context.mounted) return;
    context.push('/editor', extra: picked.path);
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

  // ── App Bar：品牌漸層 Logo ────────────────────────────────────────────────

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
                'MagicMorning',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const Spacer(),
            if (_version.isNotEmpty)
              Text(
                _version,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Hero：標語 + 3 張貼圖預覽卡堆疊 ─────────────────────────────────────

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 主標語（slide up + fade in）
          AnimatedBuilder(
            animation: _entryCtrl,
            builder: (_, child) {
              final t = CurvedAnimation(
                parent: _entryCtrl,
                curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
              ).value;
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 24 * (1 - t)),
                  child: child,
                ),
              );
            },
            child: Column(
              children: [
                Text(
                  '選一張照片',
                  style: GoogleFonts.nunito(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '一鍵生成 3 張 LINE 貼圖 ✨',
                  style: GoogleFonts.nunito(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    height: 1.3,
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
              'AI 自動去背 · 生成文案 · 滑動選擇',
              style: GoogleFonts.nunito(
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

  // ── 底部按鈕（fade + slide up） ─────────────────────────────────────────

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
          child: Transform.translate(
            offset: Offset(0, 32 * (1 - t)),
            child: child,
          ),
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
          ],
        ),
      ),
    );
  }
}

// ── 3 張貼圖預覽卡堆疊（裝飾性，交錯動畫進場） ──────────────────────────────

class _StickerPreviewStack extends StatelessWidget {
  final AnimationController controller;

  const _StickerPreviewStack({required this.controller});

  // 從後到前排列：index 0 = 最底層，index 2 = 最上層
  static const _cards = [
    _CardData(emoji: '🌟', text: '元氣滿滿！', color: Color(0xFF22C55E), angle: -0.14),
    _CardData(emoji: '💫', text: '好棒棒～', color: Color(0xFF3B82F6), angle: 0.09),
    _CardData(emoji: '❤️', text: '早安！', color: Color(0xFFFD297B), angle: 0.0),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(_cards.length, (i) {
          // 後面的卡（低 index）delay 較小，先進場
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
  final Color color;
  final double angle;

  const _CardData({
    required this.emoji,
    required this.text,
    required this.color,
    required this.angle,
  });
}

/// 小型貼圖預覽卡（保持 740:640 比例，白底+彩色外框）
class _MiniStickerCard extends StatelessWidget {
  final _CardData data;

  const _MiniStickerCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      height: 165, // 190 × (640/740) ≈ 164.3
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: data.color, width: 4),
        boxShadow: [
          BoxShadow(
            color: data.color.withOpacity(0.22),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          const BoxShadow(
            color: Color(0x10000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(data.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: data.color,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              data.text,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
