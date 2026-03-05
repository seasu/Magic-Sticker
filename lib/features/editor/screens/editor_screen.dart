import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/firebase_service.dart';
import '../models/editor_state.dart';
import '../models/sticker_config.dart';
import '../providers/editor_provider.dart';
import '../widgets/caption_editor.dart';
import '../widgets/sticker_canvas.dart';
import '../widgets/sticker_swipe_card.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String imagePath;

  const EditorScreen({super.key, required this.imagePath});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  // 每張貼圖各有一個 RepaintBoundary key（用於匯出）
  final _repaintKeys = List.generate(3, (_) => GlobalKey());
  final _cardController = StickerSwipeCardController();

  int _currentIndex = 0; // 目前顯示第幾張（0–2），3 = 全部完成
  int _keptCount = 0;    // 已保留張數
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editorStateProvider(widget.imagePath).notifier).initialize();
    });
  }

  // ─── Actions ──────────────────────────────────────────────────────

  /// 右滑「保留」：匯出目前貼圖，成功後前進到下一張
  Future<void> _accept() async {
    FirebaseService.log('EditorScreen._accept: sticker ${_currentIndex + 1}');
    setState(() => _isExporting = true);

    try {
      final boundary = _repaintKeys[_currentIndex].currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      await Gal.putImageBytes(byteData!.buffer.asUint8List());
      await FirebaseAnalytics.instance.logEvent(name: 'sticker_generated');

      setState(() {
        _keptCount++;
        _isExporting = false;
        _currentIndex++;
      });
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_export_failed',
      );
      setState(() {
        _isExporting = false;
        _currentIndex++; // 匯出失敗仍前進，避免卡住
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儲存失敗，請重試')),
      );
    }
  }

  /// 左滑「跳過」：不儲存，直接前進
  void _reject() => setState(() => _currentIndex++);

  /// 重新生成所有貼圖文字並重置滑動進度
  void _regenerate() {
    setState(() {
      _currentIndex = 0;
      _keptCount = 0;
    });
    ref
        .read(editorStateProvider(widget.imagePath).notifier)
        .regenerateTexts();
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorStateProvider(widget.imagePath));
    final isLoading = state.status == EditorStatus.removingBackground ||
        state.status == EditorStatus.generatingTexts;
    final isReady = state.status == EditorStatus.ready;
    final isDone = isReady && _currentIndex >= 3;

    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇貼圖'),
        actions: [
          if (isReady && !isDone)
            IconButton(
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '重新生成',
            ),
        ],
      ),
      body: Column(
        children: [
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
            // ── 進度指示器 ──────────────────────────────────────────
            const SizedBox(height: 16),
            _ProgressDots(current: _currentIndex),
            const SizedBox(height: 8),

            // ── 貼圖卡片區（目前 + 下一張預覽）────────────────────
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 下一張（縮小、半透明，製造景深效果）
                  if (_currentIndex + 1 < 3)
                    _NextCardPreview(
                      state: state,
                      index: _currentIndex + 1,
                    ),
                  // 目前可滑動的卡片
                  StickerSwipeCard(
                    key: ValueKey(_currentIndex),
                    controller: _cardController,
                    onAccepted: _accept,
                    onRejected: _reject,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 28),
                      child: _StickerCardFrame(
                        repaintKey: _repaintKeys[_currentIndex],
                        subjectBytes: state.subjectBytes,
                        text: state.stickerTexts[_currentIndex],
                        config: kStickerConfigs[_currentIndex],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── 操作按鈕 ────────────────────────────────────────────
            _ActionButtons(
              isExporting: _isExporting,
              onAccept: _isExporting ? null : () => _cardController.accept(),
              onReject: _isExporting ? null : () => _cardController.reject(),
            ),
            const SizedBox(height: 8),

            // ── 文字編輯面板 ─────────────────────────────────────────
            CaptionEditor(
              text: state.stickerTexts[_currentIndex],
              stickerIndex: _currentIndex,
              onTextChanged: (text) => ref
                  .read(editorStateProvider(widget.imagePath).notifier)
                  .updateStickerText(_currentIndex, text),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 貼圖卡片外框 ─────────────────────────────────────────────────────────

/// 帶陰影圓角框 + 可選的 RepaintBoundary（供匯出用）
class _StickerCardFrame extends StatelessWidget {
  final GlobalKey? repaintKey;
  final dynamic subjectBytes;
  final String text;
  final StickerConfig config;

  const _StickerCardFrame({
    this.repaintKey,
    required this.subjectBytes,
    required this.text,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final canvas = StickerCanvas(
      subjectBytes: subjectBytes,
      text: text,
      config: config,
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 24,
            offset: const Offset(0, 10),
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

// ─── 下一張預覽（景深層）────────────────────────────────────────────────

class _NextCardPreview extends StatelessWidget {
  final EditorState state;
  final int index;

  const _NextCardPreview({required this.state, required this.index});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.91,
      child: Opacity(
        opacity: 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: _StickerCardFrame(
            subjectBytes: state.subjectBytes,
            text: state.stickerTexts[index],
            config: kStickerConfigs[index],
          ),
        ),
      ),
    );
  }
}

// ─── 進度點點 ─────────────────────────────────────────────────────────────

class _ProgressDots extends StatelessWidget {
  final int current;

  const _ProgressDots({required this.current});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${current + 1} / 3',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        ...List.generate(
          3,
          (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: current == i ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: current == i ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 操作按鈕 ─────────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final bool isExporting;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _ActionButtons({
    required this.isExporting,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.close_rounded,
            label: '跳過',
            color: Colors.red.shade400,
            onTap: onReject,
          ),
          _ActionButton(
            icon: Icons.favorite_rounded,
            label: '保留',
            color: Colors.green.shade400,
            onTap: onAccept,
            isLoading: isExporting,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : Colors.grey.shade400;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: enabled
              ? effectiveColor.withOpacity(0.10)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: effectiveColor, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: effectiveColor,
                ),
              )
            else
              Icon(icon, color: effectiveColor, size: 22),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 完成畫面 ─────────────────────────────────────────────────────────────

class _CompletionView extends StatelessWidget {
  final int keptCount;
  final VoidCallback onRegenerate;
  final VoidCallback onFinish;

  const _CompletionView({
    required this.keptCount,
    required this.onRegenerate,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final hasKept = keptCount > 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasKept ? Icons.check_circle_outline : Icons.sentiment_neutral,
              size: 72,
              color: hasKept ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              hasKept ? '儲存了 $keptCount 張貼圖！' : '全部跳過',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hasKept ? '貼圖已存入相簿' : '下次再試試吧！',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onRegenerate,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新生成'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onFinish,
              child: const Text('回到首頁'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Loading / Error views ────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final EditorStatus status;

  const _LoadingView({required this.status});

  @override
  Widget build(BuildContext context) {
    final label = status == EditorStatus.removingBackground
        ? '正在去除背景…'
        : '正在生成貼圖文字…';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
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
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
