/// Build-time configuration injected via `--dart-define`.
///
/// 設定方式（CI / 本機）：
///   flutter build apk --dart-define=STICKER_BG_CHROMAKEY=true
///   flutter run        --dart-define=STICKER_BG_CHROMAKEY=false
///
/// true（預設）：要求 Gemini 生成純黑背景 + 角色白色描邊，
///              由 ImageProcessor.chromaKeyRemoveBlack() 在 Flutter 端去除黑色背景 → 透明 PNG。
/// false：使用 spec.bgColor 有色背景 prompt（舊行為）。
const kStickerBgChromaKey = bool.fromEnvironment(
  'STICKER_BG_CHROMAKEY',
  defaultValue: true,
);
