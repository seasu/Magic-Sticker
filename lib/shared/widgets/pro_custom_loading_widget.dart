import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 全畫面 Loading 動畫：Pro 客製情緒 / 全客製模式專用
///
/// 黃金漸層背景 + 旋轉 ✨ + 描述文字，取代標準貓咪 Loading。
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
      duration: const Duration(seconds: 2),
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
            colors: [Color(0xFFFFF8E1), Color(0xFFFFF3CD)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 旋轉 ✨
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Transform.rotate(
                angle: _ctrl.value * 2 * pi,
                child: const Text('✨', style: TextStyle(fontSize: 56)),
              ),
            ),
            const SizedBox(height: 28),

            // 主標
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF8B6914),
              ),
            ),
            const SizedBox(height: 14),

            // 描述卡片
            if (desc != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFD700),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '「$desc」',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6B4F12),
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // 底部小字
            Text(
              '正在創作 · 約 15~25 秒',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: const Color(0xFFB8860B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
