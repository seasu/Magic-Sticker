import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cat_loading_widget.dart';

// ─── Pro 香檳金色系常數 ─────────────────────────────────────────────────────────
const _kProTitle    = Color(0xFF7B5215); // 深暖棕主標
const _kProCardBg   = Color(0xFFC9A84C); // 香檳金邊框 / 強調色
const _kProCardText = Color(0xFF7B5215); // 卡片文字
const _kProSubtitle = Color(0xFFFF5864); // 底部小字（品牌色橋接）

/// 全畫面 Loading 動畫：Pro 客製情緒 / 全客製模式專用
///
/// 香檳金漸層背景 + 奔跑金色貓咪 + 描述文字，取代標準貓咪 Loading。
class ProCustomLoadingWidget extends StatefulWidget {
  /// 客製情緒描述（非 null 時主標顯示「AI 正在詮釋您的專屬情緒」）
  final String? emotionDesc;

  /// 客製風格描述（僅 styleDesc 有值且 emotionDesc 為 null 時顯示）
  final String? styleDesc;

  const ProCustomLoadingWidget({
    super.key,
    this.emotionDesc,
    this.styleDesc,
  });

  @override
  State<ProCustomLoadingWidget> createState() => _ProCustomLoadingWidgetState();
}

class _ProCustomLoadingWidgetState extends State<ProCustomLoadingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desc = widget.emotionDesc ?? widget.styleDesc;
    final title = widget.emotionDesc != null
        ? 'AI 正在詮釋您的專屬情緒'
        : 'AI 正在生成您的專屬貼圖';

    return SizedBox.expand(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFAFAF5), Color(0xFFF5EDD8)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 主標
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _kProTitle,
              ),
            ),
            const SizedBox(height: 16),

            // 香檳金貓咪動畫（取代旋轉 ✨）
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(
                size: const Size(220, 160),
                painter: RunningCatPainter(
                  t: _ctrl.value,
                  colors: CatColorScheme.proChampagne,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 跳動三點（香檳金）
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => BouncingDots(
                t: _ctrl.value,
                colors: CatColorScheme.proChampagne,
              ),
            ),
            const SizedBox(height: 28),

            // 描述卡片
            if (desc != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _kProCardBg.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _kProCardBg,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '「$desc」',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _kProCardText,
                  ),
                ),
              ),

            if (desc != null) const SizedBox(height: 24),

            // 底部小字（品牌色橋接）
            Text(
              '正在創作 · 約 15~25 秒',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: _kProSubtitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
