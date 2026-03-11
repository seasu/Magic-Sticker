# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Magic Sticker (package: `magic_sticker`) — an AI-powered LINE sticker generator Flutter app (Android only, no iOS directory). See `CLAUDE.md` for full development rules and `PRD.md` for product specs.

### SDK locations

- **Flutter SDK**: `/opt/flutter/bin/flutter` (v3.29.1, Dart 3.7.0)
- **Android SDK**: `/home/ubuntu/android-sdk`
- Both are on `PATH` via `~/.bashrc`.

### Key commands

| Task | Command |
|---|---|
| Install deps | `flutter pub get` |
| Lint | `dart analyze` (use `--fatal-infos` to match CI strictness) |
| Tests | `flutter test` |
| Build debug APK | `flutter build apk --debug` |
| Build release APK | `flutter build apk --release` (needs signing config) |
| Cloud Functions deps | `cd functions && npm install` |
| Cloud Functions type-check | `cd functions && npx tsc --noEmit` |

### Gotchas

- **`dart analyze --fatal-infos`** exits non-zero due to 33 pre-existing info-level hints (`prefer_const_constructors` etc.). The CI workflow (`.github/workflows/pr_check.yml`) uses `--fatal-infos`, so new code must not introduce additional infos. Running `dart analyze` without `--fatal-infos` is fine for quick checks.
- **Web mode does not work**: The app depends on Firebase, AdMob, and ML Kit native plugins. Running via `flutter run -d chrome` will show a blank screen. Only Android builds are meaningful.
- **Firebase config has placeholders**: `lib/core/services/firebase_options.dart` contains `YOUR_ANDROID_API_KEY` placeholders. The app handles Firebase init failures gracefully, so builds and tests still pass.
- **First Android build is slow** (~10-12 min) because Gradle downloads dependencies and the Android SDK auto-installs missing platform/build-tool versions. Subsequent builds are much faster.
- **No signing key in dev**: Release builds fall back to debug signing when `android/key.properties` is absent. CI uses GitHub Secrets for release signing.
- **CLAUDE.md rules**: Before any commit, you must (1) bump `version` in `pubspec.yaml` and (2) update `PRD.md`. See `CLAUDE.md` for the full checklist.
