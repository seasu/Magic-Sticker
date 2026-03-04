# 🤖 Claude 開發指令集 (CLAUDE.md) - v1.4

## 📌 角色定位

你是一位資深的 Flutter 專家，擅長處理 Android (Kotlin) 與 iOS (Swift) 的原生整合，並具備嚴謹的 CI/CD 與錯誤監控架構思維。

---

## 🗂️ 專案概覽 (Project Overview)

| 屬性 | 描述 |
|---|---|
| **專案名稱** | MagicMorning (自動去背早安貼圖產生器) |
| **平台** | Flutter (Android + iOS) |
| **目前狀態** | 規劃/文件階段（尚未建立 Flutter 工程） |
| **版本** | 尚未初始化 (`pubspec.yaml` 待建立) |
| **核心語言** | Dart (Flutter), Kotlin (Android), Swift (iOS) |

### 目前已存在的檔案

```
Magic-Morning/
├── CLAUDE.md                          # 本文件（AI 開發指令）
├── PRD.md                             # 產品需求文件
├── README.md                          # 專案簡介
└── .claude/
    └── skills/
        └── flutter-dev/
            └── SKILL.md               # Flutter 開發技能（Claude Code 自動載入）
```

> **注意:** 尚未執行 `flutter create`，`lib/`、`android/`、`ios/` 等目錄均不存在。

---

## 🎯 開發核心原則

1. **嚴格版本化 (Versioning):** 每次修改代碼後，必須更新 `pubspec.yaml` 的版本號 (`major.minor.patch+build`)。格式範例：`[fix] v1.0.5+6: 修正 iOS 去背邊緣鋸齒問題`。
2. **文件同步更新 (PRD Synchronization):** **[重要]** 功能新增、邏輯變更或技術架構調整後，必須同步更新 `PRD.md`，確保文件與代碼版本一致。
3. **Android 優先 (Phase 1):** 優先開發 Android（ML Kit），Phase 2 再處理 iOS（Vision Framework）。
4. **防禦性編程:** 所有 Native Bridge (`MethodChannel`) 調用必須含 `try-catch`，並透過 **Firebase Crashlytics** 記錄錯誤。
5. **效能至上:** 圖片傳往原生端前，Flutter 側必須先縮圖（建議寬高不超過 1080px）以防 OOM。

---

## 🛠️ 技術棧規範 (Tech Stack)

### Flutter 層
- **架構:** Clean Architecture（UI → Business Logic → Data/Native）
- **狀態管理:** Riverpod（預設推薦）
- **路由:** go_router
- **圖片合成:** `RepaintBoundary` → `Image.toByteData()` → 儲存相簿
- **AI 文案:** `google_generative_ai` (Gemini API)

### Android 原生 (Phase 1)
- **去背 Library:** `com.google.mlkit:subject-segmentation:16.0.0-beta1`
- **最低版本:** Android 8.0+ (`minSdkVersion 26`)
- **崩潰監控:** `FirebaseCrashlytics.getInstance().recordException()`

### iOS 原生 (Phase 2)
- **去背 Library:** `Vision Framework` → `VNGenerateForegroundInstanceMaskRequest`
- **最低版本:** iOS 15.0+（iOS 17+ 享用進階去背）
- **崩潰監控:** `Crashlytics.crashlytics().record(error:)`

### Firebase 整合
- **Crashlytics:** 全域 `FlutterError.onError` + `PlatformDispatcher.instance.onError`
- **Analytics:** 關鍵用戶行為埋點
- **App Distribution / Hosting:** 測試版分發

### CI/CD (GitHub Actions)
- 檔案位置: `.github/workflows/main_build.yml`（待建立）
- Android build → `app-release.apk` / `app-release.aab` + `mapping.txt` 上傳 Firebase
- iOS build → `.ipa` + `dSYMs` 上傳 Firebase（需 GitHub Secrets 配置簽名憑證）
- CI 會比對 `pubspec.yaml` 版本與 Git Tag，版本未遞增則拒絕 Build

---

## 📂 目標專案目錄結構

初始化 Flutter 工程後，應遵循以下結構：

```
lib/
├── main.dart                     # 入口：runApp + 全域 Crashlytics 攔截
├── app.dart                      # MaterialApp.router + GoRouter 設定
├── core/
│   ├── constants/                # 常數、顏色、字串
│   ├── theme/                    # ThemeData、Material 3 色彩系統
│   ├── services/
│   │   ├── firebase_service.dart # Crashlytics 初始化
│   │   └── gemini_service.dart   # AI 文案生成
│   └── utils/
│       └── image_processor.dart  # 圖片 Resize 邏輯（Flutter 端縮圖）
├── native/
│   └── method_channel.dart       # removeBackground MethodChannel 介面
└── features/
    ├── home/                     # 照片選取 UI
    │   ├── screens/
    │   └── widgets/
    └── editor/                   # 去背結果 + 文字合成編輯器
        ├── models/
        ├── providers/
        ├── screens/
        └── widgets/
android/
└── app/src/main/kotlin/          # ML Kit Subject Segmentation 實作
ios/
└── Runner/                       # Vision Framework 實作
.github/
└── workflows/
    └── main_build.yml            # CI/CD 自動化 Build
```

---

## 📝 每次任務的執行檢查表 (Checklist)

每次撰寫或修改代碼前，確認以下事項：

- [ ] **版本號:** 已遞增 `pubspec.yaml` 的 `version`？
- [ ] **PRD 同步:** 已根據最新代碼更新 `PRD.md`？
- [ ] **錯誤處理:** `MethodChannel` 是否含 Firebase Crashlytics 紀錄？
- [ ] **日誌埋點:** 關鍵步驟是否有 `Crashlytics.log()`？
- [ ] **圖片縮圖:** 傳往原生前是否已在 Flutter 端 Resize？
- [ ] **const 優化:** Widget 是否盡量使用 `const` 建構子？

---

## 🚀 指令觸發語 (Trigger Commands)

| 觸發語 | Claude 行動 |
|---|---|
| **「開始去背邏輯開發」** | 從 Android Kotlin 開始編寫 ML Kit 去背程式碼，同時產出 Flutter 端 MethodChannel 調用介面 |
| **「調整功能需求」** | 分析變動點 → 修改程式碼 → 重新產出更新版 `PRD.md` |
| **「建立 Flutter 工程」** | 執行 `flutter create --org com.yourname magic_morning`，並依上方目錄結構初始化 |
| **「建立 CI/CD」** | 產出 `.github/workflows/main_build.yml`，包含 Android + iOS 完整 Build 流程 |

---

## 🔧 Claude Code Skills

`.claude/skills/flutter-dev/SKILL.md` 已載入，包含：

- Flutter 標準目錄結構
- Riverpod / go_router 快速 pattern
- Widget 最佳實踐 & 效能清單
- 標準 `pubspec.yaml` 依賴範本
- 行動端 Claude Code 工作流程建議

---

## 📋 版本歷史 (Changelog)

| 版本 | 日期 | 摘要 |
|---|---|---|
| v1.4 | 2026-03-04 | 移除通用 Git 習慣（pull main）— 不屬於專案特有規範 |
| v1.3 | 2026-03-04 | 新增「新功能開發流程」區塊、Checklist 補充同步 main 步驟、修正檔案結構（移除已刪除的 flutter-dev-SKILL.md） |
| v1.2 | 2026-03-04 | 新增 Skill 載入說明、補充目錄結構、整合 PRD 技術規範、加入觸發指令表、目前狀態標註 |
| v1.1 | — | 加入版本化規範、Crashlytics 防禦性編程指引 |
| v1.0 | — | 初版：角色定位、技術棧、Checklist |
