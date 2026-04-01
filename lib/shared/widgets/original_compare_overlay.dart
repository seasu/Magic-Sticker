import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_urls.dart';
import '../../core/models/sticker_shape.dart';
import '../../core/theme/app_colors.dart';

/// 比對原圖 Overlay。
///
/// 放置於貼圖卡片的 Stack 中，提供：
/// - 右上角 toggle 按鈕（免費，無 Pro 門控）
/// - Instagram 風格滑動分割線比對
/// - 雙側獨立 pinch-to-zoom + pan（雙擊重置）
/// - 同步縮放 toggle
/// - 一鍵分享比對圖
///
/// 當 [originalImagePath] 或 [stickerBytes] 為 null 時，整個元件隱藏。
class OriginalCompareOverlay extends StatefulWidget {
  final String? originalImagePath;
  final Uint8List? stickerBytes;
  final StickerShape shape;

  const OriginalCompareOverlay({
    super.key,
    required this.originalImagePath,
    required this.stickerBytes,
    required this.shape,
  });

  @override
  State<OriginalCompareOverlay> createState() => _OriginalCompareOverlayState();
}

class _OriginalCompareOverlayState extends State<OriginalCompareOverlay> {
  bool _isComparing = false;
  double _dividerFraction = 0.5;

  // 左側（原圖）縮放狀態
  double _leftScale = 1.0;
  Offset _leftOffset = Offset.zero;
  double _leftBaseScale = 1.0;
  Offset _leftBaseOffset = Offset.zero;

  // 右側（貼圖）縮放狀態
  double _rightScale = 1.0;
  Offset _rightOffset = Offset.zero;
  double _rightBaseScale = 1.0;
  Offset _rightBaseOffset = Offset.zero;

  bool _syncZoom = false;
  bool _isSharing = false;
  bool _showHint = false;
  Timer? _hintTimer;

  static const _hintPrefKey = 'compare_hint_shown';

  final _compareRepaintKey = GlobalKey();
  final _shareButtonKey = GlobalKey();

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  bool get _available =>
      widget.originalImagePath != null && widget.stickerBytes != null;

  void _toggleCompare() {
    HapticFeedback.selectionClick();
    setState(() => _isComparing = !_isComparing);
    if (_isComparing) _maybeShowHint();
  }

  Future<void> _maybeShowHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_hintPrefKey) == true) return;
    await prefs.setBool(_hintPrefKey, true);
    if (!mounted) return;
    setState(() => _showHint = true);
    _hintTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  void _resetLeft() {
    setState(() {
      _leftScale = 1.0;
      _leftOffset = Offset.zero;
    });
  }

  void _resetRight() {
    setState(() {
      _rightScale = 1.0;
      _rightOffset = Offset.zero;
    });
  }

  void _onLeftScaleStart(ScaleStartDetails d) {
    _leftBaseScale = _leftScale;
    _leftBaseOffset = _leftOffset;
  }

  void _onLeftScaleUpdate(ScaleUpdateDetails d) {
    final newScale = (_leftBaseScale * d.scale).clamp(0.5, 4.0);
    final newOffset = _leftBaseOffset + d.focalPointDelta;
    setState(() {
      _leftScale = newScale;
      _leftOffset = newOffset;
      if (_syncZoom) {
        _rightScale = newScale;
        _rightOffset = newOffset;
      }
    });
  }

  void _onRightScaleStart(ScaleStartDetails d) {
    _rightBaseScale = _rightScale;
    _rightBaseOffset = _rightOffset;
  }

  void _onRightScaleUpdate(ScaleUpdateDetails d) {
    final newScale = (_rightBaseScale * d.scale).clamp(0.5, 4.0);
    final newOffset = _rightBaseOffset + d.focalPointDelta;
    setState(() {
      _rightScale = newScale;
      _rightOffset = newOffset;
      if (_syncZoom) {
        _leftScale = newScale;
        _leftOffset = newOffset;
      }
    });
  }

  Future<void> _shareCompare() async {
    setState(() => _isSharing = true);
    try {
      final boundary = _compareRepaintKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File(
          '${tmpDir.path}/compare_${DateTime.now().millisecondsSinceEpoch}.png');
      await tmpFile.writeAsBytes(bytes);
      // 自動複製下載連結到剪貼簿（LINE 分享圖片時文字會被忽略，剪貼簿為補充）
      await Clipboard.setData(
        const ClipboardData(text: AppUrls.download),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('連結已複製，分享到 LINE 後貼上即可 ✨'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromLTWH(0, 0, 1, 1);
      await Share.shareXFiles(
        [XFile(tmpFile.path)],
        text: '用 Magic Sticker AI 生成的貼圖 ✨',
        sharePositionOrigin: origin,
      );
      await tmpFile.delete();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_isComparing) _buildCompareView(),
        // 右上角按鈕組（浮動於卡片外側）
        Positioned(
          top: -8,
          right: -8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isComparing) ...[
                _buildShareButton(),
                const SizedBox(width: 6),
              ],
              _buildToggleButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompareView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final divX = w * _dividerFraction;

        // 核心比對畫面（含 RepaintBoundary 供截圖分享）
        Widget content = RepaintBoundary(
          key: _compareRepaintKey,
          child: Stack(
            children: [
              // 左側：原圖
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: _dividerFraction,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Transform(
                      transform: Matrix4.identity()
                        // ignore: deprecated_member_use — CI Flutter 3.29 無 translateByDouble
                        ..translate(_leftOffset.dx, _leftOffset.dy)
                        // ignore: deprecated_member_use — CI Flutter 3.29 無 scaleByDouble
                        ..scale(_leftScale),
                      alignment: Alignment.center,
                      child: Image.file(
                        File(widget.originalImagePath!),
                        fit: BoxFit.cover,
                        width: w,
                        height: h,
                      ),
                    ),
                  ),
                ),
              ),
              // 右側：貼圖
              ClipRect(
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1 - _dividerFraction,
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Transform(
                      transform: Matrix4.identity()
                        // ignore: deprecated_member_use — CI Flutter 3.29 無 translateByDouble
                        ..translate(_rightOffset.dx, _rightOffset.dy)
                        // ignore: deprecated_member_use — CI Flutter 3.29 無 scaleByDouble
                        ..scale(_rightScale),
                      alignment: Alignment.center,
                      child: Image.memory(
                        widget.stickerBytes!,
                        fit: BoxFit.cover,
                        width: w,
                        height: h,
                      ),
                    ),
                  ),
                ),
              ),
              // 「原圖」標籤
              Positioned(
                top: 10,
                left: 8,
                child: _buildLabel('原圖', divX > 60),
              ),
              // 「貼圖」標籤
              Positioned(
                top: 10,
                right: 8,
                child: _buildLabel('貼圖', (w - divX) > 60),
              ),
              // 分割線
              Positioned(
                left: divX - 1,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: Colors.white,
                  // 用陰影提升可見度
                ),
              ),
              // 分割線陰影（獨立層避免模糊污染圖片）
              Positioned(
                left: divX - 2,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 4,
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // 把手（可拖動）
              Positioned(
                left: divX - 16,
                top: h / 2 - 16,
                child: GestureDetector(
                  onHorizontalDragUpdate: (d) => setState(() {
                    _dividerFraction =
                        ((_dividerFraction * w + d.delta.dx) / w)
                            .clamp(0.1, 0.9);
                  }),
                  child: _buildDividerHandle(),
                ),
              ),
              // 同步縮放 toggle（把手下方）
              Positioned(
                left: (divX - 42).clamp(8.0, w - 90),
                bottom: 12,
                child: _buildSyncToggle(),
              ),
              // 首次使用提示
              if (_showHint)
                Positioned(
                  bottom: 52,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildHint()),
                ),
            ],
          ),
        );

        // 依貼圖形狀裁切
        if (widget.shape == StickerShape.circle) {
          content = ClipOval(child: content);
        } else {
          content =
              ClipRRect(borderRadius: BorderRadius.circular(16), child: content);
        }

        // 手勢偵測區（分左右，覆蓋在視覺層上方）
        return Stack(
          children: [
            content,
            // 左側手勢區
            Positioned(
              left: 0,
              top: 0,
              width: divX,
              height: h,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: _onLeftScaleStart,
                onScaleUpdate: _onLeftScaleUpdate,
                onDoubleTap: _resetLeft,
              ),
            ),
            // 右側手勢區
            Positioned(
              left: divX,
              top: 0,
              width: w - divX,
              height: h,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: _onRightScaleStart,
                onScaleUpdate: _onRightScaleUpdate,
                onDoubleTap: _resetRight,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLabel(String text, bool visible) => AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.50),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      );

  Widget _buildDividerHandle() => Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x42000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.swap_horiz_rounded,
          color: Color(0xFFFF5864),
          size: 18,
        ),
      );

  Widget _buildSyncToggle() => GestureDetector(
        onTap: () => setState(() => _syncZoom = !_syncZoom),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            gradient: _syncZoom ? AppColors.gradient : null,
            color: _syncZoom
                ? null
                : Colors.black.withValues(alpha: 0.40),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _syncZoom
                    ? Icons.link_rounded
                    : Icons.link_off_rounded,
                color: Colors.white,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                _syncZoom ? '同步縮放' : '分開縮放',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildHint() => AnimatedOpacity(
        opacity: _showHint ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 400),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            '拖動分割線比對 · 捏合可個別放大',
            style: TextStyle(fontSize: 13, color: Colors.white),
          ),
        ),
      );

  Widget _buildToggleButton() => GestureDetector(
        onTap: _toggleCompare,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _isComparing ? null : Colors.white,
            gradient: _isComparing ? AppColors.gradient : null,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _isComparing
                    ? const Color(0xFFFF5864).withValues(alpha: 0.35)
                    : Colors.black12,
                blurRadius: _isComparing ? 10 : 8,
                offset:
                    _isComparing ? const Offset(0, 3) : Offset.zero,
              ),
            ],
          ),
          child: _isComparing
              ? const Icon(
                  Icons.compare_rounded,
                  size: 20,
                  color: Colors.white,
                )
              : ShaderMask(
                  shaderCallback: (b) =>
                      AppColors.gradient.createShader(b),
                  child: const Icon(
                    Icons.compare_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
        ),
      );

  Widget _buildShareButton() => GestureDetector(
        key: _shareButtonKey,
        onTap: _isSharing ? null : _shareCompare,
        child: Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 8),
            ],
          ),
          child: _isSharing
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF5864),
                    ),
                  ),
                )
              : ShaderMask(
                  shaderCallback: (b) =>
                      AppColors.gradient.createShader(b),
                  child: const Icon(
                    Icons.ios_share_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
        ),
      );
}
