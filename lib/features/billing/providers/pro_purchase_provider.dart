import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';

/// Pro 解鎖狀態（Firestore 即時串流）
///
/// true = 使用者已購買 pro_custom_input 且服務端驗證通過
final isProUnlockedProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(false);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('purchases')
      .doc('pro_custom_input')
      .snapshots()
      .map((snap) => snap.exists && (snap.data()?['verified'] as bool? ?? false));
});
