import 'package:firebase_analytics/firebase_analytics.dart';

/// 病毒成長漏斗的 5 個關鍵埋點事件。
///
/// 事件命名統一 snake_case；所有參數均符合 Firebase Analytics 限制
/// （String / int / double / bool，單一值上限 100 字元）。
class AnalyticsService {
  AnalyticsService._();

  static final _analytics = FirebaseAnalytics.instance;

  // ── Event 1: compare_screen_viewed ────────────────────────────────────────

  /// 使用者進入比對頁時呼叫。
  ///
  /// [from] 'editor' | 'replay'
  /// [shape] 'circle' | 'square'
  /// [abVariant] 'A' | 'B'（分享按鈕文案 A/B 測試）
  static Future<void> logCompareScreenViewed({
    required String from,
    required String shape,
    required String abVariant,
  }) =>
      _analytics.logEvent(
        name: 'compare_screen_viewed',
        parameters: {'from': from, 'shape': shape, 'ab_variant': abVariant},
      );

  // ── Event 2: share_compare_tapped ─────────────────────────────────────────

  /// 使用者點擊「分享」按鈕時呼叫（分享 sheet 彈出前）。
  ///
  /// [hasLink] 分享文案是否已帶有 deep link（Sprint 2 後為 true）
  static Future<void> logShareCompareTapped({
    required String from,
    required String shape,
    required String abVariant,
    required bool hasLink,
  }) =>
      _analytics.logEvent(
        name: 'share_compare_tapped',
        parameters: {
          'from': from,
          'shape': shape,
          'ab_variant': abVariant,
          'has_link': hasLink ? 1 : 0,
        },
      );

  // ── Event 3: share_compare_dismissed ──────────────────────────────────────

  /// 使用者取消或分享失敗時呼叫。
  ///
  /// [reason] 'cancelled' | 'failed'
  static Future<void> logShareCompareDismissed({required String reason}) =>
      _analytics.logEvent(
        name: 'share_compare_dismissed',
        parameters: {'reason': reason},
      );

  // ── Event 4: share_reward_granted ─────────────────────────────────────────

  /// Cloud Function 確認入帳後呼叫（Sprint 2）。
  static Future<void> logShareRewardGranted({int credits = 1}) =>
      _analytics.logEvent(
        name: 'share_reward_granted',
        parameters: {'credits': credits},
      );

  // ── Event 5: challenge_link_opened ────────────────────────────────────────

  /// 朋友點擊 deep link 開啟 App 後呼叫（Sprint 2 deep link routing）。
  ///
  /// [installed] App 是否已安裝（true = 直接開啟，false = 安裝後回流）
  /// [resolved] Code 是否成功解析為有效挑戰
  static Future<void> logChallengeLinkOpened({
    required String code,
    required bool installed,
    required bool resolved,
  }) =>
      _analytics.logEvent(
        name: 'challenge_link_opened',
        parameters: {
          'code': code,
          'installed': installed ? 1 : 0,
          'resolved': resolved ? 1 : 0,
        },
      );

  // ── 點數漏斗埋點 ──────────────────────────────────────────────────────────

  /// Paywall 對話框出現時呼叫。
  ///
  /// [isGuest] 是否為訪客（匿名用戶）
  static Future<void> logPaywallShown({required bool isGuest}) =>
      _analytics.logEvent(
        name: 'paywall_shown',
        parameters: {'is_guest': isGuest ? 1 : 0},
      );

  /// 用戶點擊「看廣告」按鈕（ATT 未被拒絕、廣告流程正常啟動）。
  static Future<void> logAdWatchStarted() =>
      _analytics.logEvent(name: 'ad_watch_started');

  /// 廣告完整看完且點數已透過 CF 入帳。
  ///
  /// [creditsAfter] CF 回傳的最新點數餘額
  static Future<void> logAdWatchCompleted({required int creditsAfter}) =>
      _analytics.logEvent(
        name: 'ad_watch_completed',
        parameters: {'credits_after': creditsAfter},
      );

  /// Cloud Function 成功扣點（生成一張貼圖）。
  ///
  /// [creditsBefore] 扣點前的本機點數快照
  static Future<void> logCreditSpent({required int creditsBefore}) =>
      _analytics.logEvent(
        name: 'credit_spent',
        parameters: {'credits_before': creditsBefore},
      );

  /// Cloud Function 回傳點數不足（server-side 驗證失敗）。
  static Future<void> logCreditInsufficient() =>
      _analytics.logEvent(name: 'credit_insufficient');
}
