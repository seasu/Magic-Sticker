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
import '../widgets/caption_editor.dart';
import '../widgets/sticker_canvas.dart';
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

      await Gal.putImageBytes(bytes);
      await FirebaseAnalytics.instance.logEvent(name: 'sticker_generated');
      setState(() {
        _keptCount++;
        _isExporting = false;
        _currentIndex++;
      });
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
              Expanded(child: _LoadingView(status: state.status))
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

              // ── 文字編輯（簡潔內嵌） ──────────────────────────────
              _InlineTextEditor(
                text: state.stickerTexts[_currentIndex],
                stickerIndex: _currentIndex,
                onChanged: (t) => ref
                    .read(editorStateProvider(widget.imagePath).notifier)
                    .updateStickerText(_currentIndex, t),
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
  final VoidCallback? onRetry;

  const _CardStack({
    required this.state,
    required this.currentIndex,
    required this.repaintKeys,
    required this.cardController,
    required this.onAccepted,
    required this.onRejected,
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
                config: kStickerConfigs[currentIndex + 2],
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
                config: kStickerConfigs[currentIndex + 1],
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
                config: kStickerConfigs[currentIndex],
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

  const _StickerCard({
    this.repaintKey,
    required this.subjectBytes,
    this.generatedImage,
    required this.text,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final canvas = StickerCanvas(
      subjectBytes: subjectBytes,
      generatedImage: generatedImage,
      text: text,
      config: config,
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
          ),
          SizedBox(width: 6),
          Text('Gemini 貼圖生成中…', style: TextStyle(fontSize: 11, color: Colors.white)),
        ],
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

// ─── 內嵌文字編輯器（簡潔版） ─────────────────────────────────────────────

class _InlineTextEditor extends StatelessWidget {
  final String text;
  final int stickerIndex;
  final ValueChanged<String> onChanged;

  const _InlineTextEditor({
    required this.text,
    required this.stickerIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CaptionEditor(
      text: text,
      stickerIndex: stickerIndex,
      onTextChanged: onChanged,
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

// ─── Loading（Shimmer 骨架）/ Error ───────────────────────────────────────

class _LoadingView extends StatefulWidget {
  final EditorStatus status;

  const _LoadingView({required this.status});

  @override
  State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.status == EditorStatus.removingBackground
        ? '正在處理圖片…'
        : '正在準備貼圖生成…';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shimmer 骨架卡（與正式卡尺寸一致）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AspectRatio(
            aspectRatio: 740 / 640,
            child: AnimatedBuilder(
              animation: _shimmerCtrl,
              builder: (_, __) {
                final x = -1.0 + 3.0 * _shimmerCtrl.value;
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment(x - 1, 0),
                      end: Alignment(x + 1, 0),
                      colors: const [
                        Color(0xFFEEEEEE),
                        Color(0xFFF6F6F6),
                        Color(0xFFEEEEEE),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 狀態文字 + 小 dots 動畫
        _ShimmerLabel(label: label, controller: _shimmerCtrl),
      ],
    );
  }
}

/// 狀態文字旁的三個小光點（複用 shimmer controller）
class _ShimmerLabel extends StatelessWidget {
  final String label;
  final AnimationController controller;

  const _ShimmerLabel({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.notoSansTc(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        ...List.generate(3, (i) {
          return AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              final phase = ((controller.value - i * 0.15) % 1.0).clamp(0.0, 1.0);
              final opacity = (0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2))
                  .clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textSecondary.withOpacity(opacity),
                ),
              );
            },
          );
        }),
      ],
    );
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
