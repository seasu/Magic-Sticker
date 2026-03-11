import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/widgets/login_bottom_sheet.dart';
import '../../features/billing/providers/credit_provider.dart';

/// AppBar 右上角的點數 + 帳號狀態徽章
///
/// - **已登入**：Google 頭像小圓 + 點數（漸層背景）
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
      onTap: () => context.push('/credit-history'),
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
            Icon(Icons.person_outline_rounded,
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
            Icon(Icons.keyboard_arrow_down_rounded,
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
