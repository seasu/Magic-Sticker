import 'dart:typed_data';

import '../../../core/models/sticker_shape.dart';

/// 跳轉至 /sticker-compare 時攜帶的參數
class StickerCompareArgs {
  final String originalImagePath;
  final Uint8List stickerBytes;
  final StickerShape stickerShape;

  const StickerCompareArgs({
    required this.originalImagePath,
    required this.stickerBytes,
    required this.stickerShape,
  });
}
