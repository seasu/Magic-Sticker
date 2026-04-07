import 'dart:async';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_urls.dart';
import '../../../core/models/sticker_shape.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/share_code_service.dart';
import '../../../core/services/share_reward_service.dart';
import '../../../core/theme/app_colors.dart';

// ── A/B 測試文案 ─────────────────────────────────────────────────────────────

const _kShareLabelA = '分享比對圖';
const _kShareLabelB = '分享我的貼圖成果';

String _pickAbVariant() => Random().nextBool() ? 'A' : 'B';

// ── 尺寸常數 ─────────────────────────────────────────────────────────────────

const double _kDividerHeight = 28.0;
const double _kBrandFooterHeight = 56.0;

/// 儲存貼圖成功後顯示的全螢幕上下比對頁。
/// 上半：原圖；下半：貼圖（棋盤格背景）。
class StickerCompareScreen extends StatefulWidget {
  final String originalImagePath;
  final Uint8List stickerBytes;
  final StickerShape stickerShape;

  /// 來源頁：'editor' | 'replay'（用於 Analytics）
  final String from;

  /// 用於 ensureShareCode 的模板資訊
  final int? styleIndex;
  final List<String>? categoryIds;
  final String? customStyleDesc;
  final String? customEmotionDesc;

  const StickerCompareScreen({
    super.key,
    required this.originalImagePath,
    required this.stickerBytes,
    required this.stickerShape,
    this.from = 'editor',
    this.styleIndex,
    this.categoryIds,
    this.customStyleDesc,
    this.customEmotionDesc,
  });

  @override
  State<StickerCompareScreen> createState() => _StickerCompareScreenState();
}

class _StickerCompareScreenState extends State<StickerCompareScreen> {
  double _splitFraction = 0.5;
  bool _isSharing = false;
  final _repaintKey = GlobalKey();
  final _shareButtonKey = GlobalKey();

  late final String _abVariant;
  late final String _shapeLabel;

  late final TransformationController _topCtrl;
  late final TransformationController _bottomCtrl;

  @override
  void initState() {
    super.initState();
    _topCtrl = TransformationController();
    _bottomCtrl = TransformationController();
    _abVariant = _pickAbVariant();
    _shapeLabel =
        widget.stickerShape == StickerShape.circle ? 'circle' : 'square';

    // ── 漏斗 Event 1：進入比對頁 ───────────────────────────────────────────
    AnalyticsService.logCompareScreenViewed(
      from: widget.from,
      shape: _shapeLabel,
      abVariant: _abVariant,
    );
  }

  @override
  void dispose() {
    _topCtrl.dispose();
    _bottomCtrl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      // ── 同步執行：CF 取挑戰碼 + 截圖（並行，不互相等待）──────────────────
      final codeFuture = ShareCodeService.ensureShareCode(
        presetStyleIndex: widget.styleIndex,
        presetCategoryIds: widget.categoryIds,
        customStyleDesc: widget.customStyleDesc,
        customEmotionDesc: widget.customEmotionDesc,
      ).timeout(const Duration(seconds: 8));

      // 截圖（本機操作，快）
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      // 等待挑戰碼（或降級）
      ShareCodeResult? codeResult;
      try {
        codeResult = await codeFuture;
      } catch (_) {
        codeResult = null; // 靜默降級：分享文案用 fallback URL
      }

      final shareUrl = codeResult?.deepLink ?? AppUrls.download;
      final hasLink = codeResult != null;

      // 自動複製 deep link 到剪貼簿，方便用戶分享到 LINE 後貼上
      // （LINE 透過系統 Share Sheet 分享圖片時不傳遞文字，剪貼簿是唯一可靠方案）
      await Clipboard.setData(ClipboardData(text: shareUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('連結已複製，分享到 LINE 後貼上即可 ✨'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // ── 漏斗 Event 2：分享按鈕被點擊 ─────────────────────────────────────
      unawaited(AnalyticsService.logShareCompareTapped(
        from: widget.from,
        shape: _shapeLabel,
        abVariant: _abVariant,
        hasLink: hasLink,
      ));

      // 寫暫存檔
      final tmp = File(
        '${(await getTemporaryDirectory()).path}'
        '/compare_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tmp.writeAsBytes(byteData.buffer.asUint8List());

      // 分享
      // iOS：XFile 必須帶 mimeType，否則 UIActivityViewController 無法識別
      // 檔案類型，導致分享失敗。
      // iOS：sharePositionOrigin 必須傳入分享按鈕的 Rect，否則 iPad 上
      // UIActivityViewController popover 無法定位，導致 PlatformException。
      final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.fromLTWH(0, 0, 1, 1);
      final result = await Share.shareXFiles(
        [XFile(tmp.path, mimeType: 'image/png')],
        text: '我用 Magic Sticker 做了這個！試試同款 👇\n$shareUrl',
        sharePositionOrigin: origin,
      );

      if (await tmp.exists()) await tmp.delete();

      if (result.status == ShareResultStatus.dismissed) {
        // ── 漏斗 Event 3：取消分享 ──────────────────────────────────────────
        unawaited(
          AnalyticsService.logShareCompareDismissed(reason: 'cancelled'),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('分享已取消'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        // ── 分享完成：背景請求獎勵 ───────────────────────────────────────────
        unawaited(_tryGrantReward());
      }
    } catch (e, stack) {
      FirebaseService.recordError(e, stack, reason: '_share failed');
      unawaited(
        AnalyticsService.logShareCompareDismissed(reason: 'failed'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('分享失敗，請再試一次'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  /// 背景請求分享獎勵（fire-and-forget）；
  /// 若成功且今日首次，顯示 +1 點 Toast。
  Future<void> _tryGrantReward() async {
    try {
      final reward = await ShareRewardService.grantReward(
        sessionHadCompareView: true, // 進入此畫面即代表已看過比對頁
      );
      if (reward.granted && mounted) {
        // ── 漏斗 Event 4：獎勵入帳 ────────────────────────────────────────
        unawaited(AnalyticsService.logShareRewardGranted());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 +1 點分享獎勵！'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // 獎勵失敗不影響主流程，靜默忽略
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
                    final topHeight = (totalHeight * _splitFraction)
                        .clamp(80.0, totalHeight - 80.0);
                    final bottomHeight = totalHeight -
                        topHeight -
                        _kDividerHeight -
                        _kBrandFooterHeight;

                    return Column(
                      children: [
                        // ── 上半：原圖 ──────────────────────────────────
                        SizedBox(
                          height: topHeight,
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const ColoredBox(color: Color(0xFF1C1C1E)),
                                  GestureDetector(
                                    onDoubleTap: () =>
                                        _topCtrl.value = Matrix4.identity(),
                                    child: InteractiveViewer(
                                      transformationController: _topCtrl,
                                      minScale: 0.3,
                                      maxScale: 5.0,
                                      boundaryMargin:
                                          EdgeInsets.all(double.infinity),
                                      clipBehavior: Clip.none,
                                      child: Image.file(
                                        File(widget.originalImagePath),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  const Positioned(
                                    top: 10,
                                    left: 10,
                                    child: IgnorePointer(
                                      child: _Chip(label: '原圖'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                  width: 56,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.gradient,
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFFFD297B)
                                            .withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ── 下半：貼圖 ──────────────────────────────────
                        SizedBox(
                          height: bottomHeight,
                          width: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const ColoredBox(color: Color(0xFFF8F8F8)),
                                  GestureDetector(
                                    onDoubleTap: () =>
                                        _bottomCtrl.value = Matrix4.identity(),
                                    child: InteractiveViewer(
                                      transformationController: _bottomCtrl,
                                      minScale: 0.3,
                                      maxScale: 5.0,
                                      boundaryMargin:
                                          EdgeInsets.all(double.infinity),
                                      clipBehavior: Clip.none,
                                      child: widget.stickerShape ==
                                              StickerShape.circle
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
                                    ),
                                  ),
                                  const Positioned(
                                    top: 10,
                                    left: 10,
                                    child: IgnorePointer(
                                      child: _Chip(label: '貼圖', gradient: true),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ── 品牌 Footer（含 CTA，隨截圖一起分享）────────
                        const _BrandFooter(),
                      ],
                    );
                  },
                ),
              ),
            ),

            // ── 底部按鈕列 ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: [
                  // 分享按鈕（A/B 文案）
                  Expanded(
                    child: OutlinedButton.icon(
                      key: _shareButtonKey,
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
                      label: Text(
                        _abVariant == 'A' ? _kShareLabelA : _kShareLabelB,
                      ),
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

// ── _BrandFooter ──────────────────────────────────────────────────────────────

class _BrandFooter extends StatelessWidget {
  const _BrandFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kBrandFooterHeight,
      decoration: const BoxDecoration(gradient: AppColors.gradient),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset('assets/images/app_icon_small.png', width: 24, height: 24),
          ),
          const SizedBox(width: 8),
          const Text(
            'Magic Sticker',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          const Text(
            'AI 生成 LINE 貼圖 · 免費下載 →',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool gradient;

  const _Chip({required this.label, this.gradient = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: gradient ? AppColors.gradient : null,
        color: gradient ? null : Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: gradient
            ? null
            : Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 1,
              ),
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
