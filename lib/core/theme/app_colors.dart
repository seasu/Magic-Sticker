import 'package:flutter/material.dart';

/// 全域顏色常數與品牌漸層
///
/// 所有元件一律從這裡取色，禁止寫 hardcode Color() 數值。
abstract class AppColors {
  // ── 品牌漸層（CTA 按鈕、完成畫面 icon） ─────────────────────────────────
  static const gradient = LinearGradient(
    colors: [Color(0xFFFD297B), Color(0xFFFF5864), Color(0xFFFF655B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── 語意色（滑動動作） ─────────────────────────────────────────────────
  static const like = Color(0xFF4CD964);   // 綠 — 保留 ❤️
  static const nope = Color(0xFFFF3B30);   // 紅 — 跳過 ✕

  // ── 中性色 ────────────────────────────────────────────────────────────
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF8F9FA);
  static const textPrimary = Color(0xFF21262E);
  static const textSecondary = Color(0xFF71768A);
  static const divider = Color(0xFFE8E8E8);
}
