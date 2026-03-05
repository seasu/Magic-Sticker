這是一份針對 Android 與 iOS 雙平台 完整規劃的 PRD（產品需求文件）。這份文件已將 Phase 2: iOS 視覺能力 整合進度，並嚴格遵守你要求的 版本號規範、Firebase 追蹤與 GitHub Actions 自動化。
📝 產品需求文件 (PRD) - MagicMorning App
| 屬性 | 描述 |
|---|---|
| 專案名稱 | MagicMorning (自動去背 LINE 貼圖產生器) |
| 版本號規範 | SemVer (Major.Minor.Patch+Build) |
| 開發平台 | Flutter (Android & iOS) |
| 監控系統 | Firebase Crashlytics & Analytics |
| 核心技術 | ML Kit (Android) / Vision Framework (iOS) |

1. 產品願景
讓使用者只需「選取照片」，即可透過 AI 自動提取主體、移除背景，並自動產出 3 張帶有可愛小圖示與短文字的 LINE 貼圖，一鍵儲存後直接加入 LINE 分享。

2. 核心功能模組 (Feature Matrix)

2.1 影像處理 (去背核心)
 * Android (Phase 1): * 整合 com.google.mlkit:subject-segmentation。
   * 支援人像、寵物、物件的多主體偵測。
 * iOS (Phase 2): * 整合 Apple Vision Framework 中的 VNGenerateForegroundInstanceMaskRequest (iOS 17+ 推薦)。
   * 利用 Apple 晶片的神經網路引擎 (Neural Engine) 進行毫米級邊緣處理。
 * 共通規範: * 原生端處理完畢後，需回傳 Uint8List (PNG 格式，透明背景) 給 Flutter 層。
   * 傳入原生層前，Flutter 需先進行 Image Resize (建議寬高不超過 1080px) 以防止記憶體溢出 (OOM)。

2.2 LINE 貼圖自動產生器 (核心新功能)

去背完成後，Flutter 端自動合成 3 張獨立貼圖，每張規格如下：

**尺寸規格**
| 項目 | 規格 |
|---|---|
| 畫布尺寸 | 740×640 px（LINE 高解析標準） |
| 輸出格式 | PNG（透明背景） |
| 單檔上限 | 1 MB |

**短文字由 Gemini AI 依照照片內容自動生成**

去背前，先將原圖（Base64）傳入 Gemini API，一次取回 3 組符合情境的短文字，再套入 3 張貼圖。

**Gemini Prompt 規範**
```
你是 LINE 貼圖文字設計師。
請根據這張照片的內容與氛圍，產出 3 組繁體中文短文字，格式如下：
- 每組 2–6 字，口語化、有趣、適合貼圖
- 風格：正向、可愛、日常
- 禁止重複
- 僅回傳 JSON 陣列，例如：["好棒喔！", "讚啦", "超可愛✨"]
```

**Gemini API 呼叫規格**
| 項目 | 規格 |
|---|---|
| 模型 | `gemini-1.5-flash`（速度優先） |
| 輸入 | 原圖 Base64（resize 至 512px 以節省 token） |
| 輸出 | JSON 陣列，長度固定為 3 |
| Fallback | API 失敗或解析錯誤時，使用預設值 `["好棒！", "讚喔", "超可愛✨"]` |
| 逾時 | 10 秒，超時直接走 Fallback |

**3 張貼圖的差異化設計**

| 貼圖編號 | 短文字來源 | 小圖示位置 | 配色風格 |
|---|---|---|---|
| Sticker 1 | Gemini 回傳第 1 組 | 右上角 | 暖橘 / 陽光黃 |
| Sticker 2 | Gemini 回傳第 2 組 | 左下角 | 粉紅 / 珊瑚色 |
| Sticker 3 | Gemini 回傳第 3 組 | 右下角 | 薄荷綠 / 天空藍 |

**自動疊加的可愛小圖示（預設資源集）**
- 愛心 ❤️、星星 ⭐、閃光 ✨、花朵 🌸、笑臉 😊
- 圖示以 Flutter `assets/sticker_icons/` 預置 SVG/PNG 資源提供
- 每張貼圖從圖示集隨機挑選 1–2 個，疊加於主體邊緣

**合成層順序 (Stack)**
```
底層：透明背景（無填色）
  ↓
主體層：去背後的人像/物件（置中，留邊 20px）
  ↓
裝飾層：可愛小圖示（依設計定位）
  ↓
文字層：短文字（圓角氣泡框，字型 18–24sp，粗體）
```

**匯出流程**
1. 使用 `RepaintBoundary` → `toImage()` → `toByteData(format: ImageByteFormat.png)` 依序產出 3 張
2. 透過 `image_gallery_saver` 或 `gal` 套件儲存至相簿
3. 顯示「已儲存 3 張貼圖」成功提示，引導使用者前往 LINE → 貼圖 → 我的貼圖 → 新增

2.3 AI 文字生成流程（核心）

```
選圖 → resize to 512px → Base64
  → Gemini API (gemini-1.5-flash, multimodal)
  → 解析 JSON ["文字A", "文字B", "文字C"]
  → 注入 3 張貼圖 Canvas
  → 若失敗 → Fallback ["好棒！", "讚喔", "超可愛✨"]
```

**實作位置**：`core/services/gemini_service.dart`
```dart
// 方法簽名
Future<List<String>> generateStickerTexts(Uint8List imageBytes);
```

2.4 文字與樣式客製（選配）
 * 使用者可在編輯器中修改 AI 產出的短文字（點擊文字泡泡即可編輯）
 * 字型：Google Fonts 動態載入（預設：Noto Sans TC 或 Nunito）
 * 「重新生成文字」按鈕：重新呼叫 Gemini API 取得新的 3 組文字

3. 開發規範 (Strict Engineering Standards)

3.1 嚴格版本號管理 (Versioning)
 * 規則: 每次修改代碼（不論大小），必須更新 pubspec.yaml 的版本。
 * CI 檢查: GitHub Action 會比對 pubspec.yaml 版本與 Git Tag，若版本未增加則拒絕 Build。
 * Commit 範例: [feat] v1.1.0+2: 新增 LINE 貼圖自動產生（3 張）功能。

3.2 錯誤回報 (Firebase Crashlytics)
 * 全域攔截: 必須實作 FlutterError.onError 與 PlatformDispatcher.instance.onError。
 * 原生追蹤: * Android 使用 FirebaseCrashlytics.getInstance().recordException()。
   * iOS 使用 Crashlytics.crashlytics().record(error:)。
 * 日誌埋點: 在 MethodChannel 呼叫開始與結束時，手動調用 Crashlytics.log() 記錄執行參數。
 * 貼圖合成埋點: 每張貼圖產生成功/失敗均記錄 Analytics event（`sticker_generated` / `sticker_export_failed`）。
 * Gemini 埋點: 記錄 `ai_text_generated`（成功）與 `ai_text_fallback`（走 Fallback），方便監控 API 成功率。

4. GitHub Actions 自動化 Build 規範
專案必須包含 .github/workflows/main_build.yml，定義以下流程：
 * Android Build: * 環境: ubuntu-latest。
   * 產物: app-release.apk, app-release.aab。
   * 混淆: 自動上傳 mapping.txt 至 Firebase 以還原當機堆疊。
 * iOS Build: * 環境: macos-latest。
   * 產物: .ipa (需配置 GitHub Secrets 中的 P12 證書與 Provisioning Profile)。
   * 符號: 自動上傳 dSYMs 至 Firebase。
 * Firebase App Distribution: 每次 push 至 main，自動分發 APK 給 testers 群組。

5. 專案目錄結構建議
lib/
├── core/
│   ├── services/
│   │   ├── firebase_service.dart   # Crashlytics 初始化
│   │   └── gemini_service.dart     # AI 文案生成（選配）
│   └── utils/
│       └── image_processor.dart    # 圖片 Resize 邏輯
├── native/
│   └── method_channel.dart         # 定義 removeBackground 介面
├── features/
│   ├── home/                       # 照片選取介面
│   └── editor/                     # 去背結果 + 貼圖編輯器
│       ├── models/
│       │   └── sticker_config.dart # 貼圖配置（文字、圖示、配色）
│       ├── providers/
│       │   └── sticker_provider.dart
│       ├── screens/
│       │   └── sticker_preview_screen.dart
│       └── widgets/
│           ├── sticker_canvas.dart  # 單張貼圖合成畫布
│           └── sticker_icon_overlay.dart # 可愛圖示疊加元件
assets/
└── sticker_icons/                  # 預置可愛小圖示（SVG/PNG）
    ├── heart.svg
    ├── star.svg
    ├── sparkle.svg
    ├── flower.svg
    └── smile.svg
android/                            # Kotlin ML Kit 實作
ios/                                # Swift Vision Framework 實作

6. 驗收標準 (Acceptance Criteria)
 * 效能: 去背 + 3 張貼圖合成總時間 < 3 秒（高階手機）。
 * 貼圖規格: 輸出 PNG 透明背景，尺寸 740×640px，單檔 < 1MB。
 * 穩定性: Firebase Crashlytics 的 Crash-free users 需高於 99%。
 * 相容性: Android 8.0+ / iOS 15.0+ (iOS 17+ 享用進階去背)。
 * 可用性: 3 張貼圖一次儲存至相簿，系統提示引導加入 LINE。

7. 版本歷史 (Changelog)
| 版本 | 日期 | 摘要 |
|---|---|---|
| v1.2 | 2026-03-05 | 短文字改為 Gemini API 依照照片內容自動生成（3 組），加入 Fallback 機制、重新生成按鈕、`ai_text_generated` Analytics 埋點 |
| v1.1 | 2026-03-05 | 核心功能調整：由早安貼圖改為自動產出 3 張 LINE 貼圖，新增可愛圖示疊加、短文字（OK/好喔！/很棒）、740×640px 規格輸出 |
| v1.0 | 2026-03-04 | 初版：去背核心、AI 早安文案、GitHub Actions CI/CD |
