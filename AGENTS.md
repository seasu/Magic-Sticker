# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

Magic Sticker (package: `magic_sticker`) — an AI-powered LINE sticker generator Flutter app (Android only, no iOS directory) with Firebase Cloud Functions backend. See `CLAUDE.md` for full development rules and `PRD.md` for product specs.

| Component | Path | Language |
|---|---|---|
| Flutter App | `/workspace` | Dart |
| Cloud Functions | `/workspace/functions/` | TypeScript (Node 22) |

### SDK locations

- **Flutter SDK**: `/opt/flutter/bin/flutter` (v3.29.1, Dart 3.7.0)
- **Android SDK**: `/home/ubuntu/android-sdk`
- **Node.js 22** + npm, **Java 21**: pre-installed on the VM
- All on `PATH` via `~/.bashrc`.

### Key commands

| Task | Command |
|---|---|
| Install deps | `flutter pub get` |
| Lint | `dart analyze --fatal-infos` (must pass before every commit) |
| Tests | `flutter test` |
| Build debug APK | `flutter build apk --debug` |
| Build release APK | `flutter build apk --release` (needs signing config) |
| Cloud Functions deps | `cd functions && npm install` |
| Cloud Functions type-check | `cd functions && npx tsc --noEmit` |

### Gotchas

- **CLAUDE.md rules**: Before any commit, you must (1) bump `version` in `pubspec.yaml` and (2) update `PRD.md`. See `CLAUDE.md` for the full checklist.
- **Web mode does not work**: The app depends on Firebase, AdMob, and ML Kit native plugins. Running via `flutter run -d chrome` will show a blank screen. Only Android builds are meaningful.
- **Firebase config has placeholders**: `lib/core/services/firebase_options.dart` contains `YOUR_ANDROID_API_KEY` placeholders. The app handles Firebase init failures gracefully, so builds and tests still pass.
- **First Android build is slow** (~10-12 min) because Gradle downloads dependencies and the Android SDK auto-installs NDK/CMake/platform packages. Subsequent builds are much faster.
- **No signing key in dev**: Release builds fall back to debug signing when `android/key.properties` is absent. CI uses GitHub Secrets for release signing.
- **ESLint not configured**: `functions/` ESLint config is not committed; `npm run lint` will fail. TypeScript compilation (`npx tsc --noEmit`) works fine.
