import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/services/firebase_service.dart';
import '../models/credit_pack.dart';

/// Pro 解鎖購買結果
enum ProUnlockResult {
  success,
  canceled,
  error,
  verifyFailed,
  productNotFound,
  storeUnavailable,
  alreadyPending,
}

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

/// Pro 自訂輸入 Google Play 商品 ID
const kProCustomInputProductId = 'pro_custom_input';

/// Google Play / App Store 內購服務（Singleton）
///
/// 使用方式：
/// 1. `main()` 中 `await IAPService.instance.initialize()`
/// 2. `CreditShopSheet` 呼叫 `IAPService.instance.purchase(productDetails)`
/// 3. 監聽 `IAPService.instance.purchaseResultStream` 取得結果
/// 4. `IAPService.instance.buyProCustomInput()` 觸發 Pro 解鎖購買
///
/// ⚠️ TODO（生產上線前）：
///   Credit pack 購買成功後直接在本機 Firestore 增加點數，**未驗證收據**。
///   上線前須實作 Cloud Function `fulfillCreditPurchase(receiptData, platform)`，
///   於 Server 端驗證 Google Play purchaseToken / App Store receipt，
///   再原子性增加點數，防止偽造收據。
class IAPService {
  IAPService._();
  static final instance = IAPService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1');

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final _resultController = StreamController<IapPurchaseResult>.broadcast();

  /// 訂閱此 Stream 以接收購買成功/失敗通知
  Stream<IapPurchaseResult> get purchaseResultStream => _resultController.stream;

  List<ProductDetails> _products = [];

  /// 已從商店載入的商品列表（按價格排序）
  List<ProductDetails> get products => List.unmodifiable(_products);

  bool _initialized = false;

  /// 等待 pro_custom_input 購買結果的 Completer
  Completer<ProUnlockResult>? _proPendingCompleter;

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

  // ── Pro 解鎖 ────────────────────────────────────────────────────────────────

  /// 觸發 pro_custom_input 購買，等待 Google Play Billing + CF 驗證完成後回傳結果。
  Future<ProUnlockResult> buyProCustomInput() async {
    if (_proPendingCompleter != null && !_proPendingCompleter!.isCompleted) {
      return ProUnlockResult.alreadyPending;
    }

    final available = await _iap.isAvailable();
    if (!available) return ProUnlockResult.storeUnavailable;

    final response = await _iap.queryProductDetails({kProCustomInputProductId});
    if (response.productDetails.isEmpty) {
      FirebaseService.log(
        'IAPService: pro product not found. notFound=${response.notFoundIDs}',
      );
      return ProUnlockResult.productNotFound;
    }

    _proPendingCompleter = Completer<ProUnlockResult>();

    try {
      await _iap.buyNonConsumable(
        purchaseParam:
            PurchaseParam(productDetails: response.productDetails.first),
      );
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'iap_pro_buy_failed');
      _proPendingCompleter!.complete(ProUnlockResult.error);
      _proPendingCompleter = null;
      return ProUnlockResult.error;
    }

    return _proPendingCompleter!.future;
  }

  // ── 載入商品 ────────────────────────────────────────────────────────────────

  Future<void> loadProducts() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        FirebaseService.log('IAPService: store not available');
        return;
      }

      final ids = {
        ...CreditPack.packs.map((p) => p.productId),
        kProCustomInputProductId,
      };
      final response = await _iap.queryProductDetails(ids);

      if (response.error != null) {
        FirebaseService.log('IAPService: queryProductDetails error: ${response.error}');
      }

      // 只排序點數包（不含 pro_custom_input）
      _products = List<ProductDetails>.from(
        response.productDetails.where(
          (p) => p.id != kProCustomInputProductId,
        ),
      )..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));

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
      final code = purchase.error?.code ?? '';
      FirebaseService.log('IAPService: purchase error: $msg code=$code');

      if (purchase.productID == kProCustomInputProductId) {
        // itemAlreadyOwned（BillingResponseCode=7）：使用者已在 Google Play 購買過，
        // 靜默觸發還原讓 purchaseStream 以 restored 狀態重新送達 → _fulfillPro。
        // _proPendingCompleter 保持 pending，15 秒無回應則 fallback 為 verifyFailed。
        if (_isItemAlreadyOwned(code, msg)) {
          FirebaseService.log(
            'IAPService: itemAlreadyOwned — triggering silent restore',
          );
          unawaited(restorePurchases());
          final pendingCompleter = _proPendingCompleter;
          if (pendingCompleter != null) {
            Future.delayed(const Duration(seconds: 15), () {
              if (!pendingCompleter.isCompleted) {
                pendingCompleter.complete(ProUnlockResult.verifyFailed);
                if (_proPendingCompleter == pendingCompleter) {
                  _proPendingCompleter = null;
                }
              }
            });
          }
        } else {
          _proPendingCompleter?.complete(ProUnlockResult.error);
          _proPendingCompleter = null;
        }
      } else {
        _resultController.add(IapPurchaseResult.failure(msg));
      }
      // BillingResponse.itemAlreadyOwned 等 error 狀態下，
      // purchase 物件可能是 PurchaseDetails 基底類別而非 GooglePlayPurchaseDetails，
      // 直接呼叫 completePurchase 會在 plugin 內部 cast 時 crash。
      // 加 pendingCompletePurchase 判斷避免不必要的 completePurchase 呼叫。
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      return;
    }

    if (purchase.status == PurchaseStatus.canceled) {
      if (purchase.productID == kProCustomInputProductId) {
        _proPendingCompleter?.complete(ProUnlockResult.canceled);
        _proPendingCompleter = null;
      } else {
        _resultController.add(const IapPurchaseResult.failure('canceled'));
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      return;
    }

    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      await _fulfill(purchase);
    }
  }

  Future<void> _fulfill(PurchaseDetails purchase) async {
    // Pro 解鎖：走 verifyProPurchase CF
    if (purchase.productID == kProCustomInputProductId) {
      await _fulfillPro(purchase);
      return;
    }

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
      final token = purchase.verificationData.serverVerificationData.isNotEmpty
          ? purchase.verificationData.serverVerificationData
          : purchase.verificationData.localVerificationData;

      final result = await _fn
          .httpsCallable(
            'fulfillCreditPurchase',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>({
        'purchaseToken': token,
        'productId': purchase.productID,
      });

      final creditsEarned = (result.data['credits'] as num?)?.toInt() ?? pack.credits;
      FirebaseService.log(
        'IAPService: fulfilled $creditsEarned credits uid=$uid product=${pack.productId}',
      );

      // completePurchase 只在 CF 確認成功後才呼叫。
      // 若 CF 失敗（網路逾時等），保留 purchase pending 狀態，
      // Google Play 下次啟動 App 時會重新透過 purchaseStream 送達，可再次觸發驗證。
      await _iap.completePurchase(purchase);
      _resultController.add(IapPurchaseResult.success(creditsEarned));
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'iap_fulfill_failed');
      // 不呼叫 completePurchase，讓 Google Play 在下次啟動時重試
      _resultController.add(IapPurchaseResult.failure(e.toString()));
    }
  }

  Future<void> _fulfillPro(PurchaseDetails purchase) async {
    final token = purchase.verificationData.serverVerificationData.isNotEmpty
        ? purchase.verificationData.serverVerificationData
        : purchase.verificationData.localVerificationData;

    try {
      FirebaseService.log(
        'IAPService: calling verifyProPurchase orderId=${purchase.purchaseID}',
      );
      await _fn
          .httpsCallable(
            'verifyProPurchase',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<Map<String, dynamic>>({
        'purchaseToken': token,
        'orderId': purchase.purchaseID ?? '',
      });
      FirebaseService.log('IAPService: Pro unlock verified OK');
      // completePurchase 只在 CF 確認成功後才呼叫。
      // 若 CF 失敗（網路逾時、Play API 錯誤等），保留 purchase pending 狀態，
      // Google Play 下次啟動 App 時會重新透過 purchaseStream 送達，可再次觸發驗證。
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      _proPendingCompleter?.complete(ProUnlockResult.success);
    } catch (e, stack) {
      FirebaseService.log('IAPService: verifyProPurchase failed: $e');
      await FirebaseService.recordError(e, stack, reason: 'iap_pro_verify_failed');
      // 不呼叫 completePurchase，讓 Google Play 在下次啟動時重試
      _proPendingCompleter?.complete(ProUnlockResult.verifyFailed);
    } finally {
      _proPendingCompleter = null;
    }
  }

  // ── 工具 ─────────────────────────────────────────────────────────────────────

  /// Google Play BillingResponseCode.ITEM_ALREADY_OWNED = 7
  bool _isItemAlreadyOwned(String code, String message) {
    if (code == '7') return true;
    final lower = message.toLowerCase();
    return lower.contains('already_owned') ||
        lower.contains('already owned') ||
        lower.contains('itemalreadyowned');
  }

  // ── 釋放 ────────────────────────────────────────────────────────────────────

  void dispose() {
    _subscription?.cancel();
    _resultController.close();
  }
}
