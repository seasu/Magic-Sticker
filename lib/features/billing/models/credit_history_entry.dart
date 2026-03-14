import 'package:cloud_firestore/cloud_firestore.dart';

/// 點數異動類型
enum CreditHistoryType {
  earned,  // 獲得點數（新帳號、登入獎勵、看廣告）
  spent,   // 消費點數（生成貼圖）
  refund,  // 退款（API 失敗退點）
}

/// 點數異動原因
class CreditHistoryReason {
  static const newAccount = 'new_account';
  static const loginBonus = 'login_bonus';
  static const rewardedAd = 'rewarded_ad';
  static const purchase = 'purchase';  // IAP 點數包購買
  static const generateStickerImage = 'generate_sticker_image';
  static const rateLimited = 'rate_limited';
  static const apiError = 'api_error';
  static const noImageReturned = 'no_image_returned';
}

class CreditHistoryEntry {
  final String id;
  final CreditHistoryType type;
  final int amount;
  final String reason;
  final DateTime createdAt;

  const CreditHistoryEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  factory CreditHistoryEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final typeStr = data['type'] as String? ?? 'earned';
    final ts = data['createdAt'];
    return CreditHistoryEntry(
      id: doc.id,
      type: _parseType(typeStr),
      amount: (data['amount'] as num?)?.toInt() ?? 0,
      reason: data['reason'] as String? ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }

  static CreditHistoryType _parseType(String s) {
    switch (s) {
      case 'spent':
        return CreditHistoryType.spent;
      case 'refund':
        return CreditHistoryType.refund;
      default:
        return CreditHistoryType.earned;
    }
  }

  /// 人類可讀的原因描述（繁體中文）
  String get reasonLabel {
    switch (reason) {
      case CreditHistoryReason.newAccount:
        return '新帳號獎勵';
      case CreditHistoryReason.loginBonus:
        return '登入獎勵';
      case CreditHistoryReason.rewardedAd:
        return '觀看廣告';
      case CreditHistoryReason.purchase:
        return '購買點數包';
      case CreditHistoryReason.generateStickerImage:
        return '生成貼圖';
      case CreditHistoryReason.rateLimited:
      case CreditHistoryReason.apiError:
      case CreditHistoryReason.noImageReturned:
        return '生成失敗退點';
      default:
        return reason;
    }
  }
}
