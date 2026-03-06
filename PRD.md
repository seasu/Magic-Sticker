📝 產品需求文件 (PRD) - MagicMorning App
| 屬性 | 描述 |
|---|---|
| 專案名稱 | MagicMorning (自動去背 LINE 貼圖產生器) |
| 版本號規範 | SemVer (Major.Minor.Patch+Build) |
| 開發平台 | Flutter (Android & iOS) |
| 監控系統 | Firebase Crashlytics & Analytics |
| 核心技術 | ML Kit (Android) / Vision Framework (iOS) |

1. 產品願景
讓使用者只需「選取照片」，即可透過 Gemini AI 自動產出 **8 張**圓形卡通 LINE 貼圖組，涵蓋 8 種日常情感表達，每張貼圖包含根據照片人臉繪製的 Q 版頭像、彩色圓形背景，以及情感標語，一鍵儲存後直接上架至 LINE Creators Market。

2. 核心功能模組 (Feature Matrix)

2.1 影像處理 (去背核心)
 * Android (Phase 1): * 整合 com.google.mlkit:subject-segmentation。
   * 支援人像、寵物、物件的多主體偵測。
 * iOS (Phase 2): * 整合 Apple Vision Framework 中的 VNGenerateForegroundInstanceMaskRequest (iOS 17+ 推薦)。
   * 利用 Apple 晶片的神經網路引擎 (Neural Engine) 進行毫米級邊緣處理。
 * 共通規範: * 原生端處理完畢後，需回傳 Uint8List (PNG 格式，透明背景) 給 Flutter 層。
   * 傳入原生層前，Flutter 需先進行 Image Resize (建議寬高不超過 1080px) 以防止記憶體溢出 (OOM)。

2.2 LINE 貼圖自動產生器（v1.9+ 全新架構）

**新架構（v1.9+）：直接讓 Gemini 生成完整圓形貼圖，跳過 ML Kit 去背步驟**

一次生成 8 張獨立貼圖，每張規格如下：

**尺寸規格（LINE Creators Market 官方規格）**
| 項目 | 規格 | 說明 |
|---|---|---|
| 輸出尺寸 | **370×320 px** | LINE Creators Market 標準貼圖尺寸（最大值） |
| 畫布比例 | 37 : 32（740×640 @2x master） | 渲染用的邏輯畫布尺寸，輸出時依比例縮至 370×320 |
| 輸出格式 | **PNG（透明背景）** | 貼圖背景須透明，才能貼在任何顏色的對話框上 |
| 單檔上限 | **1 MB** | 超過時記錄 `sticker_export_oversized` log |
| 一組數量 | **8 張**（符合 LINE Creators Market 最低上架門檻） | App 一次產出完整 8 張 |
| 主圖 (main.png) | 240×240 px | 上架時另外提供（本 App 不自動產生） |
| 分頁縮圖 (tab.png) | 96×74 px | 上架時另外提供（本 App 不自動產生） |

**8 張貼圖情感主題（固定組合）**
| # | 情感 | 中文標語 | 圓形背景色 |
|---|---|---|---|
| 1 | 打招呼 | 哈囉！ | 暖橘 #F4A261 |
| 2 | 讚美 | 太棒了！ | 天空藍 #74C0FC |
| 3 | 驚訝 | 真的嗎？ | 金黃 #FFD43B |
| 4 | 尷尬 | 尷尬了... | 粉嫩 #FFB3C6 |
| 5 | 生氣 | 哼！ | 深紅 #FF6B6B |
| 6 | 開心 | 開心！ | 薄荷綠 #63E6BE |
| 7 | 思考 | 我想想... | 薰衣草 #C084FC |
| 8 | 道別 | 再見囉！ | 嬰兒藍 #ADE8F4 |

**Gemini 圖片生成 API 呼叫規格**
| 項目 | 規格 |
|---|---|
| 模型 | `gemini-2.0-flash-exp`（支援圖片輸出） |
| 輸入 | 原圖 Base64 + 文字 prompt（每張貼圖獨立呼叫） |
| 輸出 | 完整圓形貼圖 PNG（含卡通頭像 + 彩色背景 + 嵌入文字） |
| 並行度 | 8 張同時並行生成（Future.wait 或逐一背景更新） |
| Fallback | API 失敗時，Flutter 端顯示文字貼圖（去背主體 + 情感標語文字疊加） |
| 逾時 | 30 秒/張 |

**貼圖設計規格（Gemini Prompt 核心）**
- 圓形設計：370×370 px 正方畫布，白色背景外部，圓形填色內部
- 人臉風格：Q 版/Chibi 卡通，大眼睛、圓臉、誇張情緒表情
- 文字：中文標語嵌入圓圈底部，白色粗體字 + 深色陰影
- 裝飾：情感對應小圖示（✨ 🔥 💭 等）散佈於圓圈內

**生成流程**
```
選圖 → Resize（≤1080px 防 OOM）
  → 並行觸發 8 個 Gemini 圖片生成任務
  → 每張完成後即時更新對應 Swipe 卡片
  → 若失敗 → Flutter fallback（文字疊加模式）
```

**匯出流程**
1. 使用 `RepaintBoundary` → `toImage(pixelRatio: 370 / boundary.size.width)` 確保輸出恰好 370×320 px
2. `toByteData(format: ImageByteFormat.png)` 產出透明背景 PNG
3. 驗證檔案大小 < 1 MB（超過記錄 log，仍儲存）
4. 透過 `gal` 套件儲存至相簿

2.3 AI Fallback 文字生成（備援機制）

```
當 Gemini 圖片生成失敗時：
  → Flutter 端顯示去背主體（若有）或佔位圖
  → 疊加預設 8 組情感標語（含彩色背景 + outline 文字）
  → Fallback 文字組：["哈囉！","太棒了！","真的嗎？","尷尬了...","哼！","開心！","我想想...","再見囉！"]
```

**實作位置**：`core/services/gemini_service.dart`
```dart
Future<List<String>> generateStickerTexts(Uint8List imageBytes); // 8 組 fallback 文字
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
android/                            # Kotlin ML Kit 實作
ios/                                # Swift Vision Framework 實作

6. 驗收標準 (Acceptance Criteria)
 * 效能: 去背 + 3 張貼圖合成總時間 < 3 秒（高階手機）。
 * 貼圖規格: 輸出 PNG 透明背景，尺寸 **370×320 px**（LINE Creators Market 規格），單檔 < 1MB。
 * 穩定性: Firebase Crashlytics 的 Crash-free users 需高於 99%。
 * 相容性: Android 8.0+ / iOS 15.0+ (iOS 17+ 享用進階去背)。
 * 可用性: 3 張貼圖一次儲存至相簿，系統提示引導加入 LINE。

7. 版本歷史 (Changelog)
| 版本 | 日期 | 摘要 |
|---|---|---|
| v1.9 | 2026-03-06 | 全新貼圖架構：跳過 ML Kit 去背，改由 Gemini 2.0 Flash 直接生成 8 張完整圓形 LINE 貼圖（含 Q 版卡通頭像 + 嵌入中文文字 + 彩色背景）；Flutter fallback 保留文字疊加模式 |
| v1.4 | 2026-03-06 | LINE Creators Market 規格合規：透明背景、輸出尺寸修正為 370×320 px、1MB 大小驗證、完成畫面加入上架說明 |
| v1.3 | 2026-03-06 | 移除貼圖視覺設計規範（配色、圖示清單、層次結構、Prompt 細節），讓 AI 自由創作視覺風格 |
| v1.2 | 2026-03-05 | 短文字改為 Gemini API 依照照片內容自動生成（3 組），加入 Fallback 機制、重新生成按鈕、`ai_text_generated` Analytics 埋點 |
| v1.1 | 2026-03-05 | 核心功能調整：由早安貼圖改為自動產出 3 張 LINE 貼圖，新增可愛圖示疊加、短文字（OK/好喔！/很棒）、740×640px 規格輸出 |
| v1.0 | 2026-03-04 | 初版：去背核心、AI 早安文案、GitHub Actions CI/CD |
