import 'dart:ui' as ui;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../../core/services/firebase_service.dart';
import '../models/editor_state.dart';
import '../models/sticker_config.dart';
import '../providers/editor_provider.dart';
import '../widgets/caption_editor.dart';
import '../widgets/sticker_canvas.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String imagePath;

  const EditorScreen({super.key, required this.imagePath});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  // 每張貼圖各有一個 RepaintBoundary key
  final _repaintKeys = List.generate(3, (_) => GlobalKey());
  final _pageController = PageController();
  int _currentPage = 0;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editorStateProvider(widget.imagePath).notifier).initialize();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ─── Actions ───────────────────────────────────────────────────────

  Future<void> _exportAll() async {
    FirebaseService.log('EditorScreen._exportAll: start');
    setState(() => _isExporting = true);

    try {
      for (int i = 0; i < 3; i++) {
        final boundary = _repaintKeys[i].currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();

        await Gal.putImageBytes(pngBytes);
        await FirebaseAnalytics.instance.logEvent(name: 'sticker_generated');
        FirebaseService.log('EditorScreen._exportAll: sticker ${i + 1} saved');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('3 張貼圖已儲存至相簿！'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_export_failed',
      );
      await FirebaseAnalytics.instance
          .logEvent(name: 'sticker_export_failed');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('儲存失敗，請重試')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _regenerate() {
    ref
        .read(editorStateProvider(widget.imagePath).notifier)
        .regenerateTexts();
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editorStateProvider(widget.imagePath));
    final isLoading = state.status == EditorStatus.removingBackground ||
        state.status == EditorStatus.generatingTexts;
    final isReady = state.status == EditorStatus.ready;

    return Scaffold(
      appBar: AppBar(
        title: const Text('貼圖預覽'),
        actions: [
          if (isReady) ...[
            // 重新生成文字
            IconButton(
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '重新生成文字',
            ),
            // 儲存全部
            IconButton(
              onPressed: _isExporting ? null : _exportAll,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_rounded),
              tooltip: '儲存全部 3 張',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // ── 主體區：Loading / Error / 貼圖 PageView ──────────────
          Expanded(
            child: isLoading
                ? _LoadingView(status: state.status)
                : state.errorMessage != null
                    ? _ErrorView(message: state.errorMessage!)
                    : _StickerPageView(
                        state: state,
                        repaintKeys: _repaintKeys,
                        controller: _pageController,
                        onPageChanged: (i) =>
                            setState(() => _currentPage = i),
                      ),
          ),

          // ── 頁碼指示器 ───────────────────────────────────────────
          if (isReady) ...[
            const SizedBox(height: 8),
            _PageIndicator(currentPage: _currentPage),
            const SizedBox(height: 4),
          ],

          // ── 文字編輯面板 ─────────────────────────────────────────
          if (isReady)
            CaptionEditor(
              text: state.stickerTexts[_currentPage],
              stickerIndex: _currentPage,
              onTextChanged: (text) => ref
                  .read(editorStateProvider(widget.imagePath).notifier)
                  .updateStickerText(_currentPage, text),
            ),
        ],
      ),
    );
  }
}

// ─── 3 張貼圖 PageView ──────────────────────────────────────────────────

class _StickerPageView extends StatelessWidget {
  final EditorState state;
  final List<GlobalKey> repaintKeys;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  const _StickerPageView({
    required this.state,
    required this.repaintKeys,
    required this.controller,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      onPageChanged: onPageChanged,
      itemCount: 3,
      itemBuilder: (_, i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: _StickerCard(
            repaintKey: repaintKeys[i],
            subjectBytes: state.subjectBytes,
            text: state.stickerTexts[i],
            config: kStickerConfigs[i],
          ),
        );
      },
    );
  }
}

class _StickerCard extends StatelessWidget {
  final GlobalKey repaintKey;
  final dynamic subjectBytes;
  final String text;
  final StickerConfig config;

  const _StickerCard({
    required this.repaintKey,
    required this.subjectBytes,
    required this.text,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        // 白色底板模擬透明背景的預覽環境
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: RepaintBoundary(
          key: repaintKey,
          child: StickerCanvas(
            subjectBytes: subjectBytes,
            text: text,
            config: config,
          ),
        ),
      ),
    );
  }
}

// ─── 頁碼點點 ──────────────────────────────────────────────────────────

class _PageIndicator extends StatelessWidget {
  final int currentPage;

  const _PageIndicator({required this.currentPage});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: currentPage == i ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: currentPage == i ? color : color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

// ─── Loading / Error views ────────────────────────────────────────────

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
