import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'firebase_service.dart';

/// AdMob 廣告服務（Rewarded Ad 單例）
///
/// 使用方式：
/// 1. `main()` 中 `await AdsService.instance.initialize()`
/// 2. 在需要前呼叫 `AdsService.instance.loadRewardedAd()`
/// 3. 使用者觸發後呼叫 `AdsService.instance.showRewardedAd(onRewarded: ...)`
class AdsService {
  AdsService._();
  static final instance = AdsService._();

  // ── Ad Unit IDs ────────────────────────────────────────────────────────────
  // 測試 ID（開發期間使用 Google 官方測試 unit）
  // 上線前請換成 AdMob Console 產出的正式 ID
  static String get _rewardedAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917' // Google 官方 Android 測試 ID
          : 'ca-app-pub-3940256099942544/1712485313'; // Google 官方 iOS 測試 ID
    }
    return Platform.isAndroid
        ? 'ca-app-pub-0557904547936841/7713706857' // 正式 Android Rewarded ID
        : 'ca-app-pub-3940256099942544/1712485313'; // iOS 暫用測試 ID（Phase 2 再換）
  }

  RewardedAd? _rewardedAd;
  bool _isLoading = false;

  bool get isAdReady => _rewardedAd != null;

  // ── 初始化 ─────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      FirebaseService.log('AdsService: MobileAds initialized');
      loadRewardedAd(); // 預載廣告
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'ads_init_failed');
    }
  }

  // ── 載入 Rewarded Ad ───────────────────────────────────────────────────────

  void loadRewardedAd() {
    if (_isLoading || _rewardedAd != null) return;
    _isLoading = true;

    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
          FirebaseService.log('AdsService: rewarded ad loaded');

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              loadRewardedAd(); // 關掉後立即預載下一則
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              loadRewardedAd();
              FirebaseService.log('AdsService: ad failed to show: $error');
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          FirebaseService.log('AdsService: failed to load ad: $error');
          // 30 秒後重試
          Future.delayed(const Duration(seconds: 30), loadRewardedAd);
        },
      ),
    );
  }

  // ── 顯示廣告 ───────────────────────────────────────────────────────────────

  /// 顯示激勵廣告。
  ///
  /// [onRewarded] — 使用者完整看完廣告後呼叫（可在此增加點數）
  /// [onFailed]   — 廣告未就緒或顯示失敗時呼叫
  Future<void> showRewardedAd({
    required VoidCallback onRewarded,
    VoidCallback? onFailed,
  }) async {
    if (_rewardedAd == null) {
      FirebaseService.log('AdsService: ad not ready');
      loadRewardedAd();
      onFailed?.call();
      return;
    }

    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (_, reward) {
          FirebaseService.log(
            'AdsService: user earned reward — ${reward.amount} ${reward.type}',
          );
          onRewarded();
        },
      );
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'ads_show_failed');
      onFailed?.call();
    }
  }
}
