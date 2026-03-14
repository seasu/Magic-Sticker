import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/firebase_service.dart';
import '../models/credit_pack.dart';

/// IAP 購買結果
class IapPurchaseResult {
  final bool success;
  final int? creditsEarned;
  final String? error;

  const IapPurchaseResult.success(this.creditsEarned)
      : success = true,
        error = null;
  const IapPurchaseResult.failure(this.error)
      : success = false,
        creditsEarned = null;
}

/// Google Play / App Store 內購服務（Singleton）
///
/// 使用方式：
/// 1. `main()` 中 `await IAPService.instance.initialize()`
/// 2. `CreditShopSheet` 呼叫 `IAPService.instance.purchase(productDetails)`
/// 3. 監聽 `IAPService.instance.purchaseResultStream` 取得結果
///
/// ⚠️ TODO（生產上線前）：
///   目前購買成功後直接在本機 Firestore 增加點數，**未驗證收據**。
///   上線前須實作 Cloud Function `fulfillCreditPurchase(receiptData, platform)`，
///   於 Server 端驗證 Google Play purchaseToken / App Store receipt，
///   再原子性增加點數，防止偽造收據。
class IAPService {
  IAPService._();
  static final instance = IAPService._();

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final _resultController = StreamController<IapPurchaseResult>.broadcast();

  /// 訂閱此 Stream 以接收購買成功/失敗通知
  Stream<IapPurchaseResult> get purchaseResultStream => _resultController.stream;

  List<ProductDetails> _products = [];

  /// 已從商店載入的商品列表（按價格排序）
  List<ProductDetails> get products => List.unmodifiable(_products);

  bool _initialized = false;

  // ── 初始化 ─────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) => FirebaseService.log('IAPService: purchaseStream error: $e'),
    );

    await loadProducts();
    FirebaseService.log('IAPService: initialized');
  }

  // ── 載入商品 ────────────────────────────────────────────────────────────────

  Future<void> loadProducts() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        FirebaseService.log('IAPService: store not available');
        return;
      }

      final ids = CreditPack.packs.map((p) => p.productId).toSet();
      final response = await _iap.queryProductDetails(ids);

      if (response.error != null) {
        FirebaseService.log('IAPService: queryProductDetails error: ${response.error}');
      }

      _products = List<ProductDetails>.from(response.productDetails)
        ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));

      if (kDebugMode) {
        debugPrint('[IAP] Loaded ${_products.length} products: '
            '${_products.map((p) => '${p.id}=${p.price}').join(', ')}');
        if (response.notFoundIDs.isNotEmpty) {
          debugPrint('[IAP] Not found in store: ${response.notFoundIDs}');
        }
      }
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'iap_load_products_failed');
    }
  }

  // ── 購買 ────────────────────────────────────────────────────────────────────

  Future<void> purchase(ProductDetails product) async {
    try {
      final param = PurchaseParam(productDetails: product);
      await _iap.buyConsumable(purchaseParam: param);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'iap_purchase_failed');
      _resultController.add(IapPurchaseResult.failure(e.toString()));
    }
  }

  // ── 恢復購買 ────────────────────────────────────────────────────────────────

  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'iap_restore_failed');
    }
  }

  // ── 購買結果處理 ────────────────────────────────────────────────────────────

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      await _handlePurchase(purchase);
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    FirebaseService.log(
      'IAPService: purchase update — id=${purchase.productID} status=${purchase.status}',
    );

    if (purchase.status == PurchaseStatus.pending) {
      // 等待中（例如家長控制審核），不做任何事
      return;
    }

    if (purchase.status == PurchaseStatus.error) {
      final msg = purchase.error?.message ?? 'unknown error';
      FirebaseService.log('IAPService: purchase error: $msg');
      _resultController.add(IapPurchaseResult.failure(msg));
      await _iap.completePurchase(purchase);
      return;
    }

    if (purchase.status == PurchaseStatus.canceled) {
      _resultController.add(const IapPurchaseResult.failure('canceled'));
      await _iap.completePurchase(purchase);
      return;
    }

    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      await _fulfill(purchase);
    }
  }

  Future<void> _fulfill(PurchaseDetails purchase) async {
    final pack = CreditPack.packs.where(
      (p) => p.productId == purchase.productID,
    ).firstOrNull;

    if (pack == null) {
      FirebaseService.log('IAPService: unknown productID=${purchase.productID}');
      await _iap.completePurchase(purchase);
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      FirebaseService.log('IAPService: fulfill called but no current user');
      await _iap.completePurchase(purchase);
      return;
    }

    try {
      // ⚠️ TODO: 上線前換成 Cloud Function fulfillCreditPurchase(receipt, platform)
      // 以 Server 端驗證收據後再入帳，防止偽造。
      await AuthService.addCreditsFromPurchase(uid, pack.credits);
      FirebaseService.log(
        'IAPService: fulfilled ${pack.credits} credits uid=$uid product=${pack.productId}',
      );
      _resultController.add(IapPurchaseResult.success(pack.credits));
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'iap_fulfill_failed');
      _resultController.add(IapPurchaseResult.failure(e.toString()));
    }

    await _iap.completePurchase(purchase);
  }

  // ── 釋放 ────────────────────────────────────────────────────────────────────

  void dispose() {
    _subscription?.cancel();
    _resultController.close();
  }
}
