import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app.dart';
import '../../../core/models/emotion_category.dart';
import '../../../core/models/sticker_shape.dart';
import '../../../core/models/sticker_style.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/billing/providers/credit_provider.dart';
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

  void _showChallengeCodeInput(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('輸入挑戰碼',
              style: TextStyle(fontFamily: 'OpenHuninn',
                fontSize: 20, fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text('輸入朋友分享的挑戰碼，試試同款貼圖風格',
              style: TextStyle(fontFamily: 'OpenHuninn',
                fontSize: 13, color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 8,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: TextStyle(
                  fontSize: 22, letterSpacing: 4,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w400,
                ),
                counterText: '',
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: const Color(0xFFFF5864), width: 1.5),
                ),
              ),
              onSubmitted: (v) {
                final code = v.trim().toUpperCase();
                if (code.isEmpty) return;
                Navigator.of(ctx).pop();
                context.push('/challenge/$code');
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5864),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  final code = controller.text.trim().toUpperCase();
                  if (code.isEmpty) return;
                  Navigator.of(ctx).pop();
                  context.push('/challenge/$code');
                },
                child: Text('前往挑戰',
                  style: TextStyle(fontFamily: 'OpenHuninn',
                    fontSize: 16, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 選圖後推入風格選擇畫面（步驟 2）
  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    HapticFeedback.mediumImpact();
    FirebaseService.log('HomeScreen._pickImage: source=${source.name}');

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 95);
    if (picked == null || !context.mounted) return;

    // 拍照時，先詢問是否存到相簿，再繼續下一步
    if (source == ImageSource.camera) {
      final shouldSave = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SavePhotoDialog(imagePath: picked.path),
      );
      if (!context.mounted) return;
      if (shouldSave == true) {
        try {
          if (!await Gal.hasAccess()) await Gal.requestAccess();
          await Gal.putImage(picked.path);
        } catch (_) {}
      }
    }

    // 挑戰模式：直接帶入挑戰的風格/情緒，跳過選擇畫面
    final challenge = ref.read(pendingChallengeProvider);
    if (challenge != null) {
      ref.read(pendingChallengeProvider.notifier).state = null;
      context.push(
        '/editor',
        extra: EditorArgs(
          imagePath: picked.path,
          styleIndex: challenge.styleIndex ?? 0,
          stickerShape: StickerShape.square,
          categoryIds: challenge.categoryIds ?? kDefaultCategoryIds,
          customStyleDesc: challenge.customStyleDesc,
          customEmotionDesc: challenge.customEmotionDesc,
        ),
      );
      return;
    }

    // 進入步驟 2：選擇風格
    context.push(
      '/style-select',
      extra: StyleSelectArgs(imagePath: picked.path),
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => RefreshIndicator(
                  onRefresh: () =>
                      ref.read(creditProvider.notifier).reload(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: _buildHero(),
                    ),
                  ),
                ),
              ),
            ),
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
                style: TextStyle(fontFamily: 'OpenHuninn',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
            const Spacer(),
            // 生成紀錄入口
            IconButton(
              icon: const Icon(Icons.history_rounded, color: AppColors.textSecondary),
              tooltip: '生成紀錄',
              onPressed: () => context.push('/sticker-history'),
            ),
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
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Magic Sticker',
                      style: TextStyle(fontFamily: 'OpenHuninn',
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Text(
                  '一鍵生成專屬 LINE 貼圖',
                  style: TextStyle(fontFamily: 'OpenHuninn',
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

          const SizedBox(height: 12),

          // 三步驟說明橫列
          AnimatedBuilder(
            animation: _entryCtrl,
            builder: (_, child) {
              final t = CurvedAnimation(
                parent: _entryCtrl,
                curve: const Interval(0.1, 0.65, curve: Curves.easeOut),
              ).value;
              return Opacity(opacity: t, child: child);
            },
            child: const _ThreeStepRow(),
          ),

          const SizedBox(height: 40),

          // 3 張貼圖預覽卡堆疊
          _StickerPreviewStack(controller: _entryCtrl),
        ],
      ),
    );
  }

  // ── 底部按鈕 ──────────────────────────────────────────────────────────────

  Widget _buildChallengeBanner(ChallengeParams challenge) {
    final styleIndex = challenge.styleIndex ?? 0;
    final styleName = challenge.customStyleDesc != null
        ? '✨ ${challenge.customStyleDesc}'
        : StickerStyle.values[styleIndex.clamp(0, StickerStyle.values.length - 1)].label;
    final emotionLine = challenge.customEmotionDesc != null
        ? '🎭 ${challenge.customEmotionDesc}'
        : '預設 8 種情緒';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5864).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF5864).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎯 挑戰模式：$styleName',
                  style: const TextStyle(
                    fontFamily: 'OpenHuninn',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF5864),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  emotionLine,
                  style: TextStyle(
                    fontFamily: 'OpenHuninn',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFFF5864).withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              ref.read(pendingChallengeProvider.notifier).state = null;
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                '取消',
                style: TextStyle(
                  fontFamily: 'OpenHuninn',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFFF5864).withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final challenge = ref.watch(pendingChallengeProvider);

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
            // 挑戰模式 banner 或步驟 1 提示
            if (challenge != null)
              _buildChallengeBanner(challenge)
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  '步驟 1／3　選一張照片，開始製作專屬貼圖',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'OpenHuninn',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
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
            if (challenge == null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _showChallengeCodeInput(context),
                child: Text(
                  '有挑戰碼？點此輸入',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'OpenHuninn',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFF5864).withValues(alpha: 0.75),
                    decoration: TextDecoration.underline,
                    decorationColor: const Color(0xFFFF5864).withValues(alpha: 0.5),
                  ),
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
                    style: TextStyle(fontFamily: 'OpenHuninn',
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

// ── 三步驟說明橫列 ────────────────────────────────────────────────────────────

class _ThreeStepRow extends StatelessWidget {
  const _ThreeStepRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StepChip(number: '①', emoji: '📷', label: '選照片'),
        _StepArrow(),
        _StepChip(number: '②', emoji: '🎨', label: '選風格'),
        _StepArrow(),
        _StepChip(number: '③', emoji: '😄', label: '選情緒'),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  final String number;
  final String emoji;
  final String label;

  const _StepChip({
    required this.number,
    required this.emoji,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number,
            style: TextStyle(fontFamily: 'OpenHuninn',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontFamily: 'OpenHuninn',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '›',
        style: TextStyle(
          fontSize: 20,
          color: AppColors.textSecondary.withValues(alpha: 0.5),
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
            style: TextStyle(fontFamily: 'OpenHuninn',
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

// ── 拍照後儲存詢問 Dialog ──────────────────────────────────────────────────────

class _SavePhotoDialog extends StatelessWidget {
  final String imagePath;

  const _SavePhotoDialog({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 照片縮圖
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Image.file(
              File(imagePath),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              children: [
                Text(
                  '要把這張照片存到相簿嗎？',
                  style: TextStyle(
                    fontFamily: 'OpenHuninn',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '下次可直接從相簿選取，不用重拍',
                  style: TextStyle(
                    fontFamily: 'OpenHuninn',
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // 主要按鈕：存到相簿
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        '存到相簿',
                        style: TextStyle(
                          fontFamily: 'OpenHuninn',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // 次要按鈕：跳過
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    '不用，直接繼續',
                    style: TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
