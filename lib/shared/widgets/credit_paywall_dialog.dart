import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/ads_service.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/widgets/login_bottom_sheet.dart';
import '../../features/billing/providers/credit_provider.dart';
import '../../features/billing/widgets/credit_shop_sheet.dart';

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
  int _todayAdCount = 0;
  String? _adErrorMsg;
  bool _attDenied = false;

  @override
  void initState() {
    super.initState();
    _attDenied = AdsService.instance.isAttPermanentlyDenied;
    AdsService.instance.getTodayAdCount().then((count) {
      if (mounted) setState(() => _todayAdCount = count);
    });
    // ref.read 在 initState 中合法（ConsumerState 已初始化）
    unawaited(AnalyticsService.logPaywallShown(isGuest: ref.read(isGuestProvider)));
  }

  // ── 看廣告 ────────────────────────────────────────────────────────────────

  // ATT 被永久拒絕時，彈出說明 Dialog 指引用戶前往正確設定路徑
  void _showAttInstructions() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('開啟廣告追蹤', style: TextStyle(fontFamily: 'OpenHuninn')),
        content: const Text(
          '請按照以下步驟開啟 Magic Sticker 的廣告追蹤：\n\n'
          '1. 開啟「設定」App\n'
          '2. 前往「隱私權與安全性」\n'
          '3. 點選「追蹤」\n'
          '4. 開啟「Magic Sticker」的追蹤開關\n\n'
          '開啟後回到此畫面即可觀看廣告。',
          style: TextStyle(fontFamily: 'OpenHuninn', height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了', style: TextStyle(fontFamily: 'OpenHuninn')),
          ),
        ],
      ),
    ).then((_) async {
      // Dialog 關閉後重新確認 ATT 狀態（用戶可能已去設定開啟）
      if (mounted && Platform.isIOS) {
        final status = await Permission.appTrackingTransparency.status;
        if (mounted) setState(() => _attDenied = status == PermissionStatus.permanentlyDenied);
      }
    });
  }

  Future<void> _watchAd() async {
    if (_attDenied) { _showAttInstructions(); return; }
    if (_isWatchingAd || _isLoggingIn) return;
    setState(() { _isWatchingAd = true; _adErrorMsg = null; });
    unawaited(AnalyticsService.logAdWatchStarted());

    bool rewarded = false;
    await AdsService.instance.showRewardedAd(
      // 廣告 SDK callback 為同步，只設 flag；
      // 等廣告關閉後（showRewardedAd return）再呼叫 CF，
      // 避免 Firestore Security Rules 封鎖 App 端直接寫入。
      onRewarded: () => rewarded = true,
      onFailed: () {
        if (mounted) setState(() => _adErrorMsg = '廣告載入中，請稍後再試');
      },
    );

    if (rewarded) {
      // 透過 Cloud Function 在 Server 端原子性加點，避免直接寫 Firestore
      try {
        final result = await FirebaseFunctions.instanceFor(region: 'asia-east1')
            .httpsCallable('rewardAdCredit')
            .call<Map<String, dynamic>>();
        final credits = (result.data['credits'] as num?)?.toInt();
        if (credits != null && mounted) {
          ref.read(creditProvider.notifier).updateCredits(credits);
          unawaited(AnalyticsService.logAdWatchCompleted(creditsAfter: credits));
        }
      } catch (e) {
        // CF 失敗時從 Firestore 重讀，保持 UI 一致
        if (mounted) {
          ref.read(creditProvider.notifier).reload();
        }
      }
    }

    if (mounted) {
      setState(() {
        _isWatchingAd = false;
        if (rewarded) _todayAdCount++;
      });
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
    final adLimitReached = _todayAdCount >= AdsService.kDailyAdLimit;

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
              style: TextStyle(fontFamily: 'OpenHuninn',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '生成 1 張貼圖需要 1 點\n透過下列方式免費取得：',
              style: TextStyle(fontFamily: 'OpenHuninn',
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
                label: '登入帳號，獲得 5 點',
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
                      style: TextStyle(fontFamily: 'OpenHuninn',
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
              enabled: !isLoading && !adLimitReached,
              onTap: _watchAd,
              icon: _attDenied
                  ? Icons.settings_outlined
                  : Icons.play_circle_outline_rounded,
              label: '看廣告，獲得 1 點',
              sublabel: adLimitReached
                  ? '今日已達上限（$_todayAdCount/${AdsService.kDailyAdLimit}）'
                  : _attDenied
                      ? '需允許廣告追蹤 → 查看說明'
                      : '短片約 15–30 秒',
              gradient: null,
              foregroundColor: AppColors.textPrimary,
              borderColor: AppColors.divider,
            ),
            if (_adErrorMsg != null) ...[
              const SizedBox(height: 6),
              Text(
                _adErrorMsg!,
                style: const TextStyle(
                  fontFamily: 'OpenHuninn',
                  fontSize: 12,
                  color: Colors.red,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 10),

            // ── 購買點數包 ────────────────────────────────────────────
            _OptionButton(
              isLoading: false,
              enabled: !isLoading,
              onTap: () {
                Navigator.of(context).pop(false);
                CreditShopSheet.show(context);
              },
              icon: Icons.shopping_bag_outlined,
              label: '購買點數包',
              sublabel: '一次買斷・永久有效',
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
                style: TextStyle(fontFamily: 'OpenHuninn',
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
                            style: TextStyle(fontFamily: 'OpenHuninn',
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: foregroundColor,
                            ),
                          ),
                          Text(
                            sublabel,
                            style: TextStyle(fontFamily: 'OpenHuninn',
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
