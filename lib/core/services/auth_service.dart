import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'firebase_service.dart';
import '../../features/billing/models/credit_history_entry.dart';

/// 點數常數
const int kGuestInitialCredits = 1;      // 訪客初始點數（刻意給少，降低重裝誘因）
const int kLoginBonusCredits = 5;        // 登入獎勵（升級訪客 → 正式帳號）
const int kNewAccountCredits = 5;        // 全新帳號初始點數

/// Firebase Auth + Firestore 用戶管理服務
class AuthService {
  AuthService._();

  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;
  static bool get isSignedIn => currentUser != null;
  static bool get isGuest => currentUser?.isAnonymous ?? true;

  // ── 匿名登入（訪客模式）──────────────────────────────────────────────────

  /// App 啟動時呼叫：若沒有任何登入狀態，自動建立匿名帳號
  static Future<void> signInAnonymouslyIfNeeded() async {
    if (_auth.currentUser != null) return; // 已有帳號（匿名或真實）

    String uid;
    try {
      final result = await _auth.signInAnonymously();
      uid = result.user!.uid;
      FirebaseService.log('AuthService: anonymous sign-in uid=$uid');
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'anon_sign_in_failed');
      return;
    }

    try {
      await _ensureUserDoc(uid, isGuest: true);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'ensure_user_doc_failed');
    }
  }

  // ── Token 刷新 ─────────────────────────────────────────────────────────

  /// 強制刷新目前用戶的 ID token（若有 session 的話）。
  ///
  /// Auth session 跨 app launch 持久化，但 ID token 1 小時過期。
  /// 在呼叫 Cloud Function 前應確保 token 有效。
  static Future<void> ensureValidToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.getIdToken(true);
      FirebaseService.log('AuthService: token refreshed uid=${user.uid}');
    } catch (e) {
      FirebaseService.log('AuthService: token refresh failed: $e');
    }
  }

  // ── Google 登入 ──────────────────────────────────────────────────────────

  /// 使用 Google 帳號登入（或升級訪客帳號）
  ///
  /// 回傳：[AuthResult]（success / cancelled / error）
  static Future<AuthResult> signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return AuthResult.cancelled;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return _signInWithCredential(credential);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'google_sign_in_failed');
      return AuthResult.error(e.toString());
    }
  }

  // ── Apple 登入 ───────────────────────────────────────────────────────────

  /// 使用 Apple ID 登入（或升級訪客帳號）
  static Future<AuthResult> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      return _signInWithCredential(oauthCredential);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return AuthResult.cancelled;
      }
      await FirebaseService.recordError(e, StackTrace.current,
          reason: 'apple_sign_in_failed');
      return AuthResult.error(e.message);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'apple_sign_in_failed');
      return AuthResult.error(e.toString());
    }
  }

  // ── 登出 ─────────────────────────────────────────────────────────────────

  static Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
    // 登出後立即重建匿名帳號
    await signInAnonymouslyIfNeeded();
    FirebaseService.log('AuthService: signed out → new anonymous session');
  }

  // ── Firestore 點數操作 ────────────────────────────────────────────────────

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// 取得目前用戶的點數（null = 文件不存在）
  static Future<int?> getCredits(String uid) async {
    final doc = await _userDoc(uid).get();
    if (!doc.exists) return null;
    return doc.data()?['credits'] as int?;
  }

  /// 原子性扣點（Firestore Transaction）
  ///
  /// 回傳 `true` = 扣點成功；`false` = 點數不足
  static Future<bool> consumeCredit(String uid) async {
    try {
      return await _db.runTransaction((tx) async {
        final ref = _userDoc(uid);
        final doc = await tx.get(ref);
        final credits = (doc.data()?['credits'] as int?) ?? 0;
        if (credits <= 0) return false;
        tx.update(ref, {'credits': credits - 1, 'updatedAt': FieldValue.serverTimestamp()});
        return true;
      });
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'consume_credit_failed');
      return false;
    }
  }

  /// 購買點數包後增加點數（內部呼叫 addCredits，reason = purchase）
  static Future<void> addCreditsFromPurchase(String uid, int amount) =>
      addCredits(uid, amount, reason: CreditHistoryReason.purchase);

  /// 增加點數（看廣告 / 登入獎勵後呼叫）
  static Future<void> addCredits(
    String uid,
    int amount, {
    String reason = CreditHistoryReason.rewardedAd,
  }) async {
    try {
      await _db.runTransaction((tx) async {
        final ref = _userDoc(uid);
        tx.set(
          ref,
          {
            'credits': FieldValue.increment(amount),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      // 寫入點數歷史（非原子，失敗不影響主流程）
      await _writeHistoryEntry(uid,
          type: 'earned', amount: amount, reason: reason);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'add_credits_failed');
    }
  }

  /// 寫入一筆點數歷史紀錄（best-effort，失敗僅記錄）
  static Future<void> _writeHistoryEntry(
    String uid, {
    required String type,
    required int amount,
    required String reason,
  }) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('creditHistory')
          .add({
        'type': type,
        'amount': amount,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack,
          reason: 'write_credit_history_failed');
    }
  }

  // ── Private ──────────────────────────────────────────────────────────────

  /// 嘗試將目前匿名帳號「升級」為 Google/Apple 帳號。
  ///
  /// - 若成功：同一個 UID，Firestore 文件不動，補發登入獎勵
  /// - 若已有帳號（credential-already-in-use）：切換到現有帳號，合併點數
  static Future<AuthResult> _signInWithCredential(AuthCredential credential) async {
    final currentUser = _auth.currentUser;

    // 訪客升級：嘗試 link
    if (currentUser != null && currentUser.isAnonymous) {
      try {
        final anonCredits = (await getCredits(currentUser.uid)) ?? 0;
        await currentUser.linkWithCredential(credential);
        // 升級成功：同一 UID，給登入獎勵（若已升級過不重複給）
        await _promoteUser(currentUser.uid, previousCredits: anonCredits);
        FirebaseService.log(
          'AuthService: anonymous upgraded uid=${currentUser.uid}',
        );
        return AuthResult.success;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'email-already-in-use') {
          rethrow;
        }
        // 現有帳號 → 切換過去並合併點數
        final anonCredits = (await getCredits(currentUser.uid)) ?? 0;
        await _auth.signInWithCredential(
            e.credential ?? credential,
        );
        final newUid = _auth.currentUser!.uid;
        await _ensureUserDoc(newUid, isGuest: false);
        // 把訪客剩餘點數搬過去
        if (anonCredits > 0) {
          await addCredits(newUid, anonCredits);
          FirebaseService.log(
            'AuthService: merged $anonCredits credits to uid=$newUid',
          );
        }
        FirebaseService.log('AuthService: switched to existing uid=$newUid');
        return AuthResult.success;
      }
    }

    // 非訪客：直接登入
    final result = await _auth.signInWithCredential(credential);
    await _ensureUserDoc(result.user!.uid, isGuest: false);
    return AuthResult.success;
  }

  /// 確保 Firestore 有該用戶文件；首次建立時分配點數
  static Future<void> _ensureUserDoc(String uid, {required bool isGuest}) async {
    final ref = _userDoc(uid);
    bool created = false;
    final credits = isGuest ? kGuestInitialCredits : kNewAccountCredits;
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      if (doc.exists) return; // 已存在，不覆蓋
      created = true;
      tx.set(ref, {
        'credits': credits,
        'isAnonymous': isGuest,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    if (created) {
      FirebaseService.log(
        'AuthService: user doc created uid=$uid isGuest=$isGuest',
      );
      await _writeHistoryEntry(uid,
          type: 'earned',
          amount: credits,
          reason: CreditHistoryReason.newAccount);
    }
  }

  /// 訪客升級：標記為非匿名，補發登入獎勵點數
  static Future<void> _promoteUser(String uid, {required int previousCredits}) async {
    final ref = _userDoc(uid);
    bool promoted = false;
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      final data = doc.data() ?? {};
      if (data['isAnonymous'] != true) return; // 已升級過，不重複

      promoted = true;
      // 在現有點數基礎上累加登入獎勵
      final currentCredits = (data['credits'] as int?) ?? previousCredits;
      tx.update(ref, {
        'credits': currentCredits + kLoginBonusCredits,
        'isAnonymous': false,
        'promotedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    if (promoted) {
      FirebaseService.log(
          'AuthService: user promoted uid=$uid +$kLoginBonusCredits credits');
      await _writeHistoryEntry(uid,
          type: 'earned',
          amount: kLoginBonusCredits,
          reason: CreditHistoryReason.loginBonus);
    }
  }
}

// ── Auth 結果 ──────────────────────────────────────────────────────────────

enum _AuthStatus { success, cancelled, error }

class AuthResult {
  final _AuthStatus _status;
  final String? errorMessage;

  const AuthResult._({required _AuthStatus status, this.errorMessage})
      : _status = status;

  static const success = AuthResult._(status: _AuthStatus.success);
  static const cancelled = AuthResult._(status: _AuthStatus.cancelled);
  static AuthResult error(String msg) =>
      AuthResult._(status: _AuthStatus.error, errorMessage: msg);

  bool get isSuccess => _status == _AuthStatus.success;
  bool get isCancelled => _status == _AuthStatus.cancelled;
  bool get isError => _status == _AuthStatus.error;
}
