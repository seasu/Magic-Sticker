import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/log_service.dart';

class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  LogLevel? _filter; // null = 全部顯示
  final _scrollCtrl = ScrollController();

  List<LogEntry> get _filtered {
    final all = LogService.instance.entries;
    if (_filter == null) return all;
    return all.where((e) => e.level == _filter).toList();
  }

  void _copyAll() {
    final text = LogService.instance.exportAll();
    if (text.isEmpty) {
      _showSnack('目前沒有 log');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('已複製 ${LogService.instance.entries.length} 筆 log ✓');
  }

  void _clearAll() {
    LogService.instance.clear();
    setState(() {});
    _showSnack('Log 已清除');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Log'),
        actions: [
          // 捲到底部
          IconButton(
            icon: const Icon(Icons.vertical_align_bottom_rounded),
            tooltip: '捲到最新',
            onPressed: _scrollToBottom,
          ),
          // 複製全部
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: '複製全部 log',
            onPressed: _copyAll,
          ),
          // 清除
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '清除 log',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('清除 Log'),
                content: const Text('確定要清除所有 log 嗎？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _clearAll();
                    },
                    child: const Text('清除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ),
          // 重新整理
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新整理',
            onPressed: () => setState(() {}),
          ),
        ],
      ),

      body: Column(
        children: [
          // ── 篩選列 ─────────────────────────────────────────────────────────
          _FilterBar(
            current: _filter,
            onChanged: (level) => setState(() => _filter = level),
          ),

          // ── Log 計數 ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text(
                  '共 ${entries.length} 筆',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  '（最多保留 500 筆）',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Log 列表 ───────────────────────────────────────────────────────
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('目前沒有 log'))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _LogTile(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 篩選列 ─────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final LogLevel? current;
  final ValueChanged<LogLevel?> onChanged;

  const _FilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _Chip(label: '全部', selected: current == null, onTap: () => onChanged(null)),
          const SizedBox(width: 8),
          _Chip(
            label: 'INFO',
            selected: current == LogLevel.info,
            color: Colors.blue,
            onTap: () => onChanged(LogLevel.info),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'WARNING',
            selected: current == LogLevel.warning,
            color: Colors.orange,
            onTap: () => onChanged(LogLevel.warning),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'ERROR',
            selected: current == LogLevel.error,
            color: Colors.red,
            onTap: () => onChanged(LogLevel.error),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? effectiveColor : effectiveColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : effectiveColor,
          ),
        ),
      ),
    );
  }
}

// ── 單筆 Log 項目 ───────────────────────────────────────────────────────────

class _LogTile extends StatelessWidget {
  final LogEntry entry;

  const _LogTile({required this.entry});

  Color _levelColor(BuildContext context) => switch (entry.level) {
    LogLevel.info    => Colors.blue,
    LogLevel.warning => Colors.orange,
    LogLevel.error   => Colors.red,
  };

  IconData _levelIcon() => switch (entry.level) {
    LogLevel.info    => Icons.info_outline_rounded,
    LogLevel.warning => Icons.warning_amber_rounded,
    LogLevel.error   => Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(context);

    return InkWell(
      // 長按複製單筆
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.toExportLine()));
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('已複製此筆 log'),
              duration: Duration(seconds: 1),
            ),
          );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level icon
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(_levelIcon(), size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 時間 + tag
                  Row(
                    children: [
                      Text(
                        entry.formattedTime,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.outline,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (entry.tag != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.tag!,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // 訊息內容
                  Text(
                    entry.message,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
