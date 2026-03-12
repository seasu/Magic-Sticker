import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firebase 認證狀態串流
///
/// `null` = 未登入（理論上 app 啟動後會立即建立匿名帳號，不應長時間為 null）
/// 使用 userChanges() 以感知 linkWithCredential 事件（匿名升級時 UID 不變，
/// 但 isAnonymous / displayName / photoURL 等屬性會變化）
final authStateProvider = StreamProvider<User?>((ref) {
  // userChanges() also emits when linkWithCredential / updateProfile occurs,
  // unlike authStateChanges() which only fires on sign-in/sign-out.
  return FirebaseAuth.instance.userChanges();
});

/// 目前登入的用戶（同步讀取，null = 尚未初始化）
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

/// 是否為訪客（匿名 / 未登入）
final isGuestProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  return user == null || user.isAnonymous;
});
