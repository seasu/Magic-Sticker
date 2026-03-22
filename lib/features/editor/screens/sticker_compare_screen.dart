import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/sticker_shape.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/sticker_canvas_frame.dart';

/// 儲存貼圖成功後顯示的全螢幕上下比對頁。
/// 上半：原圖；下半：貼圖（棋盤格背景）。
/// 分隔把手可垂直拖動調整比例。
class StickerCompareScreen extends StatefulWidget {
  final String originalImagePath;
  final Uint8List stickerBytes;
  final StickerShape stickerShape;

  const StickerCompareScreen({
    super.key,
    required this.originalImagePath,
    required this.stickerBytes,
    required this.stickerShape,
  });

  @override
  State<StickerCompareScreen> createState() => _StickerCompareScreenState();
}

class _StickerCompareScreenState extends State<StickerCompareScreen> {
  double _splitFraction = 0.5;
  bool _isSharing = false;
  final _repaintKey = GlobalKey();

  Future<void> _share() async {
    setState(() => _isSharing = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final tmp = File(
        '${(await getTemporaryDirectory()).path}'
        '/compare_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tmp.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(tmp.path)],
        text: '我用 Magic Sticker 做的貼圖 ✨',
      );
      await tmp.delete();
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          '貼圖 vs 原圖',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 比對區（RepaintBoundary 截圖範圍）─────────────────────────
            Expanded(
              child: RepaintBoundary(
                key: _repaintKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalHeight = constraints.maxHeight;
                    final topHeight =
                        (totalHeight * _splitFraction).clamp(80.0, totalHeight - 80.0);
                    final bottomHeight = totalHeight - topHeight - _kDividerHeight;

                    return Column(
                      children: [
                        // ── 上半：原圖 ────────────────────────────────────
                        SizedBox(
                          height: topHeight,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(widget.originalImagePath),
                                fit: BoxFit.cover,
                              ),
                              // 「原圖」chip
                              const Positioned(
                                top: 10,
                                left: 14,
                                child: _Chip(label: '原圖'),
                              ),
                            ],
                          ),
                        ),

                        // ── 分隔把手 ─────────────────────────────────────
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (d) {
                            setState(() {
                              _splitFraction = (_splitFraction +
                                      d.delta.dy / totalHeight)
                                  .clamp(0.2, 0.8);
                            });
                          },
                          child: SizedBox(
                            height: _kDividerHeight,
                            child: ColoredBox(
                              color: Colors.black,
                              child: Center(
                                child: Container(
                                  width: 48,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ── 下半：貼圖 ────────────────────────────────────
                        SizedBox(
                          height: bottomHeight,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 棋盤格背景
                              const CustomPaint(painter: CheckerboardPainter()),
                              // 貼圖（依形狀裁切）
                              widget.stickerShape == StickerShape.circle
                                  ? ClipOval(
                                      child: Image.memory(
                                        widget.stickerBytes,
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : Image.memory(
                                      widget.stickerBytes,
                                      fit: BoxFit.contain,
                                    ),
                              // 「貼圖」chip
                              const Positioned(
                                top: 10,
                                left: 14,
                                child: _Chip(label: '貼圖'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // ── 底部按鈕列 ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  // 分享按鈕
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isSharing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('分享比對圖'),
                      onPressed: _isSharing ? null : _share,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 完成按鈕
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.gradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => context.pop(),
                        child: const Text(
                          '完成',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
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

const double _kDividerHeight = 28.0;

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
