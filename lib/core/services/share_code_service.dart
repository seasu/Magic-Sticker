import 'package:cloud_functions/cloud_functions.dart';

/// Cloud Function `ensureShareCode` 的回傳結果
class ShareCodeResult {
  final String code;
  final String deepLink;
  final bool reused;

  const ShareCodeResult({
    required this.code,
    required this.deepLink,
    required this.reused,
  });

  factory ShareCodeResult.fromMap(Map<dynamic, dynamic> map) {
    return ShareCodeResult(
      code: map['code'] as String,
      deepLink: map['deepLink'] as String,
      reused: map['reused'] as bool? ?? false,
    );
  }
}

/// 分享時自動建立（或重用）挑戰碼的服務層。
///
/// 呼叫 Cloud Function `ensureShareCode`，回傳 [ShareCodeResult]。
/// 若 CF 呼叫失敗，呼叫方可 catch 並降級為純圖片分享。
class ShareCodeService {
  ShareCodeService._();

  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-east1')
      .httpsCallable('ensureShareCode');

  /// 建立或重用挑戰碼。
  ///
  /// [templateType] 'preset' 或 'pro_custom'（有自訂描述時自動設為 pro_custom）
  /// [presetStyleIndex] 風格索引（nullable）
  /// [presetCategoryIds] 情緒類別 IDs（nullable）
  /// [customStyleDesc] Pro 自訂風格描述（nullable）
  /// [customEmotionDesc] Pro 自訂情緒描述（nullable）
  static Future<ShareCodeResult> ensureShareCode({
    int? presetStyleIndex,
    List<String>? presetCategoryIds,
    String? customStyleDesc,
    String? customEmotionDesc,
  }) async {
    final templateType = (customStyleDesc != null || customEmotionDesc != null)
        ? 'pro_custom'
        : 'preset';
    final result = await _fn.call({
      'templateType': templateType,
      if (presetStyleIndex != null) 'presetStyleIndex': presetStyleIndex,
      if (presetCategoryIds != null) 'presetCategoryIds': presetCategoryIds,
      if (customStyleDesc != null) 'customStyleDesc': customStyleDesc,
      if (customEmotionDesc != null) 'customEmotionDesc': customEmotionDesc,
    });
    return ShareCodeResult.fromMap(
      Map<dynamic, dynamic>.from(result.data as Map),
    );
  }
}
