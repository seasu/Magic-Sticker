import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/ads_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/widgets/login_bottom_sheet.dart';
import '../../features/billing/providers/credit_provider.dart';

/// 點數不足時彈出的 Paywall 對話框
///
/// 選項（依用戶狀態動態顯示）：
/// 1. 登入獲得 5 點（僅訪客顯示）
/// 2. 看廣告獲得 1 點（所有用戶）
/// 3. 購買點數包（預留）
///
/// 回傳 `true` = 已獲得點數，可繼續操作
class CreditPaywallDialog extends ConsumerStatefulWidget {
  const CreditPaywallDialog({super.key});

  static Future<bool> show(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CreditPaywallDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<CreditPaywallDialog> createState() =>
      _CreditPaywallDialogState();
}

class _CreditPaywallDialogState extends ConsumerState<CreditPaywallDialog> {
  bool _isWatchingAd = false;
  bool _isLoggingIn = false;

  // ── 看廣告 ────────────────────────────────────────────────────────────────

  Future<void> _watchAd() async {
    if (_isWatchingAd || _isLoggingIn) return;
    setState(() => _isWatchingAd = true);

    bool rewarded = false;
    await AdsService.instance.showRewardedAd(
      onRewarded: () {
        rewarded = true;
        ref.read(creditProvider.notifier).addCredits(kCreditsPerAd);
      },
      onFailed: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('廣告載入中，請稍後再試',
                style: GoogleFonts.notoSansTc(fontSize: 13)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ));
        }
      },
    );

    if (mounted) {
      setState(() => _isWatchingAd = false);
      if (rewarded) Navigator.of(context).pop(true);
    }
  }

  // ── 登入升級 ──────────────────────────────────────────────────────────────

  Future<void> _login() async {
    if (_isWatchingAd || _isLoggingIn) return;
    setState(() => _isLoggingIn = true);

    Navigator.of(context).pop(false); // 先關閉 paywall
    final loggedIn = await LoginBottomSheet.show(context);
    // 登入成功後 CreditProvider 會自動從 Firestore 更新點數
    // 呼叫方會在 consumeCredit 前重新讀取 creditProvider.state
    if (loggedIn && mounted) {
      // 通知呼叫方可以繼續（透過重新嘗試流程）
      // Note: 因為已 pop(false)，這裡不需要再 pop
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = ref.watch(isGuestProvider);
    final isLoading = _isWatchingAd || _isLoggingIn;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 圖示 ────────────────────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                gradient: AppColors.gradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),

            // ── 標題 ────────────────────────────────────────────────
            Text(
              '點數不足',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '生成 1 張貼圖需要 1 點\n透過下列方式免費取得：',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── 登入獲得 5 點（僅訪客顯示）──────────────────────────
            if (isGuest) ...[
              _OptionButton(
                isLoading: _isLoggingIn,
                enabled: !isLoading,
                onTap: _login,
                icon: Icons.person_add_rounded,
                label: '登入帳號，獲得 7 點',
                sublabel: '跨裝置同步 · 永久保存',
                gradient: AppColors.gradient,
                foregroundColor: Colors.white,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '或',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 10),
            ],

            // ── 看廣告 +1 點 ─────────────────────────────────────────
            _OptionButton(
              isLoading: _isWatchingAd,
              enabled: !isLoading,
              onTap: _watchAd,
              icon: Icons.play_circle_outline_rounded,
              label: '看廣告，獲得 1 點',
              sublabel: '短片約 15–30 秒',
              gradient: null,
              foregroundColor: AppColors.textPrimary,
              borderColor: AppColors.divider,
            ),
            const SizedBox(height: 10),

            // ── 購買點數（預留）──────────────────────────────────────
            _OptionButton(
              isLoading: false,
              enabled: !isLoading,
              onTap: () {
                Navigator.of(context).pop(false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('購買功能即將推出 🛒',
                      style: GoogleFonts.notoSansTc(fontSize: 13)),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ));
              },
              icon: Icons.shopping_bag_outlined,
              label: '購買點數包',
              sublabel: '即將推出',
              gradient: null,
              foregroundColor: AppColors.textPrimary,
              borderColor: AppColors.divider,
            ),
            const SizedBox(height: 4),

            // ── 取消 ─────────────────────────────────────────────────
            TextButton(
              onPressed:
                  isLoading ? null : () => Navigator.of(context).pop(false),
              child: Text(
                '取消',
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 選項按鈕 ──────────────────────────────────────────────────────────────────

class _OptionButton extends StatelessWidget {
  final bool isLoading;
  final bool enabled;
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final String sublabel;
  final LinearGradient? gradient;
  final Color foregroundColor;
  final Color? borderColor;

  const _OptionButton({
    required this.isLoading,
    required this.enabled,
    required this.onTap,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.gradient,
    required this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasGrad = gradient != null;
    return GestureDetector(
      onTap: (enabled && !isLoading) ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1.0 : 0.5,
        child: Container(
          height: 60,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: hasGrad ? gradient : null,
            color: hasGrad ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: borderColor != null
                ? Border.all(color: borderColor!, width: 1.5)
                : null,
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
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(icon, color: foregroundColor, size: 22),
                      const SizedBox(width: 12),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: foregroundColor,
                            ),
                          ),
                          Text(
                            sublabel,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: foregroundColor.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
