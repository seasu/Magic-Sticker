import 'dart:typed_data';

import '../../../core/models/sticker_shape.dart';

/// 跳轉至 /sticker-compare 時攜帶的參數
class StickerCompareArgs {
  final String originalImagePath;
  final Uint8List stickerBytes;
  final StickerShape stickerShape;

  /// 來源頁：'editor' | 'replay'（用於 Analytics from 參數）
  final String from;

  /// 樣式索引（用於 ensureShareCode 建立挑戰碼的模板資訊）
  final int? styleIndex;

  /// 情緒類別 IDs（用於 ensureShareCode 建立挑戰碼的模板資訊）
  final List<String>? categoryIds;

  /// Pro 自訂風格/情緒描述（用於 pro_custom 挑戰碼）
  final String? customStyleDesc;
  final String? customEmotionDesc;

  const StickerCompareArgs({
    required this.originalImagePath,
    required this.stickerBytes,
    required this.stickerShape,
    this.from = 'editor',
    this.styleIndex,
    this.categoryIds,
    this.customStyleDesc,
    this.customEmotionDesc,
  });
}
