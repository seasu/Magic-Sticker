/// 點數包定義
///
/// productId 需與 Google Play Console / App Store Connect 設定的商品 ID 一致。
/// 定價以「可上架幾組 LINE 貼圖」作為心智模型，1 組 = 8 張。
class CreditPack {
  final String productId;
  final int credits;
  final String label;
  final String badge;       // 空字串 = 無標籤；'最受歡迎' = 顯示 badge
  final int sets;           // 可上架貼圖組數
  final String priceLabel;  // fallback 顯示用（Store 未回傳 formattedPrice 時）

  const CreditPack({
    required this.productId,
    required this.credits,
    required this.label,
    required this.badge,
    required this.sets,
    required this.priceLabel,
  });

  /// 每點單價（NT$ 數值，僅用於 UI 顯示）
  String get perCreditLabel {
    // 從 priceLabel 取出數字後計算
    final raw = priceLabel.replaceAll(RegExp(r'[^0-9]'), '');
    final price = int.tryParse(raw);
    if (price == null || credits == 0) return '';
    final perCredit = price / credits;
    return 'NT\$${perCredit.toStringAsFixed(2)}/點';
  }

  static const packs = [
    CreditPack(
      productId: 'credits_08',
      credits: 8,
      label: '嘗鮮包',
      badge: '',
      sets: 1,
      priceLabel: 'NT\$30',
    ),
    CreditPack(
      productId: 'credits_24',
      credits: 24,
      label: '創作者包',
      badge: '最受歡迎',
      sets: 3,
      priceLabel: 'NT\$79',
    ),
    CreditPack(
      productId: 'credits_80',
      credits: 80,
      label: '達人包',
      badge: '',
      sets: 10,
      priceLabel: 'NT\$199',
    ),
  ];
}
