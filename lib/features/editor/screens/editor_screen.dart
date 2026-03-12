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
import '../../../features/billing/providers/credit_provider.dart';
import '../../../shared/widgets/credit_paywall_dialog.dart';
import '../models/editor_state.dart';
import '../models/sticker_config.dart';
import '../providers/editor_provider.dart';
import '../widgets/sticker_canvas.dart';
import '../widgets/sticker_edit_sheet.dart';
import '../widgets/sticker_swipe_card.dart';

// ── 顏色常數 ──────────────────────────────────────────────────────────────────

const _kBg = AppColors.surface;
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
    final state = ref.read(editorStateProvider(widget.imagePath));
    final img = state.generatedImages[_currentIndex];
    // 若圖片尚未生成，先觸發生成
    if (isNotGeneratedSentinel(img)) {
      await _generateImage(_currentIndex);
      return;
    }
    // 圖片仍在生成中，忽略
    if (img == null) return;
    // 圖片生成失敗（empty sentinel），不匯出空白圖
    if (img.isEmpty) return;

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

  Future<void> _regenerate() async {
    // Spec 免費，直接重新生成文字規格
    setState(() {
      _currentIndex = 0;
      _keptCount = 0;
    });
    ref.read(editorStateProvider(widget.imagePath).notifier).regenerateTexts();
  }

  /// 使用者點擊「生成」按鈕，消耗 1 點產生圖片
  Future<void> _generateImage(int index) async {
    final credits = ref.read(creditProvider);
    if (credits <= 0) {
      FirebaseService.log('EditorScreen._generateImage: no credits → showing paywall');
      if (!mounted) return;
      final earned = await CreditPaywallDialog.show(context, ref);
      if (!earned || !mounted) return;
    }

    final result = await ref
        .read(editorStateProvider(widget.imagePath).notifier)
        .generateSingleImage(index);

    if (result == 'insufficient' && mounted) {
      final earned = await CreditPaywallDialog.show(context, ref);
      if (earned && mounted) {
        await ref
            .read(editorStateProvider(widget.imagePath).notifier)
            .generateSingleImage(index);
      }
    }
  }

  // ─── Build helpers ────────────────────────────────────────────────────────

  /// 依圖片狀態決定底部按鈕：
  ///   sentinel(length=1)  → 尚未生成  → 顯示「生成·1點」
  ///   null                → 生成中    → 隱藏（全畫面 loading 覆蓋）
  ///   empty(length=0)     → 生成失敗  → 隱藏（_FailedOverlay 內建重試，不扣點）
  ///   bytes(length>1)     → 成功      → 顯示「儲存貼圖」
  Widget _buildBottomButton(Uint8List? img) {
    if (img != null && img.isEmpty) return const SizedBox.shrink(); // 失敗：overlay 處理重試
    if (isNotGeneratedSentinel(img)) {
      return _GenerateButton(
        onTap: _isExporting ? null : () => _generateImage(_currentIndex),
      );
    }
    if (img == null) return const SizedBox.shrink(); // loading overlay covers UI
    return _SaveButton(
      isExporting: _isExporting,
      onTap: _isExporting ? null : _accept,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorStateProvider(widget.imagePath));
    final isLoading = state.status == EditorStatus.removingBackground ||
        state.status == EditorStatus.generatingTexts;
    final isReady = state.status == EditorStatus.ready;
    final isDone = isReady && _currentIndex >= 8;

    // 當前張 AI 圖片仍在生成中（null = loading，sentinel = 尚未觸發生成）
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
                      onRetry: () => _generateImage(_currentIndex),
                      stickerShape: state.stickerShape,
                    ),
                  ),

                  // ── 底部按鈕 ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: _buildBottomButton(state.generatedImages[_currentIndex]),
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
    final isGenerated = !isNotGeneratedSentinel(state.generatedImages[currentIndex]) &&
        state.generatedImages[currentIndex] != null &&
        state.generatedImages[currentIndex]!.isNotEmpty;

    return Stack(
      alignment: Alignment.center,
      children: [
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
                onTap: isGenerated ? onEdit : null,
                stickerShape: stickerShape,
                styleIndex: state.styleIndices[currentIndex],
              ),

              // ── 生成中 badge ──────────────────────────────────────────
              if (state.generatedImages[currentIndex] == null)
                const Positioned(
                  top: 8,
                  child: _StatusBadge.loading(),
                ),

              // ── 生成失敗：全卡片居中覆蓋層 ───────────────────────────
              if (state.generatedImages[currentIndex]?.isEmpty == true)
                Positioned.fill(
                  child: _FailedOverlay(
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
  final int styleIndex;

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
    this.styleIndex = 0,
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
      styleIndex: styleIndex,
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

// ─── 生成失敗：磨砂玻璃覆蓋層 ────────────────────────────────────────────────

/// 圖片生成失敗時，蓋在整張卡片上的友善錯誤提示。
/// 磨砂玻璃背景保留卡片背景紋理感；點擊重試按鈕不扣點（CF 已退還）。
/// 長按（debug only）顯示原始錯誤訊息。
class _FailedOverlay extends StatelessWidget {
  final String? reason;
  final VoidCallback? onRetry;

  const _FailedOverlay({this.reason, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: reason == null
          ? null
          : () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('API 錯誤詳情'),
                  content:
                      SingleChildScrollView(child: SelectableText(reason!)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('關閉'),
                    ),
                  ],
                ),
              ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 圖標
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFF0F3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_outlined,
                      size: 36,
                      color: Color(0xFFFF5864),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 主標題
                  const Text(
                    '生成失敗',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 副標題：說明不扣點
                  const Text(
                    '點數已退還，免費重試',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 重試按鈕
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      onRetry?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 13),
                      decoration: BoxDecoration(
                        gradient: AppColors.gradient,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF5864).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded,
                              size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            '重新生成',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── AI 狀態 Badge ────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge.loading();

  @override
  Widget build(BuildContext context) {
    return const _CatChaseMiniBadge();
  }
}

// ─── 生成按鈕（尚未觸發生成）────────────────────────────────────────────────

class _GenerateButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _GenerateButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 22, color: Colors.white),
            SizedBox(width: 8),
            Text(
              '生成 · 1點',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
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

// ─── 儲存按鈕（圖片生成後）────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  final bool isExporting;
  final VoidCallback? onTap;

  const _SaveButton({required this.isExporting, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap?.call();
      },
      child: AnimatedOpacity(
        opacity: isExporting ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          decoration: BoxDecoration(
            color: _kLikeColor,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: _kLikeColor.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isExporting
                    ? Icons.hourglass_top_rounded
                    : Icons.download_rounded,
                size: 22,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                isExporting ? '儲存中…' : '儲存貼圖',
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
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
