/// Build-time configuration injected via `--dart-define`.
///
/// 設定方式（CI / 本機）：
///   flutter build apk --dart-define=STICKER_BG_TRANSPARENT=true
///   flutter run        --dart-define=STICKER_BG_TRANSPARENT=false
///
/// GitHub Actions：在 Repository Variables 設定 `STICKER_BG_TRANSPARENT`，
/// 預設值為 `true`（透明背景）。
const kStickerBgTransparent = bool.fromEnvironment(
  'STICKER_BG_TRANSPARENT',
  defaultValue: true,
);
