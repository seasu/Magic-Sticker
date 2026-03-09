import 'dart:async';
import 'dart:io';
import 'dart:math' show min, pi, sin;
import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/sticker_shape.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/editor_state.dart';
import '../models/sticker_config.dart';
import '../providers/editor_provider.dart';
import '../widgets/sticker_canvas.dart';
import '../widgets/sticker_edit_sheet.dart';
import '../widgets/sticker_swipe_card.dart';

// ── 顏色常數 ──────────────────────────────────────────────────────────────────

const _kBg = AppColors.surface;
const _kNopeColor = AppColors.nope;
const _kLikeColor = AppColors.like;

class EditorScreen extends ConsumerStatefulWidget {
  final String imagePath;
  final int styleIndex;
  final StickerShape stickerShape;

  const EditorScreen({
    super.key,
    required this.imagePath,
    this.styleIndex = 0,
    this.stickerShape = StickerShape.circle,
  });

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _repaintKeys = List.generate(8, (_) => GlobalKey());
  final _cardController = StickerSwipeCardController();

  int _currentIndex = 0;
  int _keptCount = 0;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editorStateProvider(widget.imagePath).notifier).initialize(
            defaultStyleIndex: widget.styleIndex,
            stickerShape: widget.stickerShape,
          );
    });
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _accept() async {
    FirebaseService.log('EditorScreen._accept: sticker ${_currentIndex + 1}');
    setState(() => _isExporting = true);
    try {
      final boundary = _repaintKeys[_currentIndex].currentContext!
          .findRenderObject() as RenderRepaintBoundary;

      const double targetWidth = 370.0;
      final double pixelRatio = targetWidth / boundary.size.width;

      // ── Step 1: 擷取正方形畫布（aspectRatio = 1.0）──────────────────
      final rectImage = await boundary.toImage(pixelRatio: pixelRatio);
      final w = rectImage.width.toDouble();
      final h = rectImage.height.toDouble();

      // ── Step 2: 依形狀決定匯出遮罩 ──────────────────────────────────
      final ui.Image exportImage;
      if (widget.stickerShape == StickerShape.circle) {
        // 正圓：取最短邊為直徑，確保寬高相等的圓
        final size = min(w, h);
        final left = (w - size) / 2;
        final top = (h - size) / 2;
        final recorder = ui.PictureRecorder();
        final exportCanvas = Canvas(recorder);
        exportCanvas.clipPath(
          Path()..addOval(Rect.fromLTWH(0, 0, size, size)),
        );
        // 先填白底，確保匯出 PNG 無透明像素，避免相簿 / 截圖顯示棋盤格
        exportCanvas.drawOval(
          Rect.fromLTWH(0, 0, size, size),
          Paint()..color = const Color(0xFFFFFFFF),
        );
        exportCanvas.drawImage(rectImage, Offset(-left, -top), Paint());
        exportImage = await recorder
            .endRecording()
            .toImage(size.toInt(), size.toInt());
      } else {
        // 方形：直接輸出，不加任何遮罩
        exportImage = rectImage;
      }

      final byteData =
          await exportImage.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      const int maxBytes = 1 * 1024 * 1024;
      if (bytes.lengthInBytes > maxBytes) {
        FirebaseService.log(
          'sticker_export_oversized: ${bytes.lengthInBytes} bytes',
        );
      }

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
      final tmpFile = File('${tmpDir.path}/magic_morning_$ts.png');
      await tmpFile.writeAsBytes(bytes);
      await Gal.putImage(tmpFile.path);
      await tmpFile.delete();
      await FirebaseAnalytics.instance.logEvent(name: 'sticker_generated');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('貼圖已儲存到相簿 ✨',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      setState(() {
        _keptCount++;
        _isExporting = false;
        _currentIndex++;
      });
    } on GalException catch (e, stack) {
      // e.error 在 gal 1.x 為 Object?，需要 null-aware 處理
      final pe = e.error as PlatformException?;
      FirebaseService.log(
        'GalException type=${e.type.name} | '
        'underlying=${pe?.runtimeType}: $pe',
      );
      FirebaseService.log(
        'PlatformException code=${pe?.code} '
        'message=${pe?.message} details=${pe?.details}',
      );
      await FirebaseService.recordError(pe ?? e, stack,
          reason: 'editor_export_failed/gal_${e.type.name}');
      await FirebaseService.recordError(e, stack,
          reason: 'editor_export_failed');
      setState(() => _isExporting = false);
      if (!mounted) return;
      final msg = switch (e.type) {
        GalExceptionType.accessDenied => '請至設定開啟相簿存取權限',
        GalExceptionType.notEnoughSpace => '儲存空間不足，請清理後重試',
        _ => '儲存失敗，請重試',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack,
          reason: 'editor_export_failed');
      setState(() {
        _isExporting = false;
        _currentIndex++;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儲存失敗，請重試')),
      );
    }
  }

  void _reject() => setState(() => _currentIndex++);

  void _openEditSheet() {
    final state = ref.read(editorStateProvider(widget.imagePath));
    final notifier = ref.read(editorStateProvider(widget.imagePath).notifier);
    final idx = _currentIndex;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StickerEditSheet(
        stickerIndex: idx,
        initialText: state.stickerTexts[idx],
        initialSchemeIndex: state.colorSchemeIndices[idx],
        initialScale: state.imageScales[idx],
        initialOffset: state.imageOffsets[idx],
        initialImageAngle: state.imageAngles[idx],
        initialFontIndex: state.fontIndices[idx],
        initialStyleIndex: state.styleIndices[idx],
        initialTextXAlign: state.textXAligns[idx],
        initialTextYAlign: state.textYAligns[idx],
        initialTextAngle: state.textAngles[idx],
        initialFontSizeScale: state.fontSizeScales[idx],
        subjectBytes: state.subjectBytes,
        generatedImage: state.generatedImages[idx],
        stickerShape: state.stickerShape,
        onTextChanged: (text) => notifier.updateStickerText(idx, text),
        onSchemeChanged: (si) => notifier.updateColorSchemeIndex(idx, si),
        onTransformChanged: (s, o, a) =>
            notifier.updateImageTransform(idx, s, o, a),
        onFontChanged: (fi) => notifier.updateFontIndex(idx, fi),
        onStyleChanged: (si) => notifier.updateStyleIndex(idx, si),
        onTextGestureChanged: (xAlign, yAlign, angle, sizeScale) =>
            notifier.updateTextTransform(
          idx,
          xAlign: xAlign,
          yAlign: yAlign,
          angle: angle,
          sizeScale: sizeScale,
        ),
      ),
    );
  }

  void _regenerate() {
    setState(() {
      _currentIndex = 0;
      _keptCount = 0;
    });
    ref.read(editorStateProvider(widget.imagePath).notifier).regenerateTexts();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorStateProvider(widget.imagePath));
    final isLoading = state.status == EditorStatus.removingBackground ||
        state.status == EditorStatus.generatingTexts;
    final isReady = state.status == EditorStatus.ready;
    final isDone = isReady && _currentIndex >= 8;

    // 當前張 AI 圖片仍在生成中（null = loading）→ 全畫面 loading 遮罩
    final isCurrentImageLoading = isReady &&
        !isDone &&
        state.generatedImages[_currentIndex] == null;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Stack(
          children: [
            // ── 主畫面內容 ─────────────────────────────────────────────
            Column(
              children: [
                // ── 頂部列 ──────────────────────────────────────────────
                _TopBar(
                  onBack: () => context.go('/'),
                  onRefresh: (isReady && !isDone) ? _regenerate : null,
                ),

                if (isLoading)
                  const Expanded(child: _FunLoadingView())
                else if (state.errorMessage != null)
                  Expanded(child: _ErrorView(message: state.errorMessage!))
                else if (isDone)
                  Expanded(
                    child: _CompletionView(
                      keptCount: _keptCount,
                      onRegenerate: _regenerate,
                      onFinish: () => context.go('/'),
                    ),
                  )
                else if (isReady) ...[
                  // ── 進度條 ────────────────────────────────────────────
                  _ProgressBar(current: _currentIndex),
                  const SizedBox(height: 4),

                  // ── 卡片層疊 ──────────────────────────────────────────
                  Expanded(
                    child: _CardStack(
                      state: state,
                      currentIndex: _currentIndex,
                      repaintKeys: _repaintKeys,
                      cardController: _cardController,
                      onAccepted: _accept,
                      onRejected: _reject,
                      onEdit: _openEditSheet,
                      onRetry: () => ref
                          .read(
                              editorStateProvider(widget.imagePath).notifier)
                          .retryImageGeneration(_currentIndex),
                      stickerShape: state.stickerShape,
                    ),
                  ),

                  // ── Tinder 圓形按鈕 ───────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _TinderButtons(
                      isExporting: _isExporting,
                      onNope: _isExporting
                          ? null
                          : () => _cardController.reject(),
                      onLike: _isExporting
                          ? null
                          : () => _cardController.accept(),
                    ),
                  ),
                ],
              ],
            ),

            // ── 圖片生成中：全畫面貓追老鼠遮罩（鎖定操作）───────────────
            if (isCurrentImageLoading)
              const AbsorbPointer(
                child: _FunLoadingView(),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 頂部列 ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  const _TopBar({required this.onBack, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            style: IconButton.styleFrom(foregroundColor: Colors.black87),
          ),
          const Spacer(),
          const Text(
            '選擇貼圖',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          if (onRefresh != null)
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
              style: IconButton.styleFrom(foregroundColor: Colors.black54),
              tooltip: '重新生成',
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// ─── 進度條 ──────────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final int current;

  const _ProgressBar({required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(8, (i) {
          final isActive = i == current;
          final isPast = i < current;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isPast
                    ? _kLikeColor.withValues(alpha: 0.6)
                    : isActive
                        ? Colors.black87
                        : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── 卡片層疊 ─────────────────────────────────────────────────────────────────

class _CardStack extends StatelessWidget {
  final EditorState state;
  final int currentIndex;
  final List<GlobalKey> repaintKeys;
  final StickerSwipeCardController cardController;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;
  final VoidCallback onEdit;
  final VoidCallback? onRetry;
  final StickerShape stickerShape;

  const _CardStack({
    required this.state,
    required this.currentIndex,
    required this.repaintKeys,
    required this.cardController,
    required this.onAccepted,
    required this.onRejected,
    required this.onEdit,
    this.onRetry,
    this.stickerShape = StickerShape.circle,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 下下張（最底層）
        if (currentIndex + 2 < 8)
          Transform.scale(
            scale: 0.88,
            child: Opacity(
              opacity: 0.25,
              child: _StickerCard(
                subjectBytes: state.subjectBytes,
                generatedImage: state.generatedImages[currentIndex + 2],
                text: state.stickerTexts[currentIndex + 2],
                config: kStickerConfigs[
                    state.colorSchemeIndices[currentIndex + 2]],
                initialScale: state.imageScales[currentIndex + 2],
                initialOffset: state.imageOffsets[currentIndex + 2],
                initialImageAngle: state.imageAngles[currentIndex + 2],
                fontIndex: state.fontIndices[currentIndex + 2],
                fontSizeScale: state.fontSizeScales[currentIndex + 2],
                textXAlign: state.textXAligns[currentIndex + 2],
                textYAlign: state.textYAligns[currentIndex + 2],
                textAngle: state.textAngles[currentIndex + 2],
                stickerShape: stickerShape,
              ),
            ),
          ),

        // 下一張（中層）
        if (currentIndex + 1 < 8)
          Transform.scale(
            scale: 0.94,
            child: Opacity(
              opacity: 0.50,
              child: _StickerCard(
                subjectBytes: state.subjectBytes,
                generatedImage: state.generatedImages[currentIndex + 1],
                text: state.stickerTexts[currentIndex + 1],
                config: kStickerConfigs[
                    state.colorSchemeIndices[currentIndex + 1]],
                initialScale: state.imageScales[currentIndex + 1],
                initialOffset: state.imageOffsets[currentIndex + 1],
                initialImageAngle: state.imageAngles[currentIndex + 1],
                fontIndex: state.fontIndices[currentIndex + 1],
                fontSizeScale: state.fontSizeScales[currentIndex + 1],
                textXAlign: state.textXAligns[currentIndex + 1],
                textYAlign: state.textYAligns[currentIndex + 1],
                textAngle: state.textAngles[currentIndex + 1],
                stickerShape: stickerShape,
              ),
            ),
          ),

        // 目前張（可滑動）
        StickerSwipeCard(
          key: ValueKey(currentIndex),
          controller: cardController,
          onAccepted: onAccepted,
          onRejected: onRejected,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              _StickerCard(
                repaintKey: repaintKeys[currentIndex],
                subjectBytes: state.subjectBytes,
                generatedImage: state.generatedImages[currentIndex],
                text: state.stickerTexts[currentIndex],
                config:
                    kStickerConfigs[state.colorSchemeIndices[currentIndex]],
                initialScale: state.imageScales[currentIndex],
                initialOffset: state.imageOffsets[currentIndex],
                initialImageAngle: state.imageAngles[currentIndex],
                fontIndex: state.fontIndices[currentIndex],
                fontSizeScale: state.fontSizeScales[currentIndex],
                textXAlign: state.textXAligns[currentIndex],
                textYAlign: state.textYAligns[currentIndex],
                textAngle: state.textAngles[currentIndex],
                onTap: onEdit,
                stickerShape: stickerShape,
              ),
              // ── 生成中 badge ──────────────────────────────────────────
              if (state.generatedImages[currentIndex] == null)
                Positioned(
                  top: 8,
                  child: _StatusBadge.loading(),
                ),

              // ── 生成失敗 badge + 重試 ─────────────────────────────────
              if (state.generatedImages[currentIndex]?.isEmpty == true)
                Positioned(
                  top: 8,
                  child: _StatusBadge.failed(
                    reason: state.imageErrors[currentIndex],
                    onRetry: onRetry,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── 貼圖卡片外框 ─────────────────────────────────────────────────────────────

class _StickerCard extends StatelessWidget {
  final GlobalKey? repaintKey;
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final String text;
  final StickerConfig config;
  final double initialScale;
  final Offset initialOffset;
  final double initialImageAngle;
  final int fontIndex;
  final double fontSizeScale;
  final double textXAlign;
  final double textYAlign;
  final double textAngle;
  final VoidCallback? onTap;
  final StickerShape stickerShape;

  const _StickerCard({
    this.repaintKey,
    required this.subjectBytes,
    this.generatedImage,
    required this.text,
    required this.config,
    this.initialScale = 1.0,
    this.initialOffset = Offset.zero,
    this.initialImageAngle = 0.0,
    this.fontIndex = 0,
    this.fontSizeScale = 1.0,
    this.textXAlign = 0.0,
    this.textYAlign = 0.85,
    this.textAngle = 0.0,
    this.onTap,
    this.stickerShape = StickerShape.circle,
  });

  @override
  Widget build(BuildContext context) {
    final canvas = StickerCanvas(
      subjectBytes: subjectBytes,
      generatedImage: generatedImage,
      text: text,
      config: config,
      initialScale: initialScale,
      initialOffset: initialOffset,
      initialImageAngle: initialImageAngle,
      fontIndex: fontIndex,
      fontSizeScale: fontSizeScale,
      textXAlign: textXAlign,
      textYAlign: textYAlign,
      textAngle: textAngle,
      onTap: onTap,
      stickerShape: stickerShape,
    );

    final inner = repaintKey != null
        ? RepaintBoundary(key: repaintKey, child: canvas)
        : canvas;

    // 圓形：卡片外框用圓形陰影；方形：維持圓角矩形陰影
    final card = stickerShape == StickerShape.circle
        ? Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: inner,
          )
        : Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: inner,
          );

    if (onTap == null) return card;

    // 明顯可點擊的編輯按鈕，避免 Scale/HorizontalDrag gesture 衝突
    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: 10,
          right: 8,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.edit_rounded,
                size: 18,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── AI 狀態 Badge ────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool isFailed;
  final String? reason;
  final VoidCallback? onRetry;

  const _StatusBadge.loading()
      : isFailed = false,
        reason = null,
        onRetry = null;

  const _StatusBadge.failed({this.reason, this.onRetry}) : isFailed = true;

  @override
  Widget build(BuildContext context) {
    if (isFailed) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onRetry?.call();
        },
        onLongPress: reason == null
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('API 錯誤詳情'),
                    content: SingleChildScrollView(
                        child: SelectableText(reason!)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('關閉'),
                      ),
                    ],
                  ),
                ),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 13, color: Colors.white),
              SizedBox(width: 5),
              Text(
                'AI 生成失敗，點此重試',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600),
              ),
              SizedBox(width: 5),
              Icon(Icons.refresh, size: 13, color: Colors.white),
            ],
          ),
        ),
      );
    }

    return const _CatChaseMiniBadge();
  }
}

// ─── 迷你貓追老鼠 Badge（每張卡片生成中狀態）────────────────────────────────

class _CatChaseMiniBadge extends StatefulWidget {
  const _CatChaseMiniBadge();

  @override
  State<_CatChaseMiniBadge> createState() => _CatChaseMiniBadgeState();
}

class _CatChaseMiniBadgeState extends State<_CatChaseMiniBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _bounce;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..repeat(reverse: true);
    _bounce = Tween<double>(begin: 0.0, end: -4.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: AnimatedBuilder(
        animation: _bounce,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, _bounce.value),
              child: const Text('🐱', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 2),
            Transform.translate(
              offset: Offset(0, -_bounce.value),
              child: const Text('🐭', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 6),
            const Text(
              'AI 生成中…',
              style: TextStyle(fontSize: 11, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tinder 大圓形按鈕 ────────────────────────────────────────────────────────

class _TinderButtons extends StatelessWidget {
  final bool isExporting;
  final VoidCallback? onNope;
  final VoidCallback? onLike;

  const _TinderButtons({
    required this.isExporting,
    required this.onNope,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleButton(
          size: 64,
          icon: Icons.close_rounded,
          iconSize: 30,
          iconColor: _kNopeColor,
          bgColor: Colors.white,
          borderColor: _kNopeColor,
          shadowColor: _kNopeColor,
          onTap: onNope,
        ),
        const SizedBox(width: 52),
        _CircleButton(
          size: 76,
          icon: isExporting ? null : Icons.favorite_rounded,
          iconSize: 36,
          iconColor: Colors.white,
          bgColor: _kLikeColor,
          shadowColor: _kLikeColor,
          isLoading: isExporting,
          onTap: onLike,
        ),
      ],
    );
  }
}

class _CircleButton extends StatefulWidget {
  final double size;
  final IconData? icon;
  final double iconSize;
  final Color iconColor;
  final Color bgColor;
  final Color? borderColor;
  final Color shadowColor;
  final VoidCallback? onTap;
  final bool isLoading;

  const _CircleButton({
    required this.size,
    this.icon,
    required this.iconSize,
    required this.iconColor,
    required this.bgColor,
    this.borderColor,
    required this.shadowColor,
    this.onTap,
    this.isLoading = false,
  });

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _scale = Tween(begin: 1.0, end: 0.86).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.isLoading;
    return GestureDetector(
      onTapDown: enabled ? (_) => _ctrl.forward() : null,
      onTapUp: enabled
          ? (_) {
              _ctrl.reverse();
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      onTapCancel: enabled ? () => _ctrl.reverse() : null,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? widget.bgColor : Colors.grey.shade200,
            border: widget.borderColor != null && enabled
                ? Border.all(color: widget.borderColor!, width: 2.5)
                : null,
            boxShadow: [
              if (enabled)
                BoxShadow(
                  color: widget.shadowColor.withValues(alpha: 0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                  spreadRadius: 1,
                ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: widget.iconColor,
                    ),
                  )
                : Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: enabled
                        ? widget.iconColor
                        : Colors.grey.shade400,
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── 完成畫面 ─────────────────────────────────────────────────────────────────

class _CompletionView extends StatefulWidget {
  final int keptCount;
  final VoidCallback onRegenerate;
  final VoidCallback onFinish;

  const _CompletionView({
    required this.keptCount,
    required this.onRegenerate,
    required this.onFinish,
  });

  @override
  State<_CompletionView> createState() => _CompletionViewState();
}

class _CompletionViewState extends State<_CompletionView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseScale = Tween(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasKept = widget.keptCount > 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseScale,
              builder: (_, child) => Transform.scale(
                scale: hasKept ? _pulseScale.value : 1.0,
                child: child,
              ),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasKept ? AppColors.gradient : null,
                  color: hasKept ? null : Colors.grey.shade200,
                  boxShadow: hasKept
                      ? [
                          BoxShadow(
                            color:
                                const Color(0xFFFF5864).withValues(alpha: 0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  hasKept
                      ? Icons.favorite_rounded
                      : Icons.sentiment_neutral,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasKept ? '儲存了 ${widget.keptCount} 張貼圖 🎉' : '全部跳過',
              style: GoogleFonts.notoSansTc(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasKept ? '貼圖已存入相簿（370×320 px PNG）' : '試試重新生成？',
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            if (hasKept) ...[
              const SizedBox(height: 6),
              Text(
                '已儲存 LINE 貼圖，可至 LINE Creators Market 上架',
                style: GoogleFonts.notoSansTc(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 40),
            GestureDetector(
              onTap: widget.onRegenerate,
              child: Container(
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF5864).withValues(alpha: 0.30),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '重新生成',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: widget.onFinish,
              child: Text(
                '回到首頁',
                style: GoogleFonts.notoSansTc(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 全螢幕趣味 Loading：貓追老鼠大場景（追劇雙關）
// ═══════════════════════════════════════════════════════════════════════════════

class _FunLoadingView extends StatefulWidget {
  const _FunLoadingView();

  @override
  State<_FunLoadingView> createState() => _FunLoadingViewState();
}

class _FunLoadingViewState extends State<_FunLoadingView>
    with TickerProviderStateMixin {
  late final AnimationController _chaseCtrl;
  late final AnimationController _bounceCtrl;
  late final AnimationController _cloudCtrl;
  int _msgIndex = 0;
  Timer? _msgTimer;

  static const _messages = [
    '🎬 AI 貓咪正在幫你「追劇」製作貼圖…',
    '🐭 老鼠：「我就是在追劇啦！」',
    '✨ 施展魔法中，稍等一下下',
    '🎨 AI 畫師拼命作畫，快好了！',
    '💨 跑不掉的！AI 馬上追上了',
  ];

  @override
  void initState() {
    super.initState();
    _chaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..repeat(reverse: true);
    _cloudCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();
    _msgTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (mounted) {
        setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
      }
    });
  }

  @override
  void dispose() {
    _chaseCtrl.dispose();
    _bounceCtrl.dispose();
    _cloudCtrl.dispose();
    _msgTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          // ── 大場景動畫區（佔 70%）───────────────────────────────────
          Expanded(
            flex: 7,
            child: _ChaseStage(
              chaseCtrl: _chaseCtrl,
              bounceCtrl: _bounceCtrl,
              cloudCtrl: _cloudCtrl,
            ),
          ),

          // ── 訊息區（佔 30%）──────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.4),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOut,
                        )),
                        child: child,
                      ),
                    ),
                    child: Text(
                      _messages[_msgIndex],
                      key: ValueKey(_msgIndex),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BounceDots(controller: _chaseCtrl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 三顆跳動圓點進度指示器
class _BounceDots extends AnimatedWidget {
  const _BounceDots({required AnimationController controller})
      : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as AnimationController).value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final phase = ((t * 3) - i).clamp(0.0, 1.0);
        final s = 0.5 + 0.5 * sin(phase * pi).clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Transform.scale(
            scale: s,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black87,
                  s,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 全螢幕追逐場景：🐭 前跑、🐱 後追、雲朵飄移、草地、星芒尾跡
class _ChaseStage extends StatelessWidget {
  final AnimationController chaseCtrl;
  final AnimationController bounceCtrl;
  final AnimationController cloudCtrl;

  const _ChaseStage({
    required this.chaseCtrl,
    required this.bounceCtrl,
    required this.cloudCtrl,
  });

  static const _catFontSize = 90.0;
  static const _mouseFontSize = 78.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final groundY = h * 0.62; // 地板在 62% 高度
      final travelW = w - _catFontSize - 24;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          // ── 雲朵（緩慢飄移）──────────────────────────────────────────
          AnimatedBuilder(
            animation: cloudCtrl,
            builder: (_, __) {
              final t = cloudCtrl.value;
              return Stack(
                children: [
                  Positioned(
                    left: (w * (0.05 + t * 0.6)) % (w + 80) - 40,
                    top: h * 0.06,
                    child: const Text('☁️',
                        style: TextStyle(fontSize: 52)),
                  ),
                  Positioned(
                    left: (w * (0.55 + t * 0.45)) % (w + 70) - 35,
                    top: h * 0.17,
                    child: const Text('⛅',
                        style: TextStyle(fontSize: 40)),
                  ),
                  Positioned(
                    left: (w * (0.25 + t * 0.35)) % (w + 60) - 30,
                    top: h * 0.03,
                    child: const Text('☁️',
                        style: TextStyle(fontSize: 34)),
                  ),
                ],
              );
            },
          ),

          // ── 地板線（草地色）──────────────────────────────────────────
          Positioned(
            top: groundY,
            left: 0,
            right: 0,
            child: Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Color(0xFF6DBE6D),
                    Color(0xFF6DBE6D),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ── 草叢裝飾 ─────────────────────────────────────────────────
          Positioned(
            top: groundY - 10,
            left: w * 0.08,
            child: const Text('🌿', style: TextStyle(fontSize: 20)),
          ),
          Positioned(
            top: groundY - 9,
            left: w * 0.42,
            child: const Text('🌱', style: TextStyle(fontSize: 17)),
          ),
          Positioned(
            top: groundY - 8,
            right: w * 0.12,
            child: const Text('🌿', style: TextStyle(fontSize: 16)),
          ),

          // ── 角色動畫 ─────────────────────────────────────────────────
          AnimatedBuilder(
            animation: Listenable.merge([chaseCtrl, bounceCtrl]),
            builder: (_, __) {
              final t = chaseCtrl.value;
              final b = bounceCtrl.value;

              final mouseProgress = (t + 0.18).clamp(0.0, 1.0);
              final catProgress = t;

              final catX = travelW * catProgress;
              final mouseX =
                  (travelW * mouseProgress + 100).clamp(0.0, w - _mouseFontSize);

              // sin 曲線彈跳（自然跑步感）
              final catBounce = -16.0 * sin(b * pi);
              final mouseBounce = -20.0 * sin((b + 0.22) * pi);

              final sparkOpacity =
                  (sin(t * pi * 7) * 0.5 + 0.5).clamp(0.0, 1.0);

              // 角色腳底對齊地板
              final charBaseY = groundY - _catFontSize + 6;

              return Stack(
                children: [
                  // ── 速度線（貓身後）
                  Positioned(
                    left: catX - 36,
                    top: charBaseY + catBounce + 36,
                    child: Opacity(
                      opacity: 0.45,
                      child: Text(
                        '— — —',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade400,
                          letterSpacing: -3,
                        ),
                      ),
                    ),
                  ),

                  // ── 星芒尾跡（老鼠身後）
                  Positioned(
                    left: mouseX - 26,
                    top: charBaseY + mouseBounce + 8,
                    child: Opacity(
                      opacity: sparkOpacity * 0.9,
                      child: const Text('✨',
                          style: TextStyle(fontSize: 26)),
                    ),
                  ),
                  Positioned(
                    left: mouseX - 52,
                    top: charBaseY + mouseBounce + 22,
                    child: Opacity(
                      opacity: (1 - sparkOpacity) * 0.7,
                      child: const Text('⭐',
                          style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  Positioned(
                    left: mouseX - 72,
                    top: charBaseY + mouseBounce + 12,
                    child: Opacity(
                      opacity: sparkOpacity * 0.5,
                      child: const Text('💫',
                          style: TextStyle(fontSize: 14)),
                    ),
                  ),

                  // ── 🐭 老鼠（水平翻轉，面朝逃跑方向）
                  Positioned(
                    left: mouseX,
                    top: charBaseY + mouseBounce,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..scale(-1.0, 1.0),
                      child: const Text('🐭',
                          style: TextStyle(fontSize: _mouseFontSize)),
                    ),
                  ),

                  // ── 🐱 貓
                  Positioned(
                    left: catX,
                    top: charBaseY + catBounce,
                    child: const Text('🐱',
                        style: TextStyle(fontSize: _catFontSize)),
                  ),
                ],
              );
            },
          ),
        ],
      );
    });
  }
}

// ─── 錯誤畫面 ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 56, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 15, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
