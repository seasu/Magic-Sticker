import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/widgets/login_bottom_sheet.dart';
import '../../features/billing/providers/credit_provider.dart';
import '../../features/billing/widgets/credit_shop_sheet.dart';

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
              style: TextStyle(fontFamily: 'OpenHuninn',
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

class _LoggedInBadge extends ConsumerWidget {
  final int credits;
  final bool isLow;
  final VoidCallback onTap;

  const _LoggedInBadge({
    required this.credits,
    required this.isLow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
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
              style: TextStyle(fontFamily: 'OpenHuninn',
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
            ? CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _InitialFallback(
                  initial: initial,
                  isLow: isLow,
                ),
                errorWidget: (_, __, ___) => _InitialFallback(
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

class _UserAccountSheet extends ConsumerStatefulWidget {
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
  ConsumerState<_UserAccountSheet> createState() => _UserAccountSheetState();
}

class _UserAccountSheetState extends ConsumerState<_UserAccountSheet> {
  bool _deleting = false;
  bool _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await ref.read(creditProvider.notifier).reload();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
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
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _LargeInitial(initial: initial),
                      errorWidget: (_, __, ___) =>
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
              style: TextStyle(fontFamily: 'OpenHuninn',
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
              style: TextStyle(fontFamily: 'OpenHuninn',
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 12),
          // ── UID（debug 用，點擊複製） ──────────────────────────────
          if (user?.uid case final String uid)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: uid));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('UID 已複製'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'uid  ',
                      style: TextStyle(
                        fontFamily: 'OpenHuninn',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        uid,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.copy_rounded,
                        size: 14,
                        color: AppColors.textSecondary.withValues(alpha: 0.6)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
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
                  style: TextStyle(fontFamily: 'OpenHuninn',
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
                      '${widget.credits}',
                      style: TextStyle(fontFamily: 'OpenHuninn',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _refreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : GestureDetector(
                            onTap: _handleRefresh,
                            child: Icon(
                              Icons.refresh_rounded,
                              size: 16,
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ── 購買點數 ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                CreditShopSheet.show(context);
              },
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      '購買點數',
                      style: TextStyle(fontFamily: 'OpenHuninn',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded,
                        size: 20, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                style: TextStyle(fontFamily: 'OpenHuninn',
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
                style: TextStyle(fontFamily: 'OpenHuninn',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.nope,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── 刪除帳號 ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _deleting
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          '刪除中...',
                          style: TextStyle(
                            fontFamily: 'OpenHuninn',
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : TextButton.icon(
                    onPressed: _confirmDeleteAccount,
                    icon: Icon(Icons.delete_forever_rounded,
                        size: 16,
                        color: AppColors.nope.withValues(alpha: 0.5)),
                    label: Text(
                      '刪除帳號',
                      style: TextStyle(
                        fontFamily: 'OpenHuninn',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.nope.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _confirmDeleteAccount() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          '確認刪除帳號',
          style: TextStyle(fontFamily: 'OpenHuninn', fontWeight: FontWeight.w800),
        ),
        content: const Text(
          '刪除後，以下資料將永久消失且無法恢復：\n\n• 帳號點數與交易紀錄\n• 本機貼圖生成紀錄\n\n確定要刪除嗎？',
          style: TextStyle(fontFamily: 'OpenHuninn', height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消', style: TextStyle(fontFamily: 'OpenHuninn')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop(); // 關閉確認 dialog，sheet 保持開啟
              setState(() => _deleting = true);
              try {
                await AuthService.deleteAccount();
                if (!mounted) return;
                setState(() => _deleting = false);
                // 顯示成功提示，等用戶確認後再關閉 sheet
                await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => AlertDialog(
                    title: const Text(
                      '帳號已刪除',
                      style: TextStyle(
                        fontFamily: 'OpenHuninn',
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    content: const Text(
                      '您的帳號資料已成功刪除。',
                      style: TextStyle(fontFamily: 'OpenHuninn', height: 1.6),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          '確認',
                          style: TextStyle(
                            fontFamily: 'OpenHuninn',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (mounted) Navigator.of(context).pop(); // 關閉 sheet
              } catch (_) {
                if (!mounted) return;
                setState(() => _deleting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      '刪除帳號失敗，請稍後再試',
                      style: TextStyle(fontFamily: 'OpenHuninn'),
                    ),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            },
            child: Text(
              '確認刪除',
              style: TextStyle(
                fontFamily: 'OpenHuninn',
                fontWeight: FontWeight.w700,
                color: AppColors.nope,
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
