/// 貼圖產圖風格選項
///
/// 每種風格會改變傳給 Gemini 的 prompt，生成不同美術風格的貼圖。
enum StickerStyle {
  chibi('Q版卡通', '🎨'),
  popArt('普普風', '🟡'),
  pixel('像素風', '🕹️'),
  sketch('素描', '✏️'),
  watercolor('水彩', '🎨'),
  webtoon('韓系插畫風', '🖼️'),
  celshade('動漫賽璐璐風', '✨'),
  pixar3d('3D 皮克斯風', '🎬'),
  plush('毛絨玩偶風', '🧸'),
  yuruDoodle('ゆるい塗鴉', '🖊️'),
  showaManga('昭和漫畫', '📰'),
  claymation('黏土捏塑', '🫧');

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
          '根據照片人物繪製普普藝術風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n'
              '  * 大膽簡化的臉部特徵、鮮豔高對比色彩\n'
              '  * 平塗色塊、Ben-Day 網點陰影、無黑色描邊\n'
              '  * Andy Warhol / Roy Lichtenstein 美術風格\n'
              '  * 完整身形不被任何畫布邊緣截斷',
        StickerStyle.pixel =>
          '根據照片人物繪製像素藝術角色\n'
              '  * 整張圖以 32×32 格子構成再放大，每格至少 4px，強制可見方塊感\n'
              '  * 限制色盤（≤16 色）、無任何反鋸齒或漸層\n'
              '  * 所有邊緣皆為直角硬邊；任天堂 / SNES 遊戲像素風',
        StickerStyle.sketch =>
          '根據照片人物繪製鉛筆素描風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n'
              '  * 手繪線條捕捉照片人物神韻\n'
              '  * 交叉線條表現深度與陰影、粗糙有力的筆觸\n'
              '  * 單色或深褐色調\n'
              '  * 完整身形不被任何畫布邊緣截斷',
        StickerStyle.watercolor =>
          '根據照片人物繪製水彩風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n'
              '  * 柔和圓潤的臉部、邊緣暈染的溫柔色調\n'
              '  * 透明疊色、隱約可見的紙張紋理\n'
              '  * 夢幻可愛的水彩質感\n'
              '  * 完整身形不被任何畫布邊緣截斷',
        StickerStyle.webtoon =>
          '根據照片人物繪製韓式 Webtoon 扁平插畫\n'
              '  * 乾淨圓滑的黑色輪廓線、均勻平塗色彩\n'
              '  * 明亮柔和的大眼睛、Q 版可愛比例\n'
              '  * 接近 LINE Friends / NAVER Webtoon 的插畫風格',
        StickerStyle.celshade =>
          '根據照片人物繪製日系動漫賽璐璐厚塗插畫\n'
              '  * 清晰的厚黑邊輪廓線、硬邊陰影分層（2–3 階，無漸層邊緣）\n'
              '  * 飽和鮮豔色彩、強烈光澤反光點\n'
              '  * 日本動漫賽璐璐賽璐璐作畫風格',
        StickerStyle.pixar3d =>
          '根據照片人物繪製 Pixar / Disney 3D 渲染風格角色\n'
              '  * 精緻的 subsurface scattering 膚色、圓潤卡通比例\n'
              '  * 柔和的環境光遮蔽（AO）、明亮的鏡面高光點\n'
              '  * Pixar 動畫電影的 3D 渲染質感',
        StickerStyle.plush =>
          '根據照片人物繪製毛絨布偶玩具風格角色（2D 插畫貼圖，非照片）\n'
              '  * 模擬短絨毛質感（細小筆觸表現毛流）\n'
              '  * 圓胖可愛比例、柔和邊緣輪廓\n'
              '  * 豐富的深淺毛色層次，外觀質感像手工布偶\n'
              '  * 角色為 2D 平面插圖，無任何攝影背景、地板、環境陰影或真實場景元素',
        StickerStyle.yuruDoodle =>
          '根據照片人物繪製「ゆるい（鬆散可愛）」塗鴉風格的完整 Q 版角色（頭頂至腳底完整呈現）\n'
              '  * 刻意歪扭的不均勻輪廓線、五官大小不對稱（一大一小的眼睛等）\n'
              '  * 粗糙肥厚的黑色手繪線條、面部簡化但身體四肢完整可見\n'
              '  * 整體散漫自然、像小孩亂畫卻帶有獨特個性與溫度\n'
              '  * 完整身形不被任何畫布邊緣截斷',
        StickerStyle.showaManga =>
          '根據照片人物繪製昭和復古漫畫風格的完整 Q 版卡通人物（非肖像、非半身，頭頂至腳底完整呈現）\n'
              '  * 黑白為主（可有限度使用 1–2 種強調色）、手繪網點（スクリーントーン）陰影\n'
              '  * 粗獷有力的黑色輪廓線、誇張的速度線與動感線條僅集中於角色周邊，不延伸至畫布邊緣\n'
              '  * 大而明亮的 60 年代漫畫風眼睛、誇張表情框線\n'
              '  * 完整身形不被任何畫布邊緣截斷',
        StickerStyle.claymation =>
          '根據照片人物繪製黏土捏塑風格的完整 Q 版角色（2D 插畫貼圖，非照片，頭頂至腳底完整呈現）\n'
              '  * 模擬手工黏土材質——可見輕微指痕、不均勻的表面起伏\n'
              '  * 圓潤厚重的造型比例、柔和的邊緣與輪廓\n'
              '  * 豐富的黏土色澤高光與陰影，外觀像手工捏製的玩偶\n'
              '  * 角色為 2D 平面插圖，無任何攝影背景、地板或真實場景元素\n'
              '  * 完整身形不被任何畫布邊緣截斷',
      };

  /// 插入 prompt 末尾的風格指令句
  String get promptSuffix => switch (this) {
        StickerStyle.chibi => 'LINE Friends / Chiikawa 畫質水準。',
        StickerStyle.popArt =>
          '普普藝術風格——鮮豔平塗色彩、Ben-Day 網點陰影、無漸層、無黑色描邊。'
              'Andy Warhol / Roy Lichtenstein 美術風格。',
        StickerStyle.pixel =>
          '復古 8-bit 像素風格——整張圖如同在 32×32 畫布上繪製再放大 8 倍，'
              '每個像素必須明顯呈現方塊感、限制色盤（≤16 色）、絕對無反鋸齒或漸層、所有邊緣皆為直角方塊。'
              '任天堂 / SNES 像素風。',
        StickerStyle.sketch =>
          '鉛筆素描／手繪風格——單色或深褐色調、可見的鉛筆筆觸與交叉線條陰影、粗糙且富有表現力的線條品質。',
        StickerStyle.watercolor =>
          '柔和水彩風格——邊緣暈染的溫柔色塊、透明疊色、隱約紙張紋理。可愛夢幻的水彩質感。',
        StickerStyle.webtoon =>
          '韓系 Webtoon 插畫風格——乾淨流暢線條、均勻平塗、明亮眼睛。'
              'LINE Friends / NAVER Webtoon 畫質水準。',
        StickerStyle.celshade =>
          '日系動漫賽璐璐風格——粗黑輪廓線、硬邊分層陰影（無漸層邊緣）、飽和鮮豔色彩、明顯的高光反光點。',
        StickerStyle.pixar3d =>
          'Pixar 3D 動畫風格——圓潤立體卡通造型、精緻打光（主光源＋補光）、subsurface 膚色、鏡面高光。'
              '3D 渲染質感。',
        StickerStyle.plush =>
          '毛絨玩偶插畫風格——以 2D 插圖形式模擬短絨毛材質、圓胖可愛比例、柔和邊緣輪廓、豐富毛色深淺層次。'
              '角色為純 2D 插圖貼圖，無攝影背景、無地面倒影、無環境投影，角色本體以外區域維持純技術背景色。',
        StickerStyle.yuruDoodle =>
          '日本「下手上手（heta-uma）」ゆるキャラ 風格——刻意不精緻的歪扭線條與不對稱五官，散漫卻充滿個性，像地方吉祥物的手繪質感。',
        StickerStyle.showaManga =>
          '昭和復古漫畫風格——黑白手繪、スクリーントーン 網點陰影、粗獷輪廓線、60 年代日本漫畫質感。手塚治虫 / 藤子不二雄 風格。',
        StickerStyle.claymation =>
          '黏土捏塑插畫風格——以 2D 插圖形式模擬手工黏土材質、圓潤厚重比例、可見指痕與不均勻表面起伏。'
              'Aardman（笑笑羊）/ 定格動畫黏土玩偶風格。',
      };
}
