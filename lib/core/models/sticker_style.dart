/// 貼圖產圖風格選項
///
/// 每種風格會改變傳給 Gemini 的 prompt，生成不同美術風格的貼圖。
enum StickerStyle {
  chibi('Q版卡通', '🎨'),
  popArt('普普風', '🟡'),
  pixel('像素風', '🕹️'),
  sketch('素描', '✏️'),
  watercolor('水彩', '🎨');

  const StickerStyle(this.label, this.emoji);

  final String label;
  final String emoji;

  /// 插入 prompt 的角色外觀描述段落
  String get characterDesc => switch (this) {
        StickerStyle.chibi =>
          'Cartoon chibi-style face of the person (cute Q-version)\n'
              '  * Big sparkly eyes, small nose, chubby cheeks\n'
              '  * Clean flat illustration, thick black outlines, no photo-realism\n'
              '  * Face and upper body fill the circle naturally',
        StickerStyle.popArt =>
          'Pop Art portrait inspired by the person in the photo\n'
              '  * Bold simplified face features, vivid high-contrast colors\n'
              '  * Thick black outlines, flat colored areas, Ben-Day dot shading\n'
              '  * Andy Warhol / Roy Lichtenstein aesthetic',
        StickerStyle.pixel =>
          'Pixel art sprite of the person\'s face\n'
              '  * Chunky pixels visible (≥4 px grid), limited palette (≤16 colors)\n'
              '  * Simple large eyes, blocky rounded shapes\n'
              '  * No anti-aliasing; Nintendo / SNES game sprite aesthetic',
        StickerStyle.sketch =>
          'Pencil sketch portrait of the person\n'
              '  * Hand-drawn lines capturing the likeness from the photo\n'
              '  * Crosshatching for depth and shading, rough expressive strokes\n'
              '  * Monochrome or sepia tones',
        StickerStyle.watercolor =>
          'Watercolor painting portrait of the person\n'
              '  * Soft rounded face with gentle color washes that bleed at edges\n'
              '  * Translucent layered colors, slight paper texture visible\n'
              '  * Dreamy, cute watercolor quality',
      };

  /// 插入 prompt 末尾的風格指令句
  String get promptSuffix => switch (this) {
        StickerStyle.chibi => 'LINE Friends / Chiikawa quality.',
        StickerStyle.popArt =>
          'Pop Art style — bold black outlines, vivid flat colors, Ben-Day dot '
              'shading, no gradients. Andy Warhol / Roy Lichtenstein aesthetic.',
        StickerStyle.pixel =>
          'Retro 8-bit pixel art style — large visible pixels (≥4 px grid), '
              'limited palette (≤16 colors), no anti-aliasing. '
              'Nintendo / SNES sprite aesthetic.',
        StickerStyle.sketch =>
          'Pencil sketch / hand-drawn style — monochrome or sepia tones, '
              'visible pencil strokes and crosshatching for shadows, '
              'rough and expressive line quality.',
        StickerStyle.watercolor =>
          'Soft watercolor painting style — gentle color washes bleeding at edges, '
              'translucent layered colors, slight paper texture. '
              'Cute and dreamy watercolor quality.',
      };
}
