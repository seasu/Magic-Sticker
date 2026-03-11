import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/widgets/login_bottom_sheet.dart';
import '../../features/billing/providers/credit_provider.dart';

/// AppBar 右上角的點數 + 帳號狀態徽章
///
/// - **已登入**：Google 頭像小圓 + 點數（漸層背景），點擊開啟帳號資訊 sheet
/// - **訪客**：人型 icon + 點數 + 「登入」提示，點擊開啟登入 sheet
class CreditBadge extends ConsumerWidget {
  const CreditBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(creditProvider);
    final isGuest = ref.watch(isGuestProvider);
    final isLow = credits <= 0;

    if (isGuest) {
      return _GuestBadge(
        credits: credits,
        onTap: () => LoginBottomSheet.show(context),
      );
    }

    return _LoggedInBadge(
      credits: credits,
      isLow: isLow,
      onTap: () => _UserAccountSheet.show(context, credits),
    );
  }
}

// ── 訪客徽章 ─────────────────────────────────────────────────────────────────

class _GuestBadge extends StatelessWidget {
  final int credits;
  final VoidCallback onTap;

  const _GuestBadge({required this.credits, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline_rounded,
                size: 13, color: AppColors.textSecondary),
            const SizedBox(width: 3),
            Text(
              '$credits',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── 登入後徽章 ────────────────────────────────────────────────────────────────

class _LoggedInBadge extends StatelessWidget {
  final int credits;
  final bool isLow;
  final VoidCallback onTap;

  const _LoggedInBadge({
    required this.credits,
    required this.isLow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    final displayName = user?.displayName ?? user?.email?.split('@').first;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: isLow ? null : AppColors.gradient,
          color: isLow ? const Color(0xFFF2F2F7) : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 使用者大頭貼（小圓） ──────────────────────────────
            _UserAvatar(
              photoUrl: photoUrl,
              displayName: displayName,
              isLow: isLow,
            ),
            const SizedBox(width: 5),
            // ── 點數 ──────────────────────────────────────────────
            Icon(
              isLow ? Icons.bolt_outlined : Icons.bolt_rounded,
              size: 13,
              color: isLow ? AppColors.textSecondary : Colors.white,
            ),
            const SizedBox(width: 2),
            Text(
              '$credits',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isLow ? AppColors.textSecondary : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── User Avatar（22×22 小圓） ──────────────────────────────────────────────────

class _UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String? displayName;
  final bool isLow;

  const _UserAvatar({this.photoUrl, this.displayName, required this.isLow});

  @override
  Widget build(BuildContext context) {
    final initial =
        (displayName?.isNotEmpty == true) ? displayName![0].toUpperCase() : '?';
    final borderColor = isLow ? AppColors.textSecondary.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.5);

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: ClipOval(
        child: photoUrl != null
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _InitialFallback(
                  initial: initial,
                  isLow: isLow,
                ),
              )
            : _InitialFallback(initial: initial, isLow: isLow),
      ),
    );
  }
}

class _InitialFallback extends StatelessWidget {
  final String initial;
  final bool isLow;

  const _InitialFallback({required this.initial, required this.isLow});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isLow ? AppColors.divider : Colors.white.withValues(alpha: 0.3),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: isLow ? AppColors.textSecondary : Colors.white,
          ),
        ),
      ),
    );
  }
}

// ── 帳號資訊 Bottom Sheet ──────────────────────────────────────────────────────

class _UserAccountSheet extends ConsumerWidget {
  final int credits;

  const _UserAccountSheet({required this.credits});

  static void show(BuildContext context, int credits) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserAccountSheet(credits: credits),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    final displayName = user?.displayName;
    final email = user?.email ?? '';
    final initial = (displayName?.isNotEmpty == true)
        ? displayName![0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : '?');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 拖曳把手 ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 24),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── 大頭貼 ────────────────────────────────────────────────
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.gradient,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFD297B).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(2.5),
            child: ClipOval(
              child: photoUrl != null
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _LargeInitial(initial: initial),
                    )
                  : _LargeInitial(initial: initial),
            ),
          ),
          const SizedBox(height: 14),
          // ── 顯示名稱 ──────────────────────────────────────────────
          if (displayName != null && displayName.isNotEmpty)
            Text(
              displayName,
              style: GoogleFonts.notoSansTc(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          const SizedBox(height: 4),
          // ── Email ─────────────────────────────────────────────────
          if (email.isNotEmpty)
            Text(
              email,
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 20),
          // ── 點數顯示 ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '剩餘點數',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.gradient.createShader(bounds),
                      child: const Icon(Icons.bolt_rounded,
                          size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$credits',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── 查看點數紀錄 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
                context.push('/credit-history');
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: const BorderSide(color: AppColors.divider),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                '查看點數紀錄',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── 登出 ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: OutlinedButton(
              onPressed: () async {
                Navigator.pop(context);
                await AuthService.signOut();
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                side: BorderSide(
                    color: AppColors.nope.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                '登出',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.nope,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeInitial extends StatelessWidget {
  final String initial;

  const _LargeInitial({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
