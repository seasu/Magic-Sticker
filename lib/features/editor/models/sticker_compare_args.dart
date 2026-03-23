import 'dart:typed_data';

import '../../../core/models/sticker_shape.dart';

/// 跳轉至 /sticker-compare 時攜帶的參數
class StickerCompareArgs {
  final String originalImagePath;
  final Uint8List stickerBytes;
  final StickerShape stickerShape;

  /// 來源頁：'editor' | 'replay'（用於 Analytics from 參數）
  final String from;

  const StickerCompareArgs({
    required this.originalImagePath,
    required this.stickerBytes,
    required this.stickerShape,
    this.from = 'editor',
  });
}
