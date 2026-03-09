import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/firebase_service.dart';

// ── 常數 ──────────────────────────────────────────────────────────────────────

/// 新用戶首次安裝贈送的免費點數
const _kInitialFreeCredits = 3;

/// SharedPreferences key
const _kCreditsKey = 'user_credits';

/// 每次看廣告獲得的點數
const int kCreditsPerAd = 1;

// ── Provider ──────────────────────────────────────────────────────────────────

final creditProvider = NotifierProvider<CreditNotifier, int>(
  CreditNotifier.new,
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class CreditNotifier extends Notifier<int> {
  @override
  int build() {
    // 非同步載入，初始值先給 0；載入完成後 state 會更新
    _load();
    return 0;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// 是否有足夠點數（>= 1）
  bool get hasCredit => state > 0;

  /// 消耗 1 點（生成前呼叫）。
  ///
  /// 回傳 `true` 表示扣點成功，`false` 表示點數不足。
  Future<bool> consumeCredit() async {
    if (state <= 0) return false;
    final newVal = state - 1;
    state = newVal;
    await _persist(newVal);
    FirebaseService.log('CreditProvider: consumed 1 credit → remaining $newVal');
    return true;
  }

  /// 增加點數（看廣告 / 購買後呼叫）
  Future<void> addCredits(int amount) async {
    final newVal = state + amount;
    state = newVal;
    await _persist(newVal);
    FirebaseService.log('CreditProvider: +$amount credits → total $newVal');
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 首次安裝：key 不存在 → 贈送免費點數
      if (!prefs.containsKey(_kCreditsKey)) {
        await prefs.setInt(_kCreditsKey, _kInitialFreeCredits);
        state = _kInitialFreeCredits;
        FirebaseService.log(
          'CreditProvider: new user → gifted $_kInitialFreeCredits free credits',
        );
      } else {
        state = prefs.getInt(_kCreditsKey) ?? 0;
        FirebaseService.log('CreditProvider: loaded ${state} credits');
      }
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'credit_load_failed');
    }
  }

  Future<void> _persist(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kCreditsKey, value);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'credit_persist_failed');
    }
  }
}
