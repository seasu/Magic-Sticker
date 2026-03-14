import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/sticker_style.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/sticker_record.dart';
import '../providers/sticker_history_provider.dart';
import '../services/sticker_archive_service.dart';

class StickerHistoryScreen extends ConsumerWidget {
  const StickerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(stickerHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '生成紀錄',
          style: GoogleFonts.notoSansTc(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Text(
            '載入失敗，請稍後再試',
            style: GoogleFonts.notoSansTc(color: AppColors.textSecondary),
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
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '消耗點數生成貼圖後，圖片將自動存檔於此',
                    style: GoogleFonts.notoSansTc(
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
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1,
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
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
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
            style: GoogleFonts.notoSansTc(),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, s) {
      await FirebaseService.recordError(e, s, reason: 'sticker_history_save_failed');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '儲存失敗，請稍後再試',
            style: GoogleFonts.notoSansTc(),
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
        title: Text('刪除紀錄', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
        content: Text(
          '確定要刪除這張貼圖的存檔嗎？此操作無法還原。',
          style: GoogleFonts.notoSansTc(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: GoogleFonts.notoSansTc()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              '刪除',
              style: GoogleFonts.notoSansTc(color: AppColors.nope),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await StickerArchiveService.instance.delete(record.id);
    onDeleted();
  }

  @override
  Widget build(BuildContext context) {
    final isCircle = record.shapeStr == 'circle';
    final file = File(record.filePath);

    return GestureDetector(
      onLongPress: () => _confirmDelete(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isCircle ? 200 : 16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 貼圖圖片
            file.existsSync()
                ? Image.file(file, fit: BoxFit.cover)
                : Container(
                    color: AppColors.surface,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.divider,
                      size: 40,
                    ),
                  ),

            // 底部半透明資訊條
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 4, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            record.stickerText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '${_styleName(record.styleIndex)} · ${_formatDate(record.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 儲存至相簿按鈕
                    GestureDetector(
                      onTap: () => _saveToGallery(context),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
