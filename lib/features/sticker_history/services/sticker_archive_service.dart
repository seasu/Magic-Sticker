import 'dart:convert';
import 'dart:io';

import 'package:gal/gal.dart';
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

  /// 將 AI 生成的 PNG bytes 存入本地檔案系統，並更新 SharedPreferences 元資料。
  /// 靜默執行，呼叫端應以 fire-and-forget 方式使用。
  Future<StickerRecord?> archive({
    required List<int> pngBytes,
    required String stickerText,
    required int styleIndex,
    required StickerShape shape,
  }) async {
    final dir = await _archiveDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final id = '${ts}_$styleIndex';
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(pngBytes);

    final record = StickerRecord(
      id: id,
      filePath: file.path,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ts),
      stickerText: stickerText,
      styleIndex: styleIndex,
      shapeStr: shape.name,
    );

    final prefs = await SharedPreferences.getInstance();
    final existing = _decodeList(prefs.getStringList(_prefKey) ?? []);
    existing.insert(0, record);

    // 超過上限時刪除最舊的紀錄
    if (existing.length > _maxRecords) {
      final toRemove = existing.sublist(_maxRecords);
      for (final old in toRemove) {
        final oldFile = File(old.filePath);
        if (oldFile.existsSync()) await oldFile.delete();
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

  /// 刪除單筆紀錄（刪除本地 PNG 檔 + 更新 metadata）。
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _decodeList(prefs.getStringList(_prefKey) ?? []);
    final target = records.where((r) => r.id == id).toList();
    for (final r in target) {
      final file = File(r.filePath);
      if (file.existsSync()) await file.delete();
    }
    records.removeWhere((r) => r.id == id);
    await prefs.setStringList(_prefKey, _encodeList(records));
  }

  /// 將存檔圖片重新儲存至裝置相簿。
  Future<void> saveToGallery(StickerRecord record) async {
    await Gal.putImage(record.filePath);
  }

  // ── Private ─────────────────────────────────────────────────────────────────

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
