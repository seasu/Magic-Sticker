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
  /// 演算法（Flood Fill from corners）：
  /// 1. 從圖片四角出發，BFS 擴散所有連通的「近黑色」像素
  /// 2. 近黑色門檻：R < 50 && G < 50 && B < 50
  /// 3. 被標記的背景像素 alpha → 0（透明）
  /// 4. 未被標記的像素（角色 + 白色描邊）維持原色
  ///
  /// 設計上依賴 prompt 要求的白色描邊，white border 會擋住 flood fill
  /// 從邊界進入角色內部，即使角色有黑色線條也不會誤刪。
  ///
  /// 可傳入 `compute()` 作為 isolate 頂層函數使用。
  static Uint8List? chromaKeyRemoveBlackIsolate(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    final w = image.width;
    final h = image.height;

    // 轉為可修改的 RGBA Image
    final result = img.Image(width: w, height: h, numChannels: 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        result.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
      }
    }

    // BFS flood fill：從四角出發，標記所有連通的近黑色背景像素
    const _kBlackThreshold = 50;
    final visited = List.filled(w * h, false);
    final queue = Queue<int>();

    void enqueue(int x, int y) {
      final idx = y * w + x;
      if (visited[idx]) return;
      final p = result.getPixel(x, y);
      if (p.r < _kBlackThreshold && p.g < _kBlackThreshold && p.b < _kBlackThreshold) {
        visited[idx] = true;
        queue.add(idx);
      }
    }

    // 四角出發點
    enqueue(0, 0);
    enqueue(w - 1, 0);
    enqueue(0, h - 1);
    enqueue(w - 1, h - 1);

    // 四邊邊緣出發點（確保完整覆蓋邊界黑色）
    for (int x = 0; x < w; x++) {
      enqueue(x, 0);
      enqueue(x, h - 1);
    }
    for (int y = 0; y < h; y++) {
      enqueue(0, y);
      enqueue(w - 1, y);
    }

    // 4-連通 BFS
    const dx = [1, -1, 0, 0];
    const dy = [0, 0, 1, -1];
    while (queue.isNotEmpty) {
      final idx = queue.removeFirst();
      final px = idx % w;
      final py = idx ~/ w;
      for (int d = 0; d < 4; d++) {
        final nx = px + dx[d];
        final ny = py + dy[d];
        if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
        enqueue(nx, ny);
      }
    }

    // 將標記的背景像素設為透明
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (visited[y * w + x]) {
          result.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(result));
  }
}
