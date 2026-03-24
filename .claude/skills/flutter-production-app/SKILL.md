# Flutter Production App — Architecture & CI/CD Guideline
> Version: 1.0 | Last updated: 2026-03-24
> **AI-Agnostic:** This document is readable by Claude, ChatGPT, Gemini, Copilot, and any LLM-based coding assistant.

---

## 0. How to Use This Guideline

Copy this file to `.claude/skills/flutter-production-app/SKILL.md` (or any `skills/` folder recognised by your AI tool) in a new project. The AI will use it as a reference for all architectural decisions.

**This guideline covers:**
1. Project structure & naming conventions
2. Flutter architecture (Clean Architecture + Riverpod)
3. Firebase & Cloud Functions integration
4. Security patterns (no API keys in binary)
5. Monetization (IAP + Ads)
6. CI/CD pipeline (GitHub Actions — Android + iOS)
7. Commit & versioning conventions
8. Pre-commit mandatory checklist

---

## 1. Project Bootstrap

### 1.1 Create the Flutter Project
```bash
flutter create --org com.<company> <app_id>
# Example: flutter create --org com.acme my_app
```

### 1.2 Minimum SDK Targets
| Platform | Minimum | Notes |
|----------|---------|-------|
| Android  | API 26 (Android 8.0) | `minSdkVersion 26` in `build.gradle` |
| iOS      | 15.0 | `IPHONEOS_DEPLOYMENT_TARGET = 15.0` |

### 1.3 Version Format
```
major.minor.patch+build   →   e.g. 1.0.0+1
```
- **build number** auto-increments on every CI build
- **patch** increments for bug fixes
- **minor** increments for new features
- **major** increments for breaking UX changes or full rewrites

---

## 2. Directory Structure

```
lib/
├── main.dart                   # Entry: Firebase init + global Crashlytics traps
├── app.dart                    # MaterialApp.router + GoRouter config
├── firebase_options.dart       # Auto-generated (FlutterFire CLI)
│
├── core/
│   ├── constants/
│   │   └── build_config.dart   # Env flags, feature toggles
│   ├── models/                 # Shared domain models
│   ├── services/
│   │   ├── firebase_service.dart    # Crashlytics + Analytics init
│   │   ├── auth_service.dart        # Anonymous + Google + Apple
│   │   ├── ads_service.dart         # AdMob rewarded ads
│   │   ├── analytics_service.dart   # Event tracking helpers
│   │   └── log_service.dart         # Local structured logging
│   ├── theme/
│   │   ├── app_colors.dart
│   │   └── app_theme.dart
│   └── utils/
│       └── image_processor.dart     # Resize before API transmission
│
├── native/
│   └── method_channel.dart     # Platform bridge (Android/iOS)
│
├── features/                   # Feature-first folder structure
│   ├── <feature_name>/
│   │   ├── models/
│   │   ├── providers/          # Riverpod providers
│   │   ├── screens/
│   │   └── widgets/
│   └── ...
│
└── shared/
    └── widgets/                # Reusable UI components

android/
├── app/
│   ├── build.gradle
│   ├── google-services.json    # Firebase Android config
│   └── proguard-rules.pro

ios/
└── Runner/
    ├── Info.plist
    └── GoogleService-Info.plist  # Firebase iOS config

functions/                      # Firebase Cloud Functions
├── src/
│   └── index.ts                # TypeScript source
├── package.json
└── tsconfig.json

public/                         # Firebase Hosting
├── index.html
└── .well-known/
    └── assetlinks.json         # Android App Links

assets/
├── images/
└── fonts/

.github/
└── workflows/
    ├── main_build.yml          # Full build on version tag
    ├── pr_check.yml            # PR validation (version + analyze + test)
    └── ios_bootstrap.yml       # iOS cert/profile setup helper
```

---

## 3. Flutter Architecture

### 3.1 Layers
```
UI Layer          (Screens, Widgets)
    ↓  reads state / calls actions
Business Layer    (Riverpod Providers / Notifiers)
    ↓  calls service methods
Service Layer     (Auth, API, Ads, Analytics)
    ↓  talks to
Data Layer        (Firestore, MethodChannel, REST APIs)
```

### 3.2 State Management — Riverpod Patterns
```dart
// Read-only async data
final userCreditsProvider = FutureProvider<int>((ref) async {
  return FirebaseFirestore.instance...;
});

// Mutable local state
final editorStateProvider = NotifierProvider<EditorNotifier, EditorState>(
  EditorNotifier.new,
);

// Auth stream
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});
```

**Rules:**
- One provider per concern; avoid mega-providers
- Use `ref.watch` in build, `ref.read` in event handlers
- Use `AsyncValue` for all async data (`when(data:, loading:, error:)`)

### 3.3 Routing — go_router
```dart
final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (ctx, state) => const HomeScreen()),
  GoRoute(path: '/editor', builder: (ctx, state) => const EditorScreen()),
  // Deep link
  GoRoute(path: '/c/:code', builder: (ctx, state) =>
      ChallengeScreen(code: state.pathParameters['code']!)),
]);
```

**Deep Link Setup:**
- Android: `android/app/src/main/AndroidManifest.xml` intent-filter + `assetlinks.json`
- iOS: `Info.plist` Associated Domains + Universal Links

---

## 4. Firebase Integration

### 4.1 Initialisation (main.dart)
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Global Crashlytics traps — NEVER OMIT
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const ProviderScope(child: MyApp()));
}
```

### 4.2 Firestore Schema Convention
```
users/{uid}
  ├── credits: int            ← write-protected (Cloud Function only)
  ├── isAnonymous: bool
  ├── createdAt: Timestamp
  └── creditHistory/{id}      ← sub-collection, read-only for client
      ├── type: "earned" | "spent" | "refund"
      ├── amount: int
      └── createdAt: Timestamp
```

**Security Rules Pattern:**
```javascript
// users/{uid}: owner-only read/write
match /users/{uid} {
  allow read, update: if request.auth.uid == uid
      && !request.resource.data.keys().hasAny(['credits', 'updatedAt']);
  allow create: if request.auth.uid == uid;

  // Sub-collections written only by Cloud Functions
  match /creditHistory/{id} {
    allow read: if request.auth.uid == uid;
    allow write: if false;
  }
}
```

### 4.3 Firebase App Check
- Android: Play Integrity provider
- iOS: DeviceCheck provider
- Enable in Cloud Functions: `enforceAppCheck: true`

---

## 5. Cloud Functions (TypeScript)

### 5.1 Structure
```typescript
// functions/src/index.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

const GEMINI_KEY = defineSecret("GEMINI_API_KEY");

export const myFunction = onCall(
  { region: "asia-east1", secrets: [GEMINI_KEY] },
  async (request) => {
    // 1. Verify auth
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");

    // 2. Validate input
    // 3. Atomic Firestore transaction
    // 4. Call external API
    // 5. Return result
  }
);
```

### 5.2 Mandatory Patterns for Cloud Functions

| Pattern | Reason |
|---------|--------|
| Verify `request.auth` at the top | Prevent unauthenticated calls |
| Atomic Firestore transactions for credit deduction | No orphaned charges |
| Store API keys in Firebase Secret Manager (never in code) | Security |
| Return structured errors with `HttpsError` | Client can handle gracefully |
| Idempotency key for purchases | Prevent duplicate fulfillment |

### 5.3 Secret Manager Setup
```bash
# Create secrets (run once)
gcloud secrets create GEMINI_API_KEY --replication-policy="automatic"
printf '%s' "YOUR_KEY" | gcloud secrets versions add GEMINI_API_KEY --data-file=-

# Reference in functions/src/index.ts
const API_KEY = defineSecret("GEMINI_API_KEY");
```

> **CI Note:** The Firebase SA (`firebase-adminsdk-fbsvc@<project>.iam.gserviceaccount.com`)
> must have `roles/secretmanager.admin` in GCP IAM for the CI to provision secrets automatically.

---

## 6. Security Checklist

- [ ] **No API keys in Flutter binary** — all sensitive keys in Firebase Secret Manager
- [ ] **Firebase App Check** enabled for all Cloud Functions
- [ ] **Firestore Security Rules** enforce user isolation; critical fields write-protected
- [ ] **Purchase verification** calls official Google Play / App Store APIs server-side
- [ ] **Image resize** before sending to AI API (≤768px or project-specific limit)
- [ ] All `MethodChannel` calls wrapped in `try-catch` with Crashlytics logging
- [ ] OAuth2 (not password) for Apple / Google auth

---

## 7. Monetization Patterns

### 7.1 Credit System
```
User arrives  → grant N free credits
Login         → grant bonus credits
Watch ad      → +1 credit (daily cap)
IAP bundle    → +N credits (server-verified)
Use feature   → −1 credit (atomic, with refund on error)
```

### 7.2 IAP (in_app_purchase)
- **Consumable:** Credit bundles (multi-buy allowed)
- **Non-consumable:** Pro unlock (buy once, restore on reinstall)
- Verify purchases in Cloud Function (never trust client alone)
- Fulfillment is idempotent (check `purchases/{orderId}` before granting)

### 7.3 AdMob Rewarded Ads
```dart
// ads_service.dart
Future<void> showRewardedAd({required VoidCallback onRewarded}) async {
  await RewardedAd.load(adUnitId: _adUnitId, ...);
  _ad.show(onUserEarnedReward: (_, __) => onRewarded());
}
```

---

## 8. Image Processing

**Rule:** Always resize images on the Flutter side before sending to any API.

```dart
// core/utils/image_processor.dart
static Future<Uint8List> resizeForApi(Uint8List bytes, {int maxSize = 768}) async {
  final decoded = img.decodeImage(bytes)!;
  final resized = (decoded.width > maxSize || decoded.height > maxSize)
      ? img.copyResize(decoded, width: maxSize)
      : decoded;
  return Uint8List.fromList(img.encodePng(resized));
}
```

---

## 9. CI/CD Pipeline (GitHub Actions)

### 9.1 Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Firebase Admin SA (JSON) |
| `FIREBASE_PROJECT_ID` | GCP/Firebase project ID |
| `ANDROID_KEYSTORE_BASE64` | Release keystore (base64) |
| `ANDROID_KEY_ALIAS` | Keystore alias |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `GOOGLE_PLAY_JSON` | Google Play Developer API SA (JSON) |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer UUID |
| `APP_STORE_CONNECT_API_KEY` | App Store Connect .p8 private key |
| `IOS_DISTRIBUTION_CERT_BASE64` | Distribution certificate (base64 p12) |
| `IOS_CERT_PASSWORD` | Certificate password |
| `IOS_PROVISIONING_PROFILE_BASE64` | Provisioning profile (base64) |
| `GEMINI_API_KEY` | Gemini API key (provisioned to Secret Manager) |

### 9.2 Trigger Strategy
```yaml
on:
  push:
    branches: [main]          # → dart-analyze only (fast feedback)
    tags: ['v*']              # → full build + release + deploy
  workflow_dispatch:          # → manual trigger with optional release notes
```

### 9.3 Job Dependency Graph
```
dart-analyze (every main push)
    |
    ├── android-build ──→ release (GitHub Release + APK)
    │                └──→ firebase-distribute (App Distribution)
    │                └──→ play-store-deploy (Google Play internal)
    │
    ├── ios-build ──────→ testflight-upload
    │
    └── deploy-functions ──→ smoke-test (POST /getConfig retry loop)
         └──→ deploy-hosting (Firebase Hosting + assetlinks.json)
```

### 9.4 Android Build Step
```yaml
- name: Build Android Release
  run: |
    flutter build apk --release \
      --dart-define=FLAVOR=production
    flutter build appbundle --release \
      --dart-define=FLAVOR=production

- name: Sign APK
  run: |
    echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > /tmp/keystore.jks
    $ANDROID_BUILD_TOOLS/apksigner sign \
      --ks /tmp/keystore.jks \
      --ks-pass pass:$ANDROID_STORE_PASSWORD \
      --ks-key-alias $ANDROID_KEY_ALIAS \
      build/app/outputs/flutter-apk/app-release.apk
```

### 9.5 iOS Build Step (macOS runner)
```yaml
- name: Import signing assets
  run: |
    echo "$IOS_DISTRIBUTION_CERT_BASE64" | base64 -d > /tmp/cert.p12
    security create-keychain -p "" build.keychain
    security import /tmp/cert.p12 -k build.keychain -P "$IOS_CERT_PASSWORD" -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "" build.keychain

    echo "$IOS_PROVISIONING_PROFILE_BASE64" | base64 -d > /tmp/profile.mobileprovision
    mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
    cp /tmp/profile.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/

- name: Build IPA
  run: |
    flutter build ipa --release \
      --export-options-plist=ios/ExportOptions.plist

- name: Upload to TestFlight
  run: |
    xcrun altool --upload-app \
      --type ios --file build/ios/ipa/*.ipa \
      --apiKey $APP_STORE_CONNECT_KEY_ID \
      --apiIssuer $APP_STORE_CONNECT_ISSUER_ID
```

### 9.6 Provision Firebase Secrets Step
```yaml
- name: Grant Secret Manager Admin to Firebase SA (idempotent)
  run: |
    echo '${{ secrets.FIREBASE_SERVICE_ACCOUNT_JSON }}' > /tmp/sa.json
    gcloud auth activate-service-account --key-file=/tmp/sa.json
    gcloud config set project ${{ secrets.FIREBASE_PROJECT_ID }}
    SA_EMAIL=$(python3 -c "import json; print(json.load(open('/tmp/sa.json'))['client_email'])")
    gcloud projects add-iam-policy-binding ${{ secrets.FIREBASE_PROJECT_ID }} \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/secretmanager.admin" --condition=None \
      2>&1 && echo "✅ granted" || echo "⚠️ grant failed — add manually in GCP IAM"
    rm -f /tmp/sa.json

- name: Provision Firebase Secrets
  run: |
    # ... (provision_secret function: create if missing, update if value set)
```

### 9.7 Smoke Test Pattern
```bash
# After deploying Cloud Functions, verify with retry loop
MAX=5; DELAY=10
for i in $(seq 1 $MAX); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "https://asia-east1-${PROJECT}.cloudfunctions.net/getConfig" \
    -H "Content-Type: application/json" -d '{"data":{}}')
  [ "$STATUS" -eq 200 ] && echo "✅ smoke test passed" && exit 0
  echo "Attempt $i/$MAX failed (HTTP $STATUS), retrying in ${DELAY}s..."
  sleep $DELAY
done
echo "❌ smoke test failed after $MAX attempts" && exit 1
```

### 9.8 PR Check Workflow (pr_check.yml)
```yaml
jobs:
  version-check:
    # Fail if pubspec.yaml version not incremented vs last git tag
  analyze-and-test:
    run: |
      dart analyze --fatal-infos
      flutter test
  functions-check:
    run: cd functions && npm ci && npm run build
```

---

## 10. Commit & Versioning Conventions

### 10.1 Commit Format
```
[type] vX.Y.Z+BUILD: short description

Types:
  feat    — new feature
  fix     — bug fix
  refactor— code change without behaviour change
  chore   — dependency/config update
  ci      — CI/CD change
  docs    — documentation only
```

Example:
```
[feat] v1.2.0+45: Add rewarded ad support for daily credit bonus
[fix]  v1.2.1+46: Fix Crashlytics null error on first launch (iOS)
[ci]   v1.2.1+47: Add Secret Manager IAM grant step to main_build.yml
```

### 10.2 Mandatory Pre-Commit Checklist
- [ ] `pubspec.yaml` version incremented
- [ ] `PRD.md` (or equivalent spec doc) updated to reflect changes
- [ ] New `MethodChannel` calls have `try-catch` + Crashlytics logging
- [ ] Images resized before API transmission
- [ ] New widgets use `const` constructors where applicable
- [ ] No hardcoded API keys or tokens in any file

### 10.3 Release via Git Tag
```bash
git tag v1.2.0+45
git push origin v1.2.0+45
# → triggers main_build.yml full pipeline
```

---

## 11. Error Handling Standard

```dart
// ALL platform/API calls must follow this pattern:
Future<Result> doSomething() async {
  try {
    FirebaseCrashlytics.instance.log('doSomething: start');
    final result = await _someNativeCall();
    FirebaseCrashlytics.instance.log('doSomething: success');
    return Result.success(result);
  } on PlatformException catch (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack);
    return Result.failure(e.message ?? 'Platform error');
  } catch (e, stack) {
    FirebaseCrashlytics.instance.recordError(e, stack);
    return Result.failure('Unexpected error');
  }
}
```

---

## 12. Analytics Event Naming

```dart
// Consistent event naming: snake_case, verb_noun
analytics.logEvent('sticker_generated', {'style': style, 'credits_spent': 1});
analytics.logEvent('ad_watched', {'placement': 'editor_bottom'});
analytics.logEvent('iap_purchased', {'product_id': productId});
analytics.logEvent('share_link_created', {'channel': 'challenge'});
analytics.logEvent('error_shown', {'code': errorCode});
```

---

## 13. Key Dependencies (pubspec.yaml Reference)

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Firebase
  firebase_core: ^3.x.x
  firebase_auth: ^5.x.x
  cloud_firestore: ^5.x.x
  firebase_crashlytics: ^4.x.x
  firebase_analytics: ^11.x.x
  firebase_app_check: ^0.3.x

  # State & Routing
  flutter_riverpod: ^2.x.x
  riverpod_annotation: ^2.x.x
  go_router: ^14.x.x

  # Image
  image_picker: ^1.x.x
  image: ^4.x.x
  gal: ^2.x.x                    # Save to album (Android + iOS)
  cached_network_image: ^3.x.x

  # Monetization
  google_mobile_ads: ^5.x.x
  in_app_purchase: ^3.x.x

  # Auth
  google_sign_in: ^6.x.x
  sign_in_with_apple: ^6.x.x

  # Utilities
  flutter_animate: ^4.x.x
  gap: ^3.x.x
  permission_handler: ^11.x.x
  app_links: ^6.x.x              # Deep links

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.x.x
  build_runner: ^2.x.x
  riverpod_generator: ^2.x.x
```

---

## 14. GCP / Firebase One-Time Setup Checklist

When starting a new project, complete these steps once:

- [ ] `firebase init` (Firestore, Functions, Hosting, Crashlytics, Analytics, App Check)
- [ ] `flutterfire configure` → generate `firebase_options.dart`
- [ ] Enable Google Sign-In + Apple Sign-In in Firebase Auth console
- [ ] Create Firestore in production mode → deploy `firestore.rules` + `firestore.indexes.json`
- [ ] Enable Firebase App Check (Play Integrity + DeviceCheck)
- [ ] Create secrets in Secret Manager:
  - `GEMINI_API_KEY` (or equivalent AI API key)
  - `APP_STORE_KEY_ID`, `APP_STORE_ISSUER_ID`, `APP_STORE_PRIVATE_KEY`
- [ ] Grant `firebase-adminsdk-fbsvc@<project>.iam.gserviceaccount.com` the role `roles/secretmanager.admin`
- [ ] Configure AdMob app ID in `AndroidManifest.xml` + `Info.plist`
- [ ] Add SHA-1 + SHA-256 fingerprints to Firebase project (Android)
- [ ] Add `assetlinks.json` to Firebase Hosting for Android App Links
- [ ] Set up GitHub Secrets (see Section 9.1)
- [ ] Create `ios/ExportOptions.plist` with distribution settings

---

## 15. Folder Naming Conventions

| Type | Convention | Example |
|------|-----------|---------|
| Dart files | snake_case | `auth_service.dart` |
| Classes | PascalCase | `AuthService` |
| Providers | camelCase + `Provider` | `authStateProvider` |
| Widgets | PascalCase | `CreditBadge` |
| Routes | kebab-case strings | `'/sticker-history'` |
| Asset images | snake_case | `style_preview_01.png` |
| Firestore fields | camelCase | `createdAt`, `isAnonymous` |

---

## 16. Recommended Development Workflow

```
1. Pull latest main
2. Create feature branch: feat/short-description
3. Implement changes
4. flutter pub get (if deps changed)
5. dart analyze && flutter test
6. Increment pubspec.yaml version
7. Update PRD.md / spec doc
8. Commit with [type] vX.Y.Z+N: description
9. Push → open PR
10. PR check must pass (version-check + analyze + test)
11. Merge to main
12. When ready to release: git tag vX.Y.Z+N && git push origin vX.Y.Z+N
```

---

*This guideline was extracted from the Magic Sticker project (production Flutter app with 370+ builds, Android + iOS, Firebase + Gemini AI integration). Apply it to bootstrap new Flutter production apps with the same patterns.*
