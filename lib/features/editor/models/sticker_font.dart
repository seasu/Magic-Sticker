import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 貼圖文字字型選項
///
/// 字型套用至 StickerCanvas 底部的 outline 文字。
/// 須選用支援繁體中文的 Google Fonts 字型。
class StickerFont {
  final String label;   // 顯示在 UI 選擇器的名稱

  const StickerFont({required this.label});

  /// 將字型套用至 [base] TextStyle 並回傳新 TextStyle
  TextStyle apply(TextStyle base) => switch (label) {
        '圓體' => GoogleFonts.notoSansTc(textStyle: base),
        '書法' => GoogleFonts.maShanZheng(
            textStyle: base.copyWith(fontWeight: FontWeight.w700)),
        '可愛' => GoogleFonts.zcoolKuaiLe(
            textStyle: base.copyWith(fontWeight: FontWeight.w400)),
        '手寫' => GoogleFonts.longCang(
            textStyle: base.copyWith(fontWeight: FontWeight.w400)),
        _ => base, // '黑體' — 使用系統預設粗黑體
      };
}

/// 全域字型清單（index 對應 EditorState.fontIndices）
const kStickerFonts = <StickerFont>[
  StickerFont(label: '黑體'),    // 0 — 預設
  StickerFont(label: '圓體'),    // 1 — Noto Sans TC
  StickerFont(label: '書法'),    // 2 — Ma Shan Zheng（毛筆）
  StickerFont(label: '可愛'),    // 3 — ZCOOL KuaiLe（圓潤活潑）
  StickerFont(label: '手寫'),    // 4 — Long Cang（手寫行書）
];
