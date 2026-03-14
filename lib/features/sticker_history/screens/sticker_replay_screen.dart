import 'dart:io';
import 'dart:math' show min;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/sticker_shape.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../editor/models/sticker_config.dart';
import '../../editor/widgets/sticker_canvas.dart';
import '../../editor/widgets/sticker_edit_sheet.dart';
import '../models/sticker_record.dart';

class StickerReplayScreen extends StatefulWidget {
  final StickerRecord record;

  const StickerReplayScreen({super.key, required this.record});

  @override
  State<StickerReplayScreen> createState() => _StickerReplayScreenState();
}

class _StickerReplayScreenState extends State<StickerReplayScreen> {
  final _repaintKey = GlobalKey();

  Uint8List? _imageBytes;
  bool _isExporting = false;

  // 可編輯的貼圖參數
  late String _text;
  late StickerShape _stickerShape;
  int _schemeIndex = 0;
  int _fontIndex = 0;
  int _styleIndex = 0;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _imageAngle = 0.0;
  double _fontSizeScale = 1.0;
  double _textXAlign = 0.0;
  double _textYAlign = 0.85;
  double _textAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _text = widget.record.stickerText;
    _styleIndex = widget.record.styleIndex;
    _stickerShape = widget.record.shapeStr == 'circle'
        ? StickerShape.circle
        : StickerShape.square;
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = File(widget.record.filePath);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    if (mounted) setState(() => _imageBytes = bytes);
  }

  void _openEditSheet() {
    if (_imageBytes == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StickerEditSheet(
        stickerIndex: 0,
        initialText: _text,
        initialSchemeIndex: _schemeIndex,
        initialScale: _scale,
        initialOffset: _offset,
        initialImageAngle: _imageAngle,
        initialFontIndex: _fontIndex,
        initialStyleIndex: _styleIndex,
        initialFontSizeScale: _fontSizeScale,
        initialTextXAlign: _textXAlign,
        initialTextYAlign: _textYAlign,
        initialTextAngle: _textAngle,
        generatedImage: _imageBytes,
        stickerShape: _stickerShape,
        onTextChanged: (t) => setState(() => _text = t),
        onSchemeChanged: (si) => setState(() => _schemeIndex = si),
        onTransformChanged: (s, o, a) => setState(() {
          _scale = s;
          _offset = o;
          _imageAngle = a;
        }),
        onFontChanged: (fi) => setState(() => _fontIndex = fi),
        onStyleChanged: (si) => setState(() => _styleIndex = si),
        onTextGestureChanged: (xAlign, yAlign, angle, sizeScale) =>
            setState(() {
          _textXAlign = xAlign;
          _textYAlign = yAlign;
          _textAngle = angle;
          _fontSizeScale = sizeScale;
        }),
      ),
    );
  }

  Future<void> _saveToGallery() async {
    if (_imageBytes == null || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      const double targetWidth = 370.0;
      final double pixelRatio = targetWidth / boundary.size.width;

      final rectImage = await boundary.toImage(pixelRatio: pixelRatio);
      final w = rectImage.width.toDouble();
      final h = rectImage.height.toDouble();

      final ui.Image exportImage;
      if (_stickerShape == StickerShape.circle) {
        final size = min(w, h);
        final left = (w - size) / 2;
        final top = (h - size) / 2;
        final recorder = ui.PictureRecorder();
        final exportCanvas = Canvas(recorder);
        exportCanvas.clipPath(
          Path()..addOval(Rect.fromLTWH(0, 0, size, size)),
        );
        exportCanvas.drawOval(
          Rect.fromLTWH(0, 0, size, size),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        exportCanvas.drawImage(rectImage, Offset(-left, -top), Paint());
        exportImage =
            await recorder.endRecording().toImage(size.toInt(), size.toInt());
      } else {
        exportImage = rectImage;
      }

      final byteData =
          await exportImage.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          throw GalException(
            type: GalExceptionType.accessDenied,
            error: PlatformException(
              code: 'ACCESS_DENIED',
              message: 'Storage access denied',
            ),
            stackTrace: StackTrace.current,
          );
        }
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/ms_replay_$ts.png');
      await tmpFile.writeAsBytes(bytes);
      await Gal.putImage(tmpFile.path);
      await tmpFile.delete();

      FirebaseService.log('StickerReplay: saved ${widget.record.id} to gallery');

      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('貼圖已儲存到相簿 ✨',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    } on GalException catch (e, stack) {
      await FirebaseService.recordError(e, stack,
          reason: 'replay_export_failed/gal_${e.type.name}');
      if (!mounted) return;
      setState(() => _isExporting = false);
      final msg = switch (e.type) {
        GalExceptionType.accessDenied => '請至設定開啟相簿存取權限',
        GalExceptionType.notEnoughSpace => '儲存空間不足，請清理後重試',
        _ => '儲存失敗，請重試',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack,
          reason: 'replay_export_failed');
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儲存失敗，請重試')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '編輯貼圖',
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
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // ── 貼圖畫布（正方形，可點擊編輯）────────────────────────────
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: _imageBytes == null
                        ? const Center(child: CircularProgressIndicator())
                        : RepaintBoundary(
                            key: _repaintKey,
                            child: StickerCanvas(
                              generatedImage: _imageBytes,
                              text: _text,
                              config: kStickerConfigs[
                                  _schemeIndex.clamp(0, kStickerConfigs.length - 1)],
                              stickerShape: _stickerShape,
                              initialScale: _scale,
                              initialOffset: _offset,
                              initialImageAngle: _imageAngle,
                              fontIndex: _fontIndex,
                              fontSizeScale: _fontSizeScale,
                              textXAlign: _textXAlign,
                              textYAlign: _textYAlign,
                              textAngle: _textAngle,
                              styleIndex: _styleIndex,
                              onTap: _openEditSheet,
                              onTransformChanged: (s, o, a) => setState(() {
                                _scale = s;
                                _offset = o;
                                _imageAngle = a;
                              }),
                            ),
                          ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── 提示文字 ──────────────────────────────────────────────────
            Text(
              '點擊貼圖可調整文字、位置與字型',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 20),

            // ── 底部按鈕 ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: _isExporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    _isExporting ? '儲存中...' : '儲存至相簿',
                    style: GoogleFonts.notoSansTc(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.like,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: _isExporting ? null : _saveToGallery,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
