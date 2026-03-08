import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 貼圖文字字型選項
///
/// 全部使用支援完整繁體中文字集的字型：
///   - 本地 bundle 字型（assets/fonts/）：OpenHuninn、Cubic11、Iansui
///   - Google Fonts 動態下載：Noto Serif TC（需網路，首次載入後快取）
///   - 系統字型：黑體（裝置預設粗黑體）
///
/// 原 Ma Shan Zheng / ZCOOL KuaiLe / Long Cang 均為簡體字型，
/// 碰到繁體字會缺字退回系統字體，故全部替換。
class StickerFont {
  final String label;

  const StickerFont({required this.label});

  /// 將字型套用至 [base] TextStyle 並回傳新 TextStyle
  TextStyle apply(TextStyle base) => switch (label) {
        // jf 開放粉圓 2.1 — 台灣最流行 TC 圓體，親切溫暖
        '粉圓' => base.copyWith(fontFamily: 'OpenHuninn'),

        // Noto Serif TC ExtraBold — Google 官方 TC 明體，典雅端正
        // 動態下載，支援完整繁體字集（CNS11643）
        '宋體' => GoogleFonts.notoSerifTc(
            textStyle: base.copyWith(fontWeight: FontWeight.w800),
          ),

        // Cubic 11 — 像素方塊圓角體，活潑俏皮感
        '活潑' => base.copyWith(fontFamily: 'Cubic11'),

        // 芫荽（Iansui）— 手寫楷書風，自然流暢
        '手寫' => base.copyWith(fontFamily: 'Iansui'),

        // 黑體 — 使用裝置系統粗黑體（fontWeight 由 base 決定）
        _ => base,
      };
}

/// 全域字型清單（index 對應 EditorState.fontIndices）
const kStickerFonts = <StickerFont>[
  StickerFont(label: '黑體'), // 0 — 系統粗黑體
  StickerFont(label: '粉圓'), // 1 — jf 開放粉圓（TC bundle）
  StickerFont(label: '宋體'), // 2 — Noto Serif TC（TC Google Fonts）
  StickerFont(label: '活潑'), // 3 — Cubic 11（TC bundle）
  StickerFont(label: '手寫'), // 4 — 芫荽 Iansui（TC bundle）
];
