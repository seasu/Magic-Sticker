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

/// Web 服務根網域（不含尾斜線）。
///
/// 設定方式（CI / 本機）：
///   flutter build apk --dart-define=DOMAIN_BASE=https://magic-sticker-8eaf4.web.app
///
/// 預設值為 Firebase Hosting 自動配發的網址。
/// 若日後綁定自訂網域，只需在 GitHub Variables 設定 DOMAIN_BASE 即可。
const kDomainBase = String.fromEnvironment(
  'DOMAIN_BASE',
  defaultValue: 'https://magic-sticker-8eaf4.web.app',
);
