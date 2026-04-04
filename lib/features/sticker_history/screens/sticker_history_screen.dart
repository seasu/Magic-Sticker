import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/sticker_style.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/sticker_record.dart';
import '../providers/sticker_history_provider.dart';
import '../services/sticker_archive_service.dart';

// 歷史紀錄頁背景 — 比純白更有層次感的淺灰
const _kPageBg = Color(0xFFF2F2F7);

class StickerHistoryScreen extends ConsumerWidget {
  const StickerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(stickerHistoryProvider);

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: AppBar(
        title: Text(
          '生成紀錄',
          style: TextStyle(
            fontFamily: 'OpenHuninn',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: _kPageBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            '載入失敗，請稍後再試',
            style: TextStyle(
              fontFamily: 'OpenHuninn',
              color: AppColors.textSecondary,
            ),
          ),
        ),
        data: (records) {
          if (records.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 64,
                    color: AppColors.divider,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '還沒有生成過任何貼圖',
                    style: TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '消耗點數生成貼圖後，圖片將自動存檔於此',
                    style: TextStyle(
                      fontFamily: 'OpenHuninn',
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(stickerHistoryProvider.future),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,  // 為底部資訊列保留空間
              ),
              itemCount: records.length,
              itemBuilder: (_, i) => _StickerCard(
                record: records[i],
                onDeleted: () => ref.invalidate(stickerHistoryProvider),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StickerCard extends StatelessWidget {
  final StickerRecord record;
  final VoidCallback onDeleted;

  const _StickerCard({required this.record, required this.onDeleted});

  String _formatDate(DateTime dt) {
    final mm  = dt.month.toString().padLeft(2, '0');
    final dd  = dt.day.toString().padLeft(2, '0');
    final hh  = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$min';
  }

  String _styleName(int index) {
    if (index < 0 || index >= StickerStyle.values.length) return '';
    return StickerStyle.values[index].label;
  }

  Future<void> _saveToGallery(BuildContext context) async {
    try {
      await StickerArchiveService.instance.saveToGallery(record);
      FirebaseService.log('StickerHistory: saved ${record.id} to gallery');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已儲存至相簿',
            style: TextStyle(fontFamily: 'OpenHuninn'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, s) {
      await FirebaseService.recordError(e, s,
          reason: 'sticker_history_save_failed');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '儲存失敗，請稍後再試',
            style: TextStyle(fontFamily: 'OpenHuninn'),
          ),
          backgroundColor: AppColors.nope,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          '刪除紀錄',
          style: TextStyle(
            fontFamily: 'OpenHuninn',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '確定要刪除這張貼圖的存檔嗎？此操作無法還原。',
          style: TextStyle(fontFamily: 'OpenHuninn'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(fontFamily: 'OpenHuninn')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '刪除',
              style: TextStyle(
                fontFamily: 'OpenHuninn',
                color: AppColors.nope,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await StickerArchiveService.instance.delete(record.id);
    onDeleted();
  }

  void _openReplay(BuildContext context) {
    context.push('/sticker-replay', extra: record);
  }

  @override
  Widget build(BuildContext context) {
    final isCircle = record.shapeStr == 'circle';
    final file = File(record.filePath);
    final styleName = record.customStyleDesc != null && record.customStyleDesc!.isNotEmpty
        ? '✨ ${record.customStyleDesc}'
        : _styleName(record.styleIndex);
    final emotionLine = record.customEmotionDesc != null && record.customEmotionDesc!.isNotEmpty
        ? record.customEmotionDesc!
        : null;
    final hasPersonDetect = record.enhancePersonFeatures;

    return GestureDetector(
      onTap: () => _openReplay(context),
      onLongPress: () => _confirmDelete(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── 圖片區 ────────────────────────────────────────────────────
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: file.existsSync()
                    ? (isCircle
                        // 圓形貼圖：留白邊距讓圓形「浮」在白卡上
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                            child: ClipOval(
                              child: Image.file(file, fit: BoxFit.cover),
                            ),
                          )
                        // 方形貼圖：填滿圖片區
                        : Image.file(file, fit: BoxFit.cover))
                    : const ColoredBox(
                        color: AppColors.surface,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.divider,
                          size: 40,
                        ),
                      ),
              ),
            ),

            // ── 資訊列（圖片外，不再遮蓋貼圖）────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 4, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (styleName.isNotEmpty)
                          Text(
                            styleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'OpenHuninn',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF555555),
                            ),
                          ),
                        if (emotionLine != null || hasPersonDetect)
                          Row(
                            children: [
                              if (emotionLine != null)
                                Flexible(
                                  child: Text(
                                    '🎭 $emotionLine',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'OpenHuninn',
                                      fontSize: 10,
                                      color: Color(0xFF888888),
                                    ),
                                  ),
                                ),
                              if (hasPersonDetect)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Text(
                                    '👁',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                            ],
                          ),
                        Text(
                          _formatDate(record.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'OpenHuninn',
                            fontSize: 10,
                            color: Color(0xFFAAAAAA),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 下載按鈕
                  GestureDetector(
                    onTap: () => _saveToGallery(context),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.download_rounded,
                        color: Color(0xFFCCCCCC),
                        size: 18,
                      ),
                    ),
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
