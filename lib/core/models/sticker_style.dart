/// 貼圖產圖風格選項
///
/// 每種風格會改變傳給 Gemini 的 prompt，生成不同美術風格的貼圖。
enum StickerStyle {
  chibi('Q版卡通', '🎨'),
  popArt('普普風', '🟡'),
  pixel('像素風', '🕹️'),
  sketch('素描', '✏️'),
  watercolor('水彩', '🎨'),
  photo('寫實風', '📸');

  const StickerStyle(this.label, this.emoji);

  final String label;
  final String emoji;

  /// 插入 prompt 的角色外觀描述段落
  String get characterDesc => switch (this) {
        StickerStyle.chibi =>
          '根據照片人物繪製卡通 Q 版臉型（可愛 Chibi 風格）\n'
              '  * 大閃亮眼睛、小鼻子、圓潤臉頰\n'
              '  * 乾淨平面插畫、粗黑色描邊、非寫實風格\n'
              '  * 臉部與上半身自然填滿圓形',
        StickerStyle.popArt =>
          '根據照片人物繪製普普藝術人物肖像\n'
              '  * 大膽簡化的臉部特徵、鮮豔高對比色彩\n'
              '  * 粗黑色描邊、平塗色塊、Ben-Day 網點陰影\n'
              '  * Andy Warhol / Roy Lichtenstein 美術風格',
        StickerStyle.pixel =>
          '根據照片人物繪製像素藝術角色\n'
              '  * 可見的粗像素（≥4 px 格）、限制色盤（≤16 色）\n'
              '  * 簡單大眼睛、方塊圓潤形狀\n'
              '  * 無反鋸齒；任天堂 / SNES 遊戲像素風',
        StickerStyle.sketch =>
          '根據照片人物繪製鉛筆素描肖像\n'
              '  * 手繪線條捕捉照片人物神韻\n'
              '  * 交叉線條表現深度與陰影、粗糙有力的筆觸\n'
              '  * 單色或深褐色調',
        StickerStyle.watercolor =>
          '根據照片人物繪製水彩畫肖像\n'
              '  * 柔和圓潤的臉部、邊緣暈染的溫柔色調\n'
              '  * 透明疊色、隱約可見的紙張紋理\n'
              '  * 夢幻可愛的水彩質感',
        StickerStyle.photo =>
          '根據照片人物繪製寫實肖像\n'
              '  * 忠實還原外型，自然膚色與清晰五官\n'
              '  * 乾淨、光線充足的肖像構圖\n'
              '  * 平滑邊緣、色彩飽和、專業大頭照品質\n'
              '  * 人物從背景中提取——優先透明背景',
      };

  /// 插入 prompt 末尾的風格指令句
  String get promptSuffix => switch (this) {
        StickerStyle.chibi => 'LINE Friends / Chiikawa 畫質水準。',
        StickerStyle.popArt =>
          '普普藝術風格——粗黑色描邊、鮮豔平塗色彩、Ben-Day 網點陰影、無漸層。'
              'Andy Warhol / Roy Lichtenstein 美術風格。',
        StickerStyle.pixel =>
          '復古 8-bit 像素風格——可見的大像素（≥4 px 格）、限制色盤（≤16 色）、無反鋸齒。'
              '任天堂 / SNES 像素風。',
        StickerStyle.sketch =>
          '鉛筆素描／手繪風格——單色或深褐色調、可見的鉛筆筆觸與交叉線條陰影、粗糙且富有表現力的線條品質。',
        StickerStyle.watercolor =>
          '柔和水彩風格——邊緣暈染的溫柔色塊、透明疊色、隱約紙張紋理。可愛夢幻的水彩質感。',
        StickerStyle.photo =>
          '寫實風格——自然色彩、清晰五官、專業肖像打光。高保真度；忠實呈現真人外貌。',
      };
}
