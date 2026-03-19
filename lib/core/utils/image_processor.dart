import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../services/firebase_service.dart';

class ImageProcessor {
  static const int _maxDimension = 768;

  /// 縮圖至最長邊不超過 1080px，回傳 JPEG bytes
  /// 必須在傳往原生層前呼叫，以防 OOM
  static Future<Uint8List> resizeForNative(File imageFile) async {
    FirebaseService.log('ImageProcessor.resizeForNative: start');
    final bytes = await imageFile.readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) throw Exception('無法解碼圖片');

    final needsResize =
        original.width > _maxDimension || original.height > _maxDimension;

    final processed = needsResize
        ? img.copyResize(
            original,
            width: original.width > original.height ? _maxDimension : -1,
            height: original.height >= original.width ? _maxDimension : -1,
          )
        : original;

    FirebaseService.log(
      'ImageProcessor.resizeForNative: done '
      '(${processed.width}x${processed.height})',
    );
    return Uint8List.fromList(img.encodeJpg(processed, quality: 90));
  }

  /// Chroma Key 去背（白幕模式）：將純白 #FFFFFF 背景替換為透明，回傳 PNG bytes。
  ///
  /// 演算法（Flood Fill from edges）：
  /// 1. 從圖片四邊所有像素出發，BFS 擴散所有連通的「近白色」像素（背景）
  /// 2. 白幕判斷：R > 220 且 G > 220 且 B > 220（處理 JPEG 壓縮色差）
  /// 3. 被標記的背景像素 alpha → 0（透明）
  /// 4. Edge cleanup：再擴展 2 輪，去除白幕 JPEG artifact 殘留
  ///
  /// 白幕優勢：去背失敗時殘留白邊遠比綠邊自然，不影響貼圖實際使用。
  /// 注意：flood fill 從邊緣出發，角色內部的白色高光、眼白等不會被誤刪。
  ///
  /// 可傳入 `compute()` 作為 isolate 頂層函數使用。
  static Uint8List? chromaKeyRemoveBlackIsolate(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // 確保 RGBA uint8 格式，使 pixel 值在 0–255 範圍內
    final image = decoded.convert(numChannels: 4);
    final w = image.width;
    final h = image.height;

    // visited[idx] = 0 未訪問, 1 = 背景(white), 2 = 非背景
    final visited = Uint8List(w * h);
    final queue = Queue<int>();

    // 白幕偵測：R、G、B 均高（近白色）
    // JPEG 壓縮後純白 #FFFFFF → R/G/B ≈ 245–255，門檻設 220 容許壓縮色差
    bool isWhitePixel(int x, int y) {
      final p = image.getPixel(x, y);
      return p.r > 220 && p.g > 220 && p.b > 220;
    }

    void tryEnqueue(int x, int y) {
      if (x < 0 || x >= w || y < 0 || y >= h) return;
      final idx = y * w + x;
      if (visited[idx] != 0) return;
      if (isWhitePixel(x, y)) {
        visited[idx] = 1;
        queue.add(idx);
      } else {
        visited[idx] = 2;
      }
    }

    // 從所有邊界像素出發
    for (int x = 0; x < w; x++) {
      tryEnqueue(x, 0);
      tryEnqueue(x, h - 1);
    }
    for (int y = 1; y < h - 1; y++) {
      tryEnqueue(0, y);
      tryEnqueue(w - 1, y);
    }

    // 4-連通 BFS
    while (queue.isNotEmpty) {
      final idx = queue.removeFirst();
      final x = idx % w;
      final y = idx ~/ w;
      tryEnqueue(x + 1, y);
      tryEnqueue(x - 1, y);
      tryEnqueue(x, y + 1);
      tryEnqueue(x, y - 1);
    }

    // Edge cleanup：擴展透明區域 2 輪，去除 JPEG 壓縮留下的白色 artifact
    // 白幕比綠幕更保守（2 輪而非 3 輪），避免誤刪角色邊緣的淺色元素
    const kEdgePasses = 2;
    for (int pass = 0; pass < kEdgePasses; pass++) {
      final candidates = <int>[];
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final idx = y * w + x;
          if (visited[idx] == 1) continue;

          final hasTransparentNeighbor =
              (x > 0     && visited[y * w + (x - 1)] == 1) ||
              (x < w - 1 && visited[y * w + (x + 1)] == 1) ||
              (y > 0     && visited[(y - 1) * w + x] == 1) ||
              (y < h - 1 && visited[(y + 1) * w + x] == 1);
          if (!hasTransparentNeighbor) continue;

          // 殘留白色 artifact（R/G/B 均偏高）
          final p = image.getPixel(x, y);
          if (p.r > 200 && p.g > 200 && p.b > 200) {
            candidates.add(idx);
          }
        }
      }
      if (candidates.isEmpty) break;
      for (final idx in candidates) {
        visited[idx] = 1;
      }
    }

    // 將標記為背景的像素設為透明
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (visited[y * w + x] == 1) {
          image.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(image));
  }
}
