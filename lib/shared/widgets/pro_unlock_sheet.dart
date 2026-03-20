import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/firebase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/billing/providers/pro_purchase_provider.dart';
import '../../features/billing/services/iap_service.dart';

/// Pro 自訂輸入解鎖 Bottom Sheet（NT$49 一次性購買）
///
/// 顯示功能說明 + 定價，點擊「立即解鎖」觸發 Google Play Billing。
/// 購買成功後 [isProUnlockedProvider] 自動更新，Sheet 自動關閉。
class ProUnlockSheet extends ConsumerStatefulWidget {
  const ProUnlockSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProUnlockSheet(),
    );
  }

  @override
  ConsumerState<ProUnlockSheet> createState() => _ProUnlockSheetState();
}

class _ProUnlockSheetState extends ConsumerState<ProUnlockSheet> {
  bool _loading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    // 若購買成功（Firestore 寫入）→ 自動關閉 sheet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual<AsyncValue<bool>>(isProUnlockedProvider, (_, next) {
        if (next.valueOrNull == true && mounted) {
          Navigator.of(context).pop();
        }
      });
    });
  }

  Future<void> _onBuyPressed() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final result = await IAPService.instance.buyProCustomInput();
    if (!mounted) return;

    setState(() => _loading = false);

    switch (result) {
      case ProUnlockResult.success:
        // Sheet 會由 isProUnlockedProvider listener 自動關閉
        break;
      case ProUnlockResult.canceled:
        // 使用者取消，不顯示錯誤
        break;
      case ProUnlockResult.verifyFailed:
        setState(() => _errorMsg = '驗證失敗，請重試或聯絡客服');
      case ProUnlockResult.productNotFound:
        setState(() => _errorMsg = '商品載入失敗，請稍後再試');
      case ProUnlockResult.storeUnavailable:
        setState(() => _errorMsg = 'Google Play 不可用，請確認網路連線');
      case ProUnlockResult.alreadyPending:
        // 已有購買程序進行中，不顯示錯誤
        break;
      case ProUnlockResult.error:
        setState(() => _errorMsg = '購買失敗，請重試');
    }
  }

  Future<void> _onRestorePressed() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      await IAPService.instance.restorePurchases();
      // restorePurchases 觸發 purchaseStream → _fulfillPro → Firestore 寫入
      // isProUnlockedProvider 更新後 sheet 自動關閉
    } catch (e, stack) {
      FirebaseService.log('ProUnlockSheet: restore failed: $e');
      await FirebaseService.recordError(e, stack, reason: 'pro_restore_failed');
      if (mounted) setState(() => _errorMsg = '還原失敗，請稍後再試');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 把手 ──
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // ── 標題 ──
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pro 自訂輸入',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '一次性解鎖 · 永久使用',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── 功能說明 ──
          _FeatureRow(
            icon: Icons.brush_rounded,
            title: '自訂風格描述',
            desc: '輸入任意風格（如「厚塗油畫」「浮世繪」），不受 12 種預設限制',
          ),
          const SizedBox(height: 12),
          _FeatureRow(
            icon: Icons.emoji_emotions_rounded,
            title: '自訂情緒描述',
            desc: '用自己的語言描述情緒（如「興奮尖叫」「淡定無語」），AI 精準詮釋',
          ),
          const SizedBox(height: 20),

          // ── 價格 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '一次性解鎖價格',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                Text(
                  'NT\$49',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFFF5864),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 錯誤訊息 ──
          if (_errorMsg != null) ...[
            Text(
              _errorMsg!,
              style: const TextStyle(fontSize: 13, color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],

          // ── 購買按鈕 ──
          SizedBox(
            width: double.infinity,
            child: AnimatedOpacity(
              opacity: _loading ? 0.65 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: _loading ? null : _onBuyPressed,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: _loading ? null : AppColors.gradient,
                    color: _loading ? Colors.grey.shade300 : null,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: _loading
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFFFF5864).withValues(alpha: 0.30),
                              blurRadius: 16,
                              offset: const Offset(0, 5),
                            ),
                          ],
                  ),
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_open_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '立即解鎖 · NT\$49',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── 還原購買 ──
          GestureDetector(
            onTap: _loading ? null : _onRestorePressed,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '已購買？點此還原',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black38,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.black26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 功能列 ────────────────────────────────────────────────────────────────────

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD700).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFFFFA500)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
