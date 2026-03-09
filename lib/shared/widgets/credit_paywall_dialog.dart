import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/ads_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/billing/providers/credit_provider.dart';

/// 點數不足時彈出的 Paywall 對話框
///
/// 提供兩個選項：
/// 1. 看廣告獲得 1 點（免費）
/// 2. 購買點數包（未來 IAP 串接）
///
/// 使用方式：
/// ```dart
/// final earned = await CreditPaywallDialog.show(context, ref);
/// if (earned) { /* 已獲得點數，可繼續 */ }
/// ```
class CreditPaywallDialog extends ConsumerStatefulWidget {
  const CreditPaywallDialog({super.key});

  /// 顯示 paywall，回傳 `true` 表示使用者看完廣告並獲得點數。
  static Future<bool> show(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CreditPaywallDialog(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<CreditPaywallDialog> createState() => _CreditPaywallDialogState();
}

class _CreditPaywallDialogState extends ConsumerState<CreditPaywallDialog> {
  bool _isWatchingAd = false;

  Future<void> _watchAd() async {
    if (_isWatchingAd) return;
    setState(() => _isWatchingAd = true);

    bool rewarded = false;

    await AdsService.instance.showRewardedAd(
      onRewarded: () {
        rewarded = true;
        ref.read(creditProvider.notifier).addCredits(kCreditsPerAd);
      },
      onFailed: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '廣告載入中，請稍後再試',
                style: GoogleFonts.notoSansTc(fontSize: 13),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );

    if (mounted) {
      setState(() => _isWatchingAd = false);
      if (rewarded) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 圖示 ──────────────────────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
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

            // ── 標題 ──────────────────────────────────────────────────
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
              '生成 1 組貼圖需要 1 點\n觀看短片廣告即可免費獲得',
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── 看廣告按鈕 ─────────────────────────────────────────────
            _WatchAdButton(
              isLoading: _isWatchingAd,
              onTap: _watchAd,
            ),
            const SizedBox(height: 12),

            // ── 購買點數（預留，未來 IAP 串接）──────────────────────────
            OutlinedButton.icon(
              onPressed: () {
                // TODO: 串接 IAP 購買頁面
                Navigator.of(context).pop(false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '購買功能即將推出 🛒',
                      style: GoogleFonts.notoSansTc(fontSize: 13),
                    ),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              label: Text(
                '購買點數包',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: const BorderSide(color: AppColors.divider, width: 1.5),
                foregroundColor: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),

            // ── 關閉 ───────────────────────────────────────────────────
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
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

// ── 看廣告按鈕（帶 loading 狀態） ────────────────────────────────────────────

class _WatchAdButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;

  const _WatchAdButton({required this.isLoading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: isLoading ? null : AppColors.gradient,
          color: isLoading ? AppColors.divider : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.textSecondary,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '看廣告，免費獲得 1 點',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
