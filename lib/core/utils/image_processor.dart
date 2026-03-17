import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../services/firebase_service.dart';

class ImageProcessor {
  static const int _maxDimension = 1080;

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

  /// Chroma Key 去背：將純黑色背景替換為透明，回傳 PNG bytes。
  ///
  /// 演算法（Flood Fill from edges）：
  /// 1. 從圖片四邊所有像素出發，BFS 擴散所有連通的「近黑色」像素（背景）
  /// 2. 近黑色門檻：max(R, G, B) < kBlackThreshold（85），處理 JPEG 壓縮 artifact
  /// 3. 被標記的背景像素 alpha → 0（透明）
  /// 4. 未被標記的像素（角色 + 白色描邊）維持原色
  ///
  /// 依賴 prompt 要求的白色描邊：白色描邊擋住 flood fill，
  /// 即使角色有黑色部分也不會被誤刪。
  ///
  /// 可傳入 `compute()` 作為 isolate 頂層函數使用。
  static Uint8List? chromaKeyRemoveBlackIsolate(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // 確保 RGBA uint8 格式，使 pixel 值在 0–255 範圍內
    final image = decoded.convert(numChannels: 4);
    final w = image.width;
    final h = image.height;

    // 門檻：85，可承受 JPEG 壓縮 artifact（純黑 #000 在 JPEG 解壓後最多 ~60）
    const kBlackThreshold = 85;

    // visited[idx] = 0 未訪問, 1 = 背景(black), 2 = 非背景
    final visited = Uint8List(w * h);
    final queue = Queue<int>();

    bool isBlackPixel(int x, int y) {
      final p = image.getPixel(x, y);
      // 取三通道最大值，任一通道 >= 門檻即非黑（處理色偏 artifact）
      final maxCh = p.r > p.g ? (p.r > p.b ? p.r : p.b) : (p.g > p.b ? p.g : p.b);
      return maxCh < kBlackThreshold;
    }

    void tryEnqueue(int x, int y) {
      if (x < 0 || x >= w || y < 0 || y >= h) return;
      final idx = y * w + x;
      if (visited[idx] != 0) return; // 已處理
      if (isBlackPixel(x, y)) {
        visited[idx] = 1; // 標記為背景
        queue.add(idx);
      } else {
        visited[idx] = 2; // 標記為非背景（阻止重複訪問）
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

    // Edge cleanup：多輪擴展透明區域，去除邊緣黑色 artifact 並修剪白色描邊
    // 每輪把「鄰近透明像素的黑色 or 白色描邊像素」設為透明
    const kEdgePasses = 4;
    for (int pass = 0; pass < kEdgePasses; pass++) {
      final candidates = <int>[];
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final idx = y * w + x;
          if (visited[idx] == 1) continue; // 已透明

          // 是否有相鄰透明像素（4-連通）
          final hasTransparentNeighbor =
              (x > 0     && visited[y * w + (x - 1)] == 1) ||
              (x < w - 1 && visited[y * w + (x + 1)] == 1) ||
              (y > 0     && visited[(y - 1) * w + x] == 1) ||
              (y < h - 1 && visited[(y + 1) * w + x] == 1);
          if (!hasTransparentNeighbor) continue;

          final p = image.getPixel(x, y);
          final maxCh = p.r > p.g ? (p.r > p.b ? p.r : p.b) : (p.g > p.b ? p.g : p.b);
          final minCh = p.r < p.g ? (p.r < p.b ? p.r : p.b) : (p.g < p.b ? p.g : p.b);
          // 黑色 artifact：max < 85
          // 白色描邊：min > 210（三通道均高，避免誤刪肌膚色）
          if (maxCh < kBlackThreshold || minCh > 210) {
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
