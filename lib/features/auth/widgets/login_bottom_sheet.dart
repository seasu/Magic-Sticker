import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';

// ── 狀態機 ─────────────────────────────────────────────────────────────────

enum _SheetState { initial, loadingGoogle, loadingApple, success, error }

/// 登入底部彈窗
///
/// 回傳 `true` = 登入成功（可繼續操作）
class LoginBottomSheet extends ConsumerStatefulWidget {
  const LoginBottomSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LoginBottomSheet(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<LoginBottomSheet> createState() => _LoginBottomSheetState();
}

class _LoginBottomSheetState extends ConsumerState<LoginBottomSheet>
    with SingleTickerProviderStateMixin {
  _SheetState _state = _SheetState.initial;
  String? _errorMessage;

  // 成功狀態的用戶資訊
  String? _userName;
  String? _userPhotoUrl;
  int _bonusCredits = 0;

  // 成功動畫
  late final AnimationController _successCtrl;
  late final Animation<double> _checkScale;
  late final Animation<double> _badgeFade;
  late final Animation<Offset> _badgeSlide;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _checkScale = CurvedAnimation(
      parent: _successCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
    );
    _badgeFade = CurvedAnimation(
      parent: _successCtrl,
      curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
    );
    _badgeSlide = Tween(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _successCtrl,
      curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
    ));
  }

  @override
  void dispose() {
    _successCtrl.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _loginWithGoogle() async {
    if (_state != _SheetState.initial) return;
    setState(() => _state = _SheetState.loadingGoogle);

    final result = await AuthService.signInWithGoogle();

    if (!mounted) return;

    if (result.isSuccess) {
      _handleSuccess();
    } else if (result.isError) {
      HapticFeedback.vibrate();
      setState(() {
        _state = _SheetState.error;
        _errorMessage = 'Google 登入失敗，請稍後再試一次';
      });
    } else {
      // cancelled
      setState(() => _state = _SheetState.initial);
    }
  }

  Future<void> _loginWithApple() async {
    if (_state != _SheetState.initial) return;
    setState(() => _state = _SheetState.loadingApple);

    final result = await AuthService.signInWithApple();

    if (!mounted) return;

    if (result.isSuccess) {
      _handleSuccess();
    } else if (result.isError) {
      HapticFeedback.vibrate();
      setState(() {
        _state = _SheetState.error;
        _errorMessage = 'Apple 登入失敗，請稍後再試一次';
      });
    } else {
      setState(() => _state = _SheetState.initial);
    }
  }

  void _handleSuccess() {
    HapticFeedback.mediumImpact();
    final user = FirebaseAuth.instance.currentUser;
    setState(() {
      _state = _SheetState.success;
      _userName = user?.displayName ?? user?.email?.split('@').first ?? '使用者';
      _userPhotoUrl = user?.photoURL;
      _bonusCredits = 5;
    });
    _successCtrl.forward();
  }

  void _retry() => setState(() {
        _state = _SheetState.initial;
        _errorMessage = null;
      });

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: switch (_state) {
          _SheetState.success => _SuccessView(
              key: const ValueKey('success'),
              userName: _userName!,
              photoUrl: _userPhotoUrl,
              bonusCredits: _bonusCredits,
              checkScale: _checkScale,
              badgeFade: _badgeFade,
              badgeSlide: _badgeSlide,
              onDone: () => Navigator.of(context).pop(true),
            ),
          _SheetState.error => _ErrorView(
              key: const ValueKey('error'),
              message: _errorMessage ?? '登入失敗，請稍後再試',
              onRetry: _retry,
              onGuest: () => Navigator.of(context).pop(false),
            ),
          _ => _InitialView(
              key: const ValueKey('initial'),
              isLoadingGoogle: _state == _SheetState.loadingGoogle,
              isLoadingApple: _state == _SheetState.loadingApple,
              onGoogle: _loginWithGoogle,
              onApple: _loginWithApple,
              onGuest: () => Navigator.of(context).pop(false),
            ),
        },
      ),
    );
  }
}

// ── Initial View ─────────────────────────────────────────────────────────────

class _InitialView extends StatelessWidget {
  final bool isLoadingGoogle;
  final bool isLoadingApple;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onGuest;

  const _InitialView({
    super.key,
    required this.isLoadingGoogle,
    required this.isLoadingApple,
    required this.onGoogle,
    required this.onApple,
    required this.onGuest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DragHandle(),
        const SizedBox(height: 24),

        // ── 圖示 ────────────────────────────────────────────────────
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: AppColors.gradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5864).withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: Colors.white, size: 34),
        ),
        const SizedBox(height: 18),

        // ── 標題 ────────────────────────────────────────────────────
        ShaderMask(
          shaderCallback: (b) => AppColors.gradient.createShader(b),
          child: Text(
            '登入獲得 5 點',
            style: GoogleFonts.notoSansTc(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '登入帳號可跨裝置同步點數\n首次登入獲得 5 點初始獎勵 🎉',
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
            height: 1.65,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // ── 功能說明列 ──────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _FeatureChip(icon: Icons.bolt_rounded, label: '5 點獎勵'),
            const SizedBox(width: 10),
            _FeatureChip(icon: Icons.sync_rounded, label: '跨裝置同步'),
            const SizedBox(width: 10),
            _FeatureChip(icon: Icons.history_rounded, label: '點數紀錄'),
          ],
        ),
        const SizedBox(height: 24),

        // ── Google 登入 ─────────────────────────────────────────────
        _SocialLoginButton(
          isLoading: isLoadingGoogle,
          onTap: onGoogle,
          icon: _GoogleIcon(),
          label: '使用 Google 帳號登入',
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          borderColor: AppColors.divider,
        ),

        // ── Apple 登入（iOS only）───────────────────────────────────
        if (Platform.isIOS) ...[
          const SizedBox(height: 12),
          _SocialLoginButton(
            isLoading: isLoadingApple,
            onTap: onApple,
            icon: const Icon(Icons.apple, size: 24, color: Colors.white),
            label: '使用 Apple ID 登入',
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        ],

        const SizedBox(height: 20),
        TextButton(
          onPressed: onGuest,
          child: Text(
            '繼續以訪客身份使用',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Success View ──────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final String userName;
  final String? photoUrl;
  final int bonusCredits;
  final Animation<double> checkScale;
  final Animation<double> badgeFade;
  final Animation<Offset> badgeSlide;
  final VoidCallback onDone;

  const _SuccessView({
    super.key,
    required this.userName,
    this.photoUrl,
    required this.bonusCredits,
    required this.checkScale,
    required this.badgeFade,
    required this.badgeSlide,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DragHandle(),
        const SizedBox(height: 28),

        // ── 大頭貼 + 勾勾 badge ─────────────────────────────────────
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Google 大頭貼 or 首字母
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: photoUrl == null ? AppColors.gradient : null,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5864).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: photoUrl != null
                  ? ClipOval(
                      child: Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
            // ✅ 右下角
            Positioned(
              right: -4,
              bottom: -4,
              child: ScaleTransition(
                scale: checkScale,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.like,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 15),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── 歡迎文字 ────────────────────────────────────────────────
        Text(
          '歡迎，$userName！',
          style: GoogleFonts.notoSansTc(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          '已成功登入 Google 帳號',
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 22),

        // ── +5 點 入帳動畫 badge ────────────────────────────────────
        SlideTransition(
          position: badgeSlide,
          child: FadeTransition(
            opacity: badgeFade,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppColors.gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5864).withValues(alpha: 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    '+$bonusCredits 點 已入帳',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('✨', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),

        // ── 確認按鈕 ────────────────────────────────────────────────
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onDone();
          },
          child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: AppColors.gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5864).withValues(alpha: 0.30),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '太棒了，開始使用 🚀',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Error View ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onGuest;

  const _ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onGuest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DragHandle(),
        const SizedBox(height: 28),

        // ── 錯誤圖示 ────────────────────────────────────────────────
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F0),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFFF3B30),
            size: 38,
          ),
        ),
        const SizedBox(height: 18),

        // ── 標題 ────────────────────────────────────────────────────
        Text(
          '哎呀，登入失敗了',
          style: GoogleFonts.notoSansTc(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: GoogleFonts.notoSansTc(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // ── 重試按鈕 ────────────────────────────────────────────────
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            onRetry();
          },
          child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: AppColors.gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5864).withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '重試登入',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: onGuest,
          child: Text(
            '繼續以訪客身份使用',
            style: GoogleFonts.notoSansTc(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.gradient.createShader(b),
            child: Icon(icon, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.notoSansTc(
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

class _SocialLoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

  const _SocialLoginButton({
    required this.isLoading,
    required this.onTap,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foregroundColor.withValues(alpha: 0.6),
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: foregroundColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Google Icon ───────────────────────────────────────────────────────────────

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleIconPainter()),
    );
  }
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    const sweepRad = 3.14159265 * 2 / 4;
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];

    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -3.14159265 / 2 + sweepRad * i,
        sweepRad,
        true,
        paint,
      );
    }

    paint.color = Colors.white;
    canvas.drawCircle(c, r * 0.6, paint);

    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - r * 0.25, r, r * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
