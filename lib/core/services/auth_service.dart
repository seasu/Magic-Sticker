import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1');

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
      // 透過 Cloud Function 建立 users/{uid} 文件並分配初始點數，
      // 避免 App 端直接寫 Firestore 被 Security Rules 封鎖。
      await _callInitUserSession(uid);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'init_user_session_failed');
    }
  }

  /// 呼叫 initUserSession Cloud Function，確保用戶文件存在並取得點數。
  ///
  /// [anonCredits] > 0 時，CF 會在 Server 端原子性地將匿名點數合併至目標帳號，
  /// 並將 [anonUid] 對應的匿名帳號 credits 歸零，防止重複 merge。
  static Future<int?> _callInitUserSession(
    String uid, {
    int anonCredits = 0,
    String? anonUid,
  }) async {
    final Map<String, dynamic> payload = {};
    if (anonCredits > 0) payload['anonCredits'] = anonCredits;
    if (anonUid != null && anonUid.isNotEmpty) payload['anonUid'] = anonUid;
    final result = await _fn
        .httpsCallable(
          'initUserSession',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
        )
        .call<Map<String, dynamic>>(
          payload.isNotEmpty ? payload : null,
        );
    final credits = (result.data['credits'] as num?)?.toInt();
    FirebaseService.log(
      'AuthService: initUserSession uid=$uid credits=$credits created=${result.data['created']}',
    );
    return credits;
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

      final result = await _signInWithCredential(credential);

      // Firebase Android SDK 有時不會在 linkWithCredential 後自動填入 photoURL，
      // 明確呼叫 updateProfile() 補上 Google 帳號的頭像與顯示名稱。
      if (result.isSuccess) {
        final user = _auth.currentUser;
        if (user != null) {
          final needsUpdate =
              (user.photoURL == null && googleUser.photoUrl != null) ||
              (user.displayName == null && googleUser.displayName != null);
          if (needsUpdate) {
            await user.updateProfile(
              photoURL: googleUser.photoUrl,
              displayName: user.displayName ?? googleUser.displayName,
            );
            await _auth.currentUser?.reload();
          }
        }
      }

      return result;
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'google_sign_in_failed');
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
        // reload() 更新 User 物件（photoURL / displayName 在 linkWithCredential 後
        // 不會自動寫入本機快取，必須主動 reload 才能從 Firebase 取回最新 profile）。
        await _auth.currentUser?.reload();
        // Force token refresh: linkWithCredential fires userChanges() but
        // the updated token may not yet be in the Firestore SDK's cache.
        await _auth.currentUser?.getIdToken(true);
        // 升級成功：同一 UID，給登入獎勵（若已升級過不重複給）
        bool didPromote = false;
        try {
          didPromote = await _promoteUser(currentUser.uid, previousCredits: anonCredits);
        } catch (e, stack) {
          await FirebaseService.recordError(e, stack,
              reason: 'post_link_promote_failed');
        }
        FirebaseService.log(
          'AuthService: anonymous upgraded uid=${currentUser.uid}',
        );
        return didPromote ? AuthResult.successWithBonus : AuthResult.success;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use' &&
            e.code != 'email-already-in-use') {
          rethrow;
        }
        // 現有帳號 → 切換過去並合併點數
        // 先記錄匿名 UID，signInWithCredential 後 currentUser 已換成正式帳號
        final anonUid = currentUser.uid;
        final anonCredits = (await getCredits(anonUid)) ?? 0;
        await _auth.signInWithCredential(e.credential ?? credential);

        // Force token refresh so subsequent Firestore calls get a valid JWT.
        // signInWithCredential fires userChanges() immediately but the new
        // ID token may not yet be in the Firestore SDK's cache.
        await _auth.currentUser?.getIdToken(true);

        final newUid = _auth.currentUser!.uid;
        try {
          await _callInitUserSession(newUid, anonCredits: anonCredits, anonUid: anonUid);
          if (anonCredits > 0) {
            FirebaseService.log(
              'AuthService: merged $anonCredits credits to uid=$newUid',
            );
          }
        } catch (firestoreErr, stack) {
          await FirebaseService.recordError(firestoreErr, stack,
              reason: 'post_signin_firestore_failed');
        }
        FirebaseService.log('AuthService: switched to existing uid=$newUid');
        return AuthResult.success;
      }
    }

    // 非訪客：直接登入
    final result = await _auth.signInWithCredential(credential);
    // Force token refresh before Firestore operations.
    await _auth.currentUser?.getIdToken(true);
    try {
      await _callInitUserSession(result.user!.uid);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack,
          reason: 'post_signin_ensure_doc_failed');
    }
    return AuthResult.success;
  }

  /// 訪客升級：標記為非匿名，補發登入獎勵點數
  /// 回傳 true = 本次實際升級並給點；false = 已升級過（不重複給）
  static Future<bool> _promoteUser(String uid, {required int previousCredits}) async {
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
    return promoted;
  }
}

// ── Auth 結果 ──────────────────────────────────────────────────────────────

enum _AuthStatus { success, cancelled, error }

class AuthResult {
  final _AuthStatus _status;
  final String? errorMessage;
  /// 本次登入是否實際完成「訪客 → 正式帳號」升級並發放獎勵點數
  final bool wasPromoted;

  const AuthResult._({
    required _AuthStatus status,
    this.errorMessage,
    this.wasPromoted = false,
  }) : _status = status;

  static const success = AuthResult._(status: _AuthStatus.success);
  static const successWithBonus =
      AuthResult._(status: _AuthStatus.success, wasPromoted: true);
  static const cancelled = AuthResult._(status: _AuthStatus.cancelled);
  static AuthResult error(String msg) =>
      AuthResult._(status: _AuthStatus.error, errorMessage: msg);

  bool get isSuccess => _status == _AuthStatus.success;
  bool get isCancelled => _status == _AuthStatus.cancelled;
  bool get isError => _status == _AuthStatus.error;
}
