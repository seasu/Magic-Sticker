import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/theme/app_colors.dart';
import '../models/credit_pack.dart';
import '../providers/iap_provider.dart';
import '../services/iap_service.dart';

/// 點數商店 Bottom Sheet
///
/// 顯示三個點數包（嘗鮮包 / 創作者包 / 達人包），
/// 商品價格從 Store 讀取，失敗時 fallback 顯示 CreditPack.priceLabel。
class CreditShopSheet extends ConsumerStatefulWidget {
  const CreditShopSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreditShopSheet(),
    );
  }

  @override
  ConsumerState<CreditShopSheet> createState() => _CreditShopSheetState();
}

class _CreditShopSheetState extends ConsumerState<CreditShopSheet> {
  StreamSubscription<IapPurchaseResult>? _purchaseSub;

  @override
  void initState() {
    super.initState();
    _purchaseSub = IAPService.instance.purchaseResultStream.listen(_onResult);
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  void _onResult(IapPurchaseResult result) {
    if (!mounted) return;
    // 清除購買中狀態
    ref.read(iapPurchasingProvider.notifier).state = null;

    if (result.success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '購買成功！已獲得 ${result.creditsEarned} 點 ⚡',
          style: GoogleFonts.notoSansTc(fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF34C759),
        duration: const Duration(seconds: 3),
      ));
    } else if (result.error != 'canceled') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '購買失敗，請稍後再試',
          style: GoogleFonts.notoSansTc(fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _onTapPurchase(CreditPack pack, ProductDetails? storeProduct) async {
    final purchasing = ref.read(iapPurchasingProvider);
    if (purchasing != null) return; // 已有進行中的購買

    ref.read(iapPurchasingProvider.notifier).state = pack.productId;

    if (storeProduct != null) {
      await IAPService.instance.purchase(storeProduct);
    } else {
      // Store 商品未載入：提示用戶
      ref.read(iapPurchasingProvider.notifier).state = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '商店連線失敗，請確認網路後重試',
            style: GoogleFonts.notoSansTc(fontSize: 13),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  Future<void> _onRestore() async {
    await IAPService.instance.restorePurchases();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '已提交恢復購買請求',
          style: GoogleFonts.notoSansTc(fontSize: 13),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(iapProductsProvider);
    final purchasingId = ref.watch(iapPurchasingProvider);

    final storeProducts = productsAsync.valueOrNull ?? [];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 拖曳把手 ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── 標題 ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (b) => AppColors.gradient.createShader(b),
                  child: const Icon(Icons.bolt_rounded,
                      size: 26, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  '購買點數包',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '一次買斷・永久有效',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── 商品卡片列表 ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: CreditPack.packs.map((pack) {
                final storeProduct = storeProducts.where(
                  (p) => p.id == pack.productId,
                ).firstOrNull;
                final isPurchasing = purchasingId == pack.productId;
                final anyPurchasing = purchasingId != null;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PackCard(
                    pack: pack,
                    storeProduct: storeProduct,
                    isPurchasing: isPurchasing,
                    disabled: anyPurchasing && !isPurchasing,
                    onTap: () => _onTapPurchase(pack, storeProduct),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── 恢復購買 ──────────────────────────────────────────────
          TextButton(
            onPressed: _onRestore,
            child: Text(
              '恢復購買',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 單張商品卡片 ───────────────────────────────────────────────────────────────

class _PackCard extends StatelessWidget {
  final CreditPack pack;
  final ProductDetails? storeProduct;
  final bool isPurchasing;
  final bool disabled;
  final VoidCallback onTap;

  const _PackCard({
    required this.pack,
    required this.storeProduct,
    required this.isPurchasing,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPopular = pack.badge.isNotEmpty;
    final priceText = storeProduct?.price ?? pack.priceLabel;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: disabled ? 0.45 : 1.0,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPopular
                ? const Color(0xFFFD297B).withValues(alpha: 0.4)
                : AppColors.divider,
            width: isPopular ? 1.5 : 1.0,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  // ── 左側：包名 + 描述 + 每點價 ──────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pack.label,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '上架 ${pack.sets} 組貼圖  ·  ${pack.credits} 點',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pack.perCreditLabel,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 11,
                            color: AppColors.textSecondary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── 右側：價格 + 購買按鈕 ────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        priceText,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: isPopular
                              ? const Color(0xFFFD297B)
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: disabled ? null : onTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: isPopular ? AppColors.gradient : null,
                            color: isPopular ? null : AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: isPopular
                                ? null
                                : Border.all(color: AppColors.divider),
                          ),
                          child: isPurchasing
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: isPopular
                                        ? Colors.white
                                        : AppColors.textSecondary,
                                  ),
                                )
                              : Text(
                                  '購買',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isPopular
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── 最受歡迎 badge ────────────────────────────────────
            if (isPopular)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: const BoxDecoration(
                    gradient: AppColors.gradient,
                    borderRadius:
                        BorderRadius.only(topRight: Radius.circular(15),
                            bottomLeft: Radius.circular(12)),
                  ),
                  child: Text(
                    pack.badge,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
