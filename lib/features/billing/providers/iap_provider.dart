import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/iap_service.dart';

/// 從商店載入的商品列表（失敗回傳空 list，不拋錯）
final iapProductsProvider = FutureProvider.autoDispose<List<ProductDetails>>(
  (ref) async {
    await IAPService.instance.loadProducts();
    return IAPService.instance.products;
  },
);

/// 目前正在購買中的 productId（null = 無進行中）
final iapPurchasingProvider = StateProvider<String?>((ref) => null);
