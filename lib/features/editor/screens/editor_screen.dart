import 'dart:async';
import 'dart:math' show pi, sin;
import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/editor_state.dart';
import '../models/sticker_config.dart';
import '../providers/editor_provider.dart';
import '../widgets/sticker_canvas.dart';
import '../widgets/sticker_edit_sheet.dart';
import '../widgets/sticker_swipe_card.dart';

// ── 顏色常數（使用 AppColors 統一管理） ──────────────────────────────────────

const _kBg = AppColors.surface;
const _kNopeColor = AppColors.nope;
const _kLikeColor = AppColors.like;

class EditorScreen extends ConsumerStatefulWidget {
  final String imagePath;

  const EditorScreen({super.key, required this.imagePath});

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
      ref.read(editorStateProvider(widget.imagePath).notifier).initialize();
    });
  }

  // ─── Actions ──────────────────────────────────────────────────────

  /// 匯出貼圖：固定輸出 370×320 px 透明背景 PNG（LINE Creators Market 規格）
  Future<void> _accept() async {
    FirebaseService.log('EditorScreen._accept: sticker ${_currentIndex + 1}');
    setState(() => _isExporting = true);
    try {
      final boundary = _repaintKeys[_currentIndex].currentContext!
          .findRenderObject() as RenderRepaintBoundary;

      // 計算讓輸出寬度恰好 370px 所需的 pixelRatio
      // LINE Creators Market 規格：370×320 px（比例 37:32）
      const double targetWidth = 370.0;
      final double pixelRatio = targetWidth / boundary.size.width;

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      // LINE 規格：單檔上限 1 MB
      const int maxBytes = 1 * 1024 * 1024;
      if (bytes.lengthInBytes > maxBytes) {
        FirebaseService.log(
          'sticker_export_oversized: ${bytes.lengthInBytes} bytes',
        );
      }

      // 儲存前確保 runtime 權限已授予（Android 13+ READ_MEDIA_IMAGES）
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          throw GalException(
            type: GalExceptionType.accessDenied,
            error: Exception('Storage access denied'),
            stackTrace: StackTrace.current,
          );
        }
      }

      await Gal.putImageBytes(bytes);
      await FirebaseAnalytics.instance.logEvent(name: 'sticker_generated');
      setState(() {
        _keptCount++;
        _isExporting = false;
        _currentIndex++;
      });
    } on GalException catch (e, stack) {
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
        initialFontIndex: state.fontIndices[idx],
        initialStyleIndex: state.styleIndices[idx],
        subjectBytes: state.subjectBytes,
        generatedImage: state.generatedImages[idx],
        onTextChanged: (text) => notifier.updateStickerText(idx, text),
        onSchemeChanged: (si) => notifier.updateColorSchemeIndex(idx, si),
        onTransformChanged: (s, o) =>
            notifier.updateImageTransform(idx, s, o),
        onFontChanged: (fi) => notifier.updateFontIndex(idx, fi),
        onStyleChanged: (si) => notifier.updateStyleIndex(idx, si),
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

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorStateProvider(widget.imagePath));
    final isLoading = state.status == EditorStatus.removingBackground ||
        state.status == EditorStatus.generatingTexts;
    final isReady = state.status == EditorStatus.ready;
    final isDone = isReady && _currentIndex >= 8;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
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
              // ── 進度 ─────────────────────────────────────────────
              _ProgressBar(current: _currentIndex),
              const SizedBox(height: 4),

              // ── 卡片區 ────────────────────────────────────────────
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
                      .read(editorStateProvider(widget.imagePath).notifier)
                      .retryImageGeneration(_currentIndex),
                ),
              ),

              // ── Tinder 圓形按鈕 ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _TinderButtons(
                  isExporting: _isExporting,
                  onNope: _isExporting ? null : () => _cardController.reject(),
                  onLike: _isExporting ? null : () => _cardController.accept(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 頂部列 ────────────────────────────────────────────────────────────────

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
          Text(
            '選擇貼圖',
            style: const TextStyle(
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

// ─── 進度條 ────────────────────────────────────────────────────────────────

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
                    ? _kLikeColor.withOpacity(0.6)
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

// ─── 卡片層疊 ──────────────────────────────────────────────────────────────

class _CardStack extends StatelessWidget {
  final EditorState state;
  final int currentIndex;
  final List<GlobalKey> repaintKeys;
  final StickerSwipeCardController cardController;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;
  final VoidCallback onEdit;
  final VoidCallback? onRetry;

  const _CardStack({
    required this.state,
    required this.currentIndex,
    required this.repaintKeys,
    required this.cardController,
    required this.onAccepted,
    required this.onRejected,
    required this.onEdit,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 下下張（最底層，更小）
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
                fontIndex: state.fontIndices[currentIndex + 2],
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
                fontIndex: state.fontIndices[currentIndex + 1],
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
                config: kStickerConfigs[state.colorSchemeIndices[currentIndex]],
                initialScale: state.imageScales[currentIndex],
                initialOffset: state.imageOffsets[currentIndex],
                fontIndex: state.fontIndices[currentIndex],
                onTap: onEdit,
              ),
              // ── 生成中 badge ──────────────────────────────────────
              if (state.generatedImages[currentIndex] == null)
                Positioned(
                  top: 8,
                  child: _StatusBadge.loading(),
                ),

              // ── 生成失敗 badge + 重試按鈕 ─────────────────────────
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

/// 貼圖卡片外框：陰影 + 圓角 + 可選 RepaintBoundary
class _StickerCard extends StatelessWidget {
  final GlobalKey? repaintKey;
  final Uint8List? subjectBytes;
  final Uint8List? generatedImage;
  final String text;
  final StickerConfig config;
  final double initialScale;
  final Offset initialOffset;
  final int fontIndex;
  final VoidCallback? onTap;

  const _StickerCard({
    this.repaintKey,
    required this.subjectBytes,
    this.generatedImage,
    required this.text,
    required this.config,
    this.initialScale = 1.0,
    this.initialOffset = Offset.zero,
    this.fontIndex = 0,
    this.onTap,
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
      fontIndex: fontIndex,
      onTap: onTap,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: repaintKey != null
          ? RepaintBoundary(key: repaintKey, child: canvas)
          : canvas,
    );
  }
}

// ─── AI 狀態 Badge（生成中 / 失敗+重試）────────────────────────────────────

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
      const shortLabel = 'AI 生成失敗，點此重試';
      final badge = GestureDetector(
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
                    content: SingleChildScrollView(child: SelectableText(reason!)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('關閉'),
                      ),
                    ],
                  ),
                ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                shortLabel,
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.refresh, size: 13, color: Colors.white),
            ],
          ),
        ),
      );
      return badge;
    }

    return const _CatChaseMiniBadge();
  }
}

// ─── 迷你貓追老鼠 Badge（每張卡片 AI 生成中狀態）──────────────────────────

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

// ─── Tinder 大圓形按鈕 ─────────────────────────────────────────────────────

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
        // ❌ Nope（空心圓，紅邊）
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
        // ❤️ Like（實心圓，綠底）
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
                  color: widget.shadowColor.withOpacity(0.28),
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

// ─── 完成畫面（動畫版）────────────────────────────────────────────────────

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
            // ── 脈動 icon（有保留時漸層圓 + 陰影）────────────────────
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
                            color: const Color(0xFFFF5864).withOpacity(0.35),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  hasKept ? Icons.favorite_rounded : Icons.sentiment_neutral,
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
                  color: AppColors.textSecondary.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 40),
            // ── 漸層重新生成按鈕 ─────────────────────────────────────
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
                      color: const Color(0xFFFF5864).withOpacity(0.30),
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

// ─── 趣味 Loading（貓追老鼠動畫）/ Error ────────────────────────────────

/// 取代枯燥 shimmer 的趣味等待動畫：🐱 貓追 🐭 老鼠
class _FunLoadingView extends StatefulWidget {
  const _FunLoadingView();

  @override
  State<_FunLoadingView> createState() => _FunLoadingViewState();
}

class _FunLoadingViewState extends State<_FunLoadingView>
    with TickerProviderStateMixin {
  late final AnimationController _chaseCtrl;   // 橫向追逐進度
  late final AnimationController _bounceCtrl;  // 上下彈跳
  int _msgIndex = 0;
  Timer? _msgTimer;

  static const _messages = [
    '🐱 AI 貓咪正在捕捉靈感…',
    '🐭 老鼠偷走了你的臉，快追！',
    '✨ 施展魔法中，請稍等…',
    '🎨 努力作畫中，快好了！',
    '💨 再一下下，跑不掉的！',
  ];

  @override
  void initState() {
    super.initState();
    _chaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    )..repeat();
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..repeat(reverse: true);
    _msgTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted) setState(() => _msgIndex = (_msgIndex + 1) % _messages.length);
    });
  }

  @override
  void dispose() {
    _chaseCtrl.dispose();
    _bounceCtrl.dispose();
    _msgTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ChaseStage(chaseCtrl: _chaseCtrl, bounceCtrl: _bounceCtrl),
        const SizedBox(height: 36),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Text(
            _messages[_msgIndex],
            key: ValueKey(_msgIndex),
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 舞台：🐭 老鼠在前、🐱 貓在後追趕，搭配尾跡小星星
class _ChaseStage extends StatelessWidget {
  final AnimationController chaseCtrl;
  final AnimationController bounceCtrl;

  const _ChaseStage({required this.chaseCtrl, required this.bounceCtrl});

  static const _stageHeight = 160.0;
  static const _floor = 110.0;        // 角色底部距舞台頂的距離
  static const _catSize = 52.0;
  static const _mouseSize = 46.0;
  static const _gap = 88.0;           // 預設貓鼠水平間距

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final stageW = constraints.maxWidth;
      final travelW = stageW - _catSize - 24; // 可移動寬度

      return SizedBox(
        height: _stageHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── 地板線 ────────────────────────────────────────────────
            Positioned(
              bottom: _stageHeight - _floor - 2,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.grey.shade300,
                      Colors.grey.shade300,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── 角色（貓 + 老鼠 + 尾跡星星）─────────────────────────
            AnimatedBuilder(
              animation: Listenable.merge([chaseCtrl, bounceCtrl]),
              builder: (_, __) {
                final t = chaseCtrl.value;   // 0→1 追逐進度
                final b = bounceCtrl.value;  // 0→1→0 彈跳

                // 追逐結尾讓貓加速靠近老鼠（sin 曲線讓間距縮小）
                final catProgress = t;
                final mouseProgress = (t + 0.18).clamp(0.0, 1.0);

                final catX = travelW * catProgress;
                final mouseX = (travelW * mouseProgress + _gap).clamp(0.0, stageW - _mouseSize);

                final catBounce = -10.0 * sin(b * pi);
                final mouseBounce = -13.0 * sin((b + 0.2) * pi);

                // 星星尾跡透明度（老鼠後方）
                final sparkOpacity = (sin(t * pi * 8) * 0.5 + 0.5).clamp(0.0, 1.0);

                final baseY = _floor - _catSize;

                return Stack(
                  children: [
                    // ✨ 尾跡星星 1
                    Positioned(
                      left: mouseX - 14,
                      top: baseY + mouseBounce + 4,
                      child: Opacity(
                        opacity: sparkOpacity * 0.8,
                        child: const Text('✨', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                    // ✨ 尾跡星星 2
                    Positioned(
                      left: mouseX - 28,
                      top: baseY + mouseBounce + 14,
                      child: Opacity(
                        opacity: (1 - sparkOpacity) * 0.6,
                        child: const Text('⭐', style: TextStyle(fontSize: 10)),
                      ),
                    ),
                    // 🐭 老鼠
                    Positioned(
                      left: mouseX,
                      top: baseY + mouseBounce,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..scale(-1.0, 1.0), // 面朝右（逃跑方向）
                        child: const Text('🐭', style: TextStyle(fontSize: 40)),
                      ),
                    ),
                    // 🐱 貓
                    Positioned(
                      left: catX,
                      top: baseY + catBounce,
                      child: const Text('🐱', style: TextStyle(fontSize: 46)),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    });
  }
}

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
