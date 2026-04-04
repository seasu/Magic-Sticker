import 'dart:convert';
import 'dart:io';

import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/sticker_shape.dart';
import '../models/sticker_record.dart';

class StickerArchiveService {
  StickerArchiveService._();
  static final instance = StickerArchiveService._();

  static const _prefKey = 'sticker_archive_records';
  static const _maxRecords = 200;
  static const _dirName = 'sticker_archives';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// 將貼圖 PNG bytes 存入本地，並更新 SharedPreferences 元資料。
  /// [originalImagePath] 若提供，會額外儲存 300px 縮圖用於比對原圖功能。
  /// [rawAiBytes] 若提供，會額外儲存 AI 去背原圖（供再次編輯使用）。
  Future<StickerRecord?> archive({
    required List<int> pngBytes,
    required String stickerText,
    required int styleIndex,
    required StickerShape shape,
    String? originalImagePath,
    List<int>? rawAiBytes,
    String? customStyleDesc,
    String? customEmotionDesc,
    bool enhancePersonFeatures = false,
  }) async {
    final dir = await _archiveDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final id = '${ts}_$styleIndex';
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(pngBytes);

    // 存原圖縮圖（300px JPEG，供比對原圖功能使用）
    String? thumbnailPath;
    if (originalImagePath != null) {
      try {
        final origBytes = await File(originalImagePath).readAsBytes();
        final decoded = img.decodeImage(origBytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: 300);
          final jpegBytes = img.encodeJpg(resized, quality: 75);
          final thumbFile = File('${dir.path}/${id}_orig.jpg');
          await thumbFile.writeAsBytes(jpegBytes);
          thumbnailPath = thumbFile.path;
        }
      } catch (_) {
        // 縮圖失敗不影響主流程
      }
    }

    // 存 AI 去背原圖（PNG，供再次編輯時作為底圖）
    String? rawAiPath;
    if (rawAiBytes != null) {
      try {
        final rawFile = File('${dir.path}/${id}_ai.png');
        await rawFile.writeAsBytes(rawAiBytes);
        rawAiPath = rawFile.path;
      } catch (_) {
        // 失敗不影響主流程
      }
    }

    final record = StickerRecord(
      id: id,
      filePath: file.path,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
      stickerText: stickerText,
      styleIndex: styleIndex,
      shapeStr: shape.name,
      originalThumbnailPath: thumbnailPath,
      rawAiImagePath: rawAiPath,
      customStyleDesc: customStyleDesc,
      customEmotionDesc: customEmotionDesc,
      enhancePersonFeatures: enhancePersonFeatures,
    );

    final prefs = await SharedPreferences.getInstance();
    final existing = _decodeList(prefs.getStringList(_prefKey) ?? []);
    existing.insert(0, record);

    // 超過上限時刪除最舊的紀錄
    if (existing.length > _maxRecords) {
      final toRemove = existing.sublist(_maxRecords);
      for (final old in toRemove) {
        _deleteRecordFiles(old);
      }
      existing.removeRange(_maxRecords, existing.length);
    }

    await prefs.setStringList(_prefKey, _encodeList(existing));
    return record;
  }

  /// 讀取全部紀錄（降冪排列），過濾掉已刪除的檔案。
  Future<List<StickerRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final records = _decodeList(prefs.getStringList(_prefKey) ?? []);

    // 過濾掉本地檔案已遺失的紀錄（例如清除 App 資料後）
    final valid = records.where((r) => File(r.filePath).existsSync()).toList();

    // 若有孤立紀錄，同步更新 SharedPreferences
    if (valid.length != records.length) {
      await prefs.setStringList(_prefKey, _encodeList(valid));
    }

    return valid;
  }

  /// 刪除單筆紀錄（刪除本地 PNG 檔、縮圖 + 更新 metadata）。
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _decodeList(prefs.getStringList(_prefKey) ?? []);
    final target = records.where((r) => r.id == id).toList();
    for (final r in target) {
      _deleteRecordFiles(r);
    }
    records.removeWhere((r) => r.id == id);
    await prefs.setStringList(_prefKey, _encodeList(records));
  }

  /// 刪除全部生成紀錄（本地檔案 + SharedPreferences）。
  /// 用於帳號刪除時清除本機資料。
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final records = _decodeList(prefs.getStringList(_prefKey) ?? []);
    for (final r in records) {
      _deleteRecordFiles(r);
    }
    await prefs.remove(_prefKey);
    // 刪除整個目錄（清除殘留檔案）
    final dir = await _archiveDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  /// 將存檔圖片重新儲存至裝置相簿。
  Future<void> saveToGallery(StickerRecord record) async {
    await Gal.putImage(record.filePath);
  }

  // ── Private ─────────────────────────────────────────────────────────────────

  void _deleteRecordFiles(StickerRecord record) {
    final stickerFile = File(record.filePath);
    if (stickerFile.existsSync()) stickerFile.deleteSync();
    if (record.originalThumbnailPath != null) {
      final thumbFile = File(record.originalThumbnailPath!);
      if (thumbFile.existsSync()) thumbFile.deleteSync();
    }
    if (record.rawAiImagePath != null) {
      final rawFile = File(record.rawAiImagePath!);
      if (rawFile.existsSync()) rawFile.deleteSync();
    }
  }

  Future<Directory> _archiveDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  List<StickerRecord> _decodeList(List<String> raw) => raw
      .map((s) {
        try {
          return StickerRecord.fromJson(
            jsonDecode(s) as Map<String, dynamic>,
          );
        } catch (_) {
          return null;
        }
      })
      .whereType<StickerRecord>()
      .toList();

  List<String> _encodeList(List<StickerRecord> records) =>
      records.map((r) => jsonEncode(r.toJson())).toList();
}
