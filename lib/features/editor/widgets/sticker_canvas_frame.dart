import 'package:flutter/material.dart';

import '../../../core/constants/build_config.dart';
import '../../../core/models/sticker_shape.dart';

// ─── 共用：貼圖畫布外框 ──────────────────────────────────────────────────────
//
// 使用情境：
//   • 滑動選擇卡片（showShadow: true, showBoundary: false, onEditTap: callback）
//   • 編輯 Sheet 預覽區（showShadow: false, showBoundary: true）
//
// 修正問題：
//   原本 edit sheet 的 _CheckerboardPainter 畫在整個正方形上，
//   而 StickerCanvas 才套用 ClipOval/ClipRRect，導致棋盤格超出形狀邊界。
//   現在棋盤格與 child 都在同一個 clip 容器內，視覺範圍完全吻合。

/// 圓角半徑：card 模式與 edit sheet 模式統一使用相同數值。
const double kStickerFrameRadius = 20.0;

/// 貼圖預覽外框，統一管理：
///   - 棋盤格透明背景（形狀內裁切）
///   - 虛線邊界（僅 showBoundary）
///   - 陰影外框（僅 showShadow）
///   - 右上角編輯按鈕（onEditTap != null 時）
class StickerCanvasFrame extends StatelessWidget {
  final StickerShape stickerShape;
  final Widget child;

  /// 顯示棋盤格透明示意，預設跟隨 build config 的 kStickerBgChromaKey。
  final bool? showCheckerboard;

  /// Card 模式：顯示陰影外框（滑動選擇卡片用）。
  final bool showShadow;

  /// Edit 模式：顯示虛線邊界（編輯 Sheet 用）。
  final bool showBoundary;

  /// 顯示右上角編輯按鈕，null 表示不顯示。
  final VoidCallback? onEditTap;

  const StickerCanvasFrame({
    super.key,
    required this.stickerShape,
    required this.child,
    this.showCheckerboard,
    this.showShadow = false,
    this.showBoundary = false,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final useCheckerboard = showCheckerboard ?? kStickerBgChromaKey;

    // ── 步驟 1：棋盤格 + child 組合（共同受下方 clip 約束）──────────────
    Widget content = useCheckerboard
        ? Stack(children: [
            Positioned.fill(
              child: const CustomPaint(painter: CheckerboardPainter()),
            ),
            child,
          ])
        : child;

    // ── 步驟 2：依形狀裁切（確保棋盤格與 child 完全同範圍）──────────────
    if (showShadow) {
      // Card 模式：Container 的 clipBehavior 同時裁切棋盤格與 child
      content = Container(
        decoration: stickerShape == StickerShape.circle
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: _cardShadows,
              )
            : BoxDecoration(
                borderRadius: BorderRadius.circular(kStickerFrameRadius),
                boxShadow: _cardShadows,
              ),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    } else {
      // Edit 模式：明確 Clip（無陰影容器）
      content = stickerShape == StickerShape.circle
          ? ClipOval(child: content)
          : ClipRRect(
              borderRadius: BorderRadius.circular(kStickerFrameRadius),
              child: content,
            );
    }

    // ── 步驟 3：虛線邊界疊加在裁切後的內容上面（Edit 模式）────────────────
    if (showBoundary) {
      content = CustomPaint(
        foregroundPainter: StickerBoundaryPainter(stickerShape: stickerShape),
        child: content,
      );
    }

    // ── 步驟 4：整張卡片可點擊開啟編輯（Card 模式）─────────────────────────
    if (onEditTap != null) {
      return GestureDetector(
        onTap: onEditTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      );
    }

    return content;
  }

  static const List<BoxShadow> _cardShadows = [
    BoxShadow(
      color: Color(0x29000000), // 0.16 alpha
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x0F000000), // 0.06 alpha
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];
}

// ─── 棋盤格 Painter（透明背景示意，僅用於預覽，不進入 RepaintBoundary）────────

class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter();

  static const double _tileSize = 14.0;
  static const Color _light = Color(0xFFE8E8E8);
  static const Color _dark = Color(0xFFC8C8C8);

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = _light;
    final darkPaint = Paint()..color = _dark;
    final cols = (size.width / _tileSize).ceil() + 1;
    final rows = (size.height / _tileSize).ceil() + 1;
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(c * _tileSize, r * _tileSize, _tileSize, _tileSize),
          (r + c).isEven ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 虛線邊界 Painter（標示貼圖最大可編輯範圍）──────────────────────────────

class StickerBoundaryPainter extends CustomPainter {
  final StickerShape stickerShape;
  const StickerBoundaryPainter({required this.stickerShape});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBBBBBB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashLen = 5.0;
    const gapLen = 4.0;

    final path = stickerShape == StickerShape.circle
        ? (Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height)))
        : (Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width, size.height),
            const Radius.circular(kStickerFrameRadius),
          )));

    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final end = (dist + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(covariant StickerBoundaryPainter old) =>
      old.stickerShape != stickerShape;
}
