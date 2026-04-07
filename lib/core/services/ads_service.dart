import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // ── 每日廣告上限 ───────────────────────────────────────────────────────────
  static const int kDailyAdLimit = 2;
  static const _kPrefDate  = 'ad_date';
  static const _kPrefCount = 'ad_count';

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
  }

  /// 取得今日已觀看廣告次數（跨日自動重置）
  Future<int> getTodayAdCount() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    if (prefs.getString(_kPrefDate) != today) {
      await prefs.setString(_kPrefDate, today);
      await prefs.setInt(_kPrefCount, 0);
      return 0;
    }
    return prefs.getInt(_kPrefCount) ?? 0;
  }

  Future<void> _incrementAdCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getTodayAdCount();
    await prefs.setInt(_kPrefCount, current + 1);
  }

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
        ? 'ca-app-pub-0557904547936841/5007506675' // 正式 Android Rewarded ID
        : 'ca-app-pub-0557904547936841/9694031576'; // 正式 iOS Rewarded ID
  }

  RewardedAd? _rewardedAd;
  bool _isLoading = false;
  Completer<void>? _adCompleter;
  PermissionStatus _attStatus = PermissionStatus.denied;

  bool get isAdReady => _rewardedAd != null;

  /// iOS：ATT 被永久拒絕，AdMob 無法投放個人化廣告（fill rate 趨近 0）
  bool get isAttPermanentlyDenied =>
      Platform.isIOS && _attStatus == PermissionStatus.permanentlyDenied;

  // ── 初始化 ─────────────────────────────────────────────────────────────────

  /// 階段一：Android 初始化 AdMob SDK。
  /// iOS 刻意略過：必須先取得 ATT 授權才能初始化 MobileAds，
  /// 否則系統可能直接封鎖 ATT dialog，參見 requestAttAndPreload()。
  Future<void> initialize() async {
    if (Platform.isIOS) {
      FirebaseService.log('AdsService: iOS — skip pre-ATT MobileAds init');
      return;
    }
    await _initMobileAds();
  }

  Future<void> _initMobileAds() async {
    try {
      await MobileAds.instance.initialize();
      FirebaseService.log('AdsService: MobileAds initialized');
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'ads_init_failed');
    }
  }

  /// 階段二（iOS）：ATT 授權 → 初始化 MobileAds → 預載廣告。
  /// 階段二（Android）：直接預載（initialize() 已在 main 完成）。
  /// 必須在 Flutter UI 可見後呼叫（HomeScreen.initState）。
  Future<void> requestAttAndPreload() async {
    try {
      if (Platform.isIOS) {
        _attStatus = await Permission.appTrackingTransparency.request();
        FirebaseService.log('AdsService: ATT status=$_attStatus');
        // 取得 ATT 結果後才初始化 SDK（符合 Google AdMob iOS 規範）
        await _initMobileAds();
      } else {
        _attStatus = PermissionStatus.granted;
      }
      loadRewardedAd(); // 預載廣告
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'ads_att_failed');
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
              _adCompleter?.complete();
              _adCompleter = null;
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              loadRewardedAd();
              FirebaseService.log('AdsService: ad failed to show: $error');
              _adCompleter?.complete();
              _adCompleter = null;
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
  /// [onFailed]   — 廣告未就緒、顯示失敗、或已達每日上限時呼叫
  Future<void> showRewardedAd({
    required VoidCallback onRewarded,
    VoidCallback? onFailed,
  }) async {
    // 每日上限檢查
    final count = await getTodayAdCount();
    if (count >= kDailyAdLimit) {
      FirebaseService.log('AdsService: daily ad limit reached ($count/$kDailyAdLimit)');
      onFailed?.call();
      return;
    }

    if (_rewardedAd == null) {
      FirebaseService.log('AdsService: ad not ready');
      loadRewardedAd();
      onFailed?.call();
      return;
    }

    _adCompleter = Completer<void>();

    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (_, reward) {
          FirebaseService.log(
            'AdsService: user earned reward — ${reward.amount} ${reward.type}',
          );
          _incrementAdCount(); // 記錄已觀看
          onRewarded();
        },
      );
      // 等廣告關閉後才 return，確保 _watchAd 的 rewarded 旗標已被設置
      await (_adCompleter?.future ?? Future.value());
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'ads_show_failed');
      _adCompleter?.complete();
      _adCompleter = null;
      onFailed?.call();
    }
  }
}
