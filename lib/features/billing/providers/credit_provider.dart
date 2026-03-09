import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/services/firebase_service.dart';
import '../../auth/providers/auth_provider.dart';

/// 每次看廣告獲得的點數
const int kCreditsPerAd = 1;

// ── Provider ──────────────────────────────────────────────────────────────────

final creditProvider = NotifierProvider<CreditNotifier, int>(
  CreditNotifier.new,
);

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Firestore 為主的點數 Provider
///
/// 點數存在 Firestore `users/{uid}/credits`。
/// 切換帳號（匿名 → 登入）時自動重新載入。
class CreditNotifier extends Notifier<int> {
  @override
  int build() {
    // 監聽 auth 狀態，用戶切換時重新載入點數
    ref.listen<User?>(currentUserProvider, (prev, next) {
      if (next?.uid != prev?.uid) {
        _onUserChanged(next);
      }
    });

    // 初始化：讀取目前用戶的點數
    final user = ref.read(currentUserProvider);
    if (user != null) {
      _loadCredits(user.uid);
    }

    return 0; // 同步初始值，_loadCredits 非同步更新
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  bool get hasCredit => state > 0;

  /// 消耗 1 點（透過 Firestore Transaction，防止 race condition）
  ///
  /// 回傳 `true` = 扣點成功
  Future<bool> consumeCredit() async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return false;

    if (state <= 0) return false;

    final success = await AuthService.consumeCredit(uid);
    if (success) {
      state = state - 1;
      FirebaseService.log('CreditProvider: consumed 1 → remaining ${state}');
    }
    return success;
  }

  /// 增加點數（看廣告 / 登入獎勵後呼叫）
  Future<void> addCredits(int amount) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;

    await AuthService.addCredits(uid, amount);
    state = state + amount;
    FirebaseService.log('CreditProvider: +$amount → total ${state}');
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _onUserChanged(User? user) {
    if (user == null) {
      state = 0;
    } else {
      _loadCredits(user.uid);
    }
  }

  Future<void> _loadCredits(String uid) async {
    try {
      final credits = await AuthService.getCredits(uid);
      if (credits != null && ref.read(currentUserProvider)?.uid == uid) {
        state = credits;
        FirebaseService.log('CreditProvider: loaded $credits credits for uid=$uid');
      }
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'credit_load_failed');
    }
  }
}
