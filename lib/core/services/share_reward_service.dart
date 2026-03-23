import 'package:cloud_functions/cloud_functions.dart';

/// Cloud Function `shareRewardGrant` 的回傳結果
class ShareRewardResult {
  final bool granted;
  final int newBalance;
  final String reason;

  const ShareRewardResult({
    required this.granted,
    required this.newBalance,
    required this.reason,
  });

  factory ShareRewardResult.fromMap(Map<dynamic, dynamic> map) {
    return ShareRewardResult(
      granted: map['granted'] as bool? ?? false,
      newBalance: (map['newBalance'] as num?)?.toInt() ?? 0,
      reason: map['reason'] as String? ?? '',
    );
  }
}

/// 分享獎勵服務層：呼叫 Cloud Function `shareRewardGrant`。
///
/// 每日首次點擊分享按鈕（且 session 有看過比對頁）即 +1 點。
/// 回傳 [ShareRewardResult]，呼叫方可用 granted 判斷是否顯示獎勵 Toast。
class ShareRewardService {
  ShareRewardService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1')
      .httpsCallable('shareRewardGrant');

  /// 請求分享獎勵。
  ///
  /// [sessionHadCompareView] 本 session 是否已看過比對頁（防濫用雙條件之一）。
  static Future<ShareRewardResult> grantReward({
    required bool sessionHadCompareView,
  }) async {
    final result = await _fn.call({
      'sessionHadCompareView': sessionHadCompareView,
    });
    return ShareRewardResult.fromMap(
      Map<dynamic, dynamic>.from(result.data as Map),
    );
  }
}
