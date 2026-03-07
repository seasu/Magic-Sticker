import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  final String? tag;

  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.tag,
  });

  String get formattedTime {
    final t = time;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  String toExportLine() {
    final iso = time.toIso8601String();
    final tagStr = tag != null ? '[$tag] ' : '';
    return '[$iso][${level.name.toUpperCase()}] $tagStr$message';
  }
}

/// 輕量 in-app log 服務，記憶體內最多保留 500 筆。
/// 同時會呼叫 [debugPrint] 在 console 輸出。
class LogService {
  LogService._();

  static final instance = LogService._();

  static const _maxEntries = 500;
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void info(String message, {String? tag}) =>
      _add(LogLevel.info, message, tag: tag);

  void warning(String message, {String? tag}) =>
      _add(LogLevel.warning, message, tag: tag);

  void error(String message, {String? tag}) =>
      _add(LogLevel.error, message, tag: tag);

  void _add(LogLevel level, String message, {String? tag}) {
    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
    );
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    debugPrint('[${level.name.toUpperCase()}]${tag != null ? "[$tag]" : ""} $message');
  }

  void clear() => _entries.clear();

  /// 匯出所有 log 為純文字（可貼給 Claude 分析）
  String exportAll() => _entries.map((e) => e.toExportLine()).join('\n');
}
