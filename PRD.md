📝 產品需求文件 (PRD) - MagicMorning App
| 屬性 | 描述 |
|---|---|
| 專案名稱 | MagicMorning（AI 一鍵產 LINE 貼圖） |
| 版本號規範 | SemVer (Major.Minor.Patch+Build) |
| 目前版本 | v3.0.4+99 |
| 開發平台 | Flutter (Android & iOS) |
| 監控系統 | Firebase Crashlytics & Analytics |
| 核心技術 | Gemini 2.0 Flash（圖片生成）|

---

## 1. 產品願景

讓使用者只需「選取一張照片」，App 即透過 **Gemini AI** 自動產出 **8 張**符合 LINE Creators Market 規格的圓形卡通貼圖，每張呈現 Q 版人物 + 彩色背景 + 情感標語，透過 **Tinder 滑卡** 介面挑選後一鍵儲存至相簿，即可直接上架。

---

## 2. 核心功能模組

### 2.1 照片輸入與 Resize
- 使用者從相簿選取任意照片（`image_picker`）
- Flutter 端先 Resize ≤ 1080px（`image_processor.dart`），避免傳送巨圖給 API 造成 OOM
- Resize 後以 Base64 傳送至 Gemini

### 2.2 AI 貼圖生成（Gemini 2.0 Flash — 透過 Cloud Functions）

**安全架構（v3.0 起）**

> Gemini API Key 不再打包進 App，完全存放於 Firebase Cloud Functions 環境變數，防止反編譯洩漏。

**生成流程**
```
選圖 → Resize（≤1080px）
  → Cloud Function: generateStickerSpecs
      ├── 驗證 Firebase Auth
      ├── Firestore Transaction 原子性扣 1 點
      └── 呼叫 Gemini 2.0 Flash（文字）→ 取得 8 組規格
  → 並行觸發 8 個 Cloud Function: generateStickerImage
      ├── 驗證 Firebase Auth（無再次扣點）
      └── 呼叫 Gemini 2.5 Flash（圖片）→ 回傳 PNG base64
  → 每張完成後即時顯示在對應 Swipe 卡片
  → 失敗 → Flutter fallback（彩色背景 + 文字疊加）
```

**Cloud Functions 規格**
| Function | 記憶體 | 逾時 | 說明 |
|---|---|---|---|
| `generateStickerSpecs` | 512 MiB | 60s | 扣點 + AI 文字規格 |
| `generateStickerImage` | 1 GiB | 120s | AI 圖片生成（proxy） |

**輸出規格（LINE Creators Market 官方）**
| 項目 | 規格 |
|---|---|
| 輸出尺寸 | **370×320 px** |
| 畫布邏輯比例 | 740×640（@2x master，AspectRatio = 740/640） |
| 輸出格式 | **PNG 透明背景** |
| 單檔上限 | **1 MB** |
| 一組數量 | **8 張**（LINE Creators Market 最低門檻） |

### 2.3 Tinder 滑卡挑選介面
- 8 張貼圖以 **Tinder 風格堆疊卡片**呈現
- **右滑 / ❤️ 按鈕** → 儲存至相簿（`gal` 套件）
- **左滑 / ✕ 按鈕** → 跳過
- 卡片上方顯示 8 格進度條
- 全部完成後顯示「已儲存 N 張」結果畫面

### 2.4 貼圖編輯器（點圖開啟 Bottom Sheet）
使用者可對每張貼圖進行即時預覽編輯，變更後立即反映：

| 功能 | 實作 |
|---|---|
| **文字編輯** | TextField，即時更新 Canvas overlay |
| **字型選擇** | 5 種繁中字體（黑體、圓體、書法、可愛、手寫） |
| **字體大小** | 滑桿 40%–200%，基礎字體 36px |
| **文字位置** | 上↔下滑桿（Align -1.0 ~ 1.0），即時預覽 |
| **配色方案** | 8 組預設色系（橘、藍、黃、粉、紅、綠、紫、水藍） |
| **產圖風格** | Q版卡通 / 普普風 / 像素風 / 素描（變更後重新生成） |

編輯預覽框外圍顯示**虛線邊界框**，清楚標示 LINE 貼圖輸出邊界。

### 2.5 匯出（RepaintBoundary → PNG）
1. `RepaintBoundary.toImage(pixelRatio: 370 / boundary.size.width)` → 確保輸出恰好 370×320 px
2. `toByteData(format: ImageByteFormat.png)` → 透明背景 PNG
3. 驗證 < 1 MB（超過記錄 `sticker_export_oversized` log，仍儲存）
4. `Gal.putImageBytes()` 儲存至相簿
5. Firebase Analytics 記錄 `sticker_generated`

### 2.6 AI 等待動畫
- **全畫面等待**（去背/生成文案階段）：🐱 貓追 🐭 老鼠橫向動畫 + 輪播趣味文案
- **每張卡片生成中**：迷你 🐱🐭 彈跳 Badge 取代靜態 Spinner

### 2.7 Fallback 機制
- Gemini 圖片生成失敗 → Flutter 端顯示彩色圓形背景 + outline 文字疊加
- 失敗 badge 支援長按查看 API 錯誤詳情、點擊單張重試

---

## 3. 技術架構

### 狀態管理（Riverpod）
```
authStateProvider → StreamProvider<User?>
├── Firebase Anonymous Auth（訪客）→ Firestore 建立文件，1 點
├── Google Sign-In / Apple Sign-In → 升級帳號，最低 5 點
└── iOS Keychain 保護：重裝後匿名 UID 不變（Android 重裝才重置）

creditProvider → int (點數，來自 Firestore)
├── 訪客首次 1 點（降低重裝誘因）
├── 登入升級 5 點
├── 看廣告 +1 點（AdMob Rewarded Ad）
├── 購買點數包（未來 IAP 串接）
└── Firestore: users/{uid}/credits（原子性 Transaction 扣點）

Firestore 資料結構:
users/{uid}/
  credits: int        ← 點數
  isAnonymous: bool   ← 訪客/正式帳號
  createdAt: Timestamp
  updatedAt: Timestamp

editorStateProvider(imagePath) → EditorState
├── status: idle / generatingTexts / ready
├── stickerTexts[8]       ← AI 生成標語
├── generatedImages[8]    ← null=生成中, empty=失敗, bytes=成功
├── colorSchemeIndices[8] ← 配色方案
├── fontIndices[8]        ← 字型索引
├── fontSizeScales[8]     ← 字體大小倍率
├── textYAligns[8]        ← 文字垂直位置
├── imageScales[8]        ← 圖片縮放
└── imageOffsets[8]       ← 圖片位移
```

### 目錄結構
```
lib/
├── main.dart                         # 入口 + Firebase + 全域錯誤攔截
├── app.dart                          # MaterialApp.router + GoRouter
├── core/
│   ├── constants/
│   ├── models/
│   │   ├── sticker_spec.dart         # AI 生成規格（文字/風格）
│   │   └── sticker_style.dart        # 產圖風格 Enum
│   ├── services/
│   │   ├── ads_service.dart          # AdMob Rewarded Ad 單例
│   │   ├── firebase_service.dart
│   │   ├── gemini_service.dart       # generateStickerSpecs()
│   │   └── sticker_generation_service.dart  # generateSingle()
│   ├── theme/
│   │   └── app_colors.dart
│   └── utils/
│       └── image_processor.dart      # Resize ≤ 1080px
├── features/
│   ├── home/                         # 照片選取首頁
│   ├── billing/
│   │   └── providers/
│   │       └── credit_provider.dart  # 點數狀態（Riverpod）
│   └── editor/
│       ├── models/
│       │   ├── editor_state.dart
│       │   ├── sticker_config.dart
│       │   ├── sticker_font.dart
│       │   └── frame_style.dart
│       ├── providers/
│       │   └── editor_provider.dart
│       ├── screens/
│       │   └── editor_screen.dart    # Tinder 滑卡主畫面
│       └── widgets/
│           ├── sticker_canvas.dart   # 單張貼圖畫布
│           ├── sticker_swipe_card.dart
│           ├── sticker_edit_sheet.dart
│           └── canvas_preview.dart
├── shared/
│   └── widgets/
│       ├── credit_badge.dart         # AppBar 點數徽章
│       └── credit_paywall_dialog.dart # 點數不足 Paywall Dialog
└── native/
    └── method_channel.dart           # Android/iOS 原生橋接（備用）
```

---

## 4. 錯誤監控（Firebase Crashlytics）
- 全域攔截：`FlutterError.onError` + `PlatformDispatcher.instance.onError`
- 每張貼圖生成結果記錄：`sticker_generated` / `sticker_export_failed`
- Gemini API 呼叫全程記錄 `Crashlytics.log()`

---

## 5. 驗收標準

| 指標 | 標準 |
|---|---|
| 貼圖規格 | PNG 透明背景，370×320 px，< 1 MB |
| 相容性 | Android 8.0+（minSdk 26）/ iOS 15.0+ |
| 穩定性 | Crashlytics crash-free users > 99% |
| AI 生成 | 每張 ≤ 30 秒；8 張逐一顯示，不需等全部完成 |

---

## 6. 版本歷史

| 版本 | 日期 | 摘要 |
|---|---|---|
| v3.0.4 | 2026-03-10 | **CI/CD 加強**：`google-services.json` 寫入後以 Python 驗證 JSON 格式、`project_info` 欄位、及 placeholder 偵測，錯誤時給出明確訊息 |
| v3.0.3 | 2026-03-10 | **隱私政策**：新增 Firebase Hosting 靜態隱私政策頁面（`public/privacy.html`）；firebase.json 加入 Hosting 設定；CI/CD 加入 `deploy-hosting` job，push to main 自動部署 |
| v3.0.2 | 2026-03-10 | **CI/CD 修正**：NDK 升級至 27.0.12077973（符合 Firebase 套件需求）；`GOOGLE_SERVICES_JSON_ANDROID` secret 未設定時 CI 立即 fail，防止空檔案覆蓋 google-services.json |
| v3.0.1 | 2026-03-10 | **CI/CD 修正**：Cloud Functions deploy workflow 改用 `npm install`（移除 package-lock.json 依賴），修正 GitHub Actions `npm ci` 失敗問題 |
| v3.0.0 | 2026-03-09 | **安全升級**：Gemini API Key 移至 Firebase Cloud Functions，App 完全不含金鑰；新增 `generateStickerSpecs` / `generateStickerImage` 兩支 Cloud Functions；點數扣除移至 server 端原子性處理；CI/CD 加入 functions deploy 步驟 |
| v2.9.0 | 2026-03-09 | Firebase Auth 帳號系統：匿名訪客 1 點；Google/Apple 登入升級 5 點；Firestore 雲端點數；訪客刪 App 重裝僅得 1 點（iOS Keychain 保護）；LoginBottomSheet |
| v2.8.0 | 2026-03-09 | 免費版廣告點數系統：新增 CreditProvider / AdsService / CreditPaywallDialog；首次安裝贈 3 點，看廣告解鎖 1 次；AppBar 即時點數徽章 |
| v2.1.5 | 2026-03-08 | 編輯畫面新增虛線邊界框；字體大小與文字位置滑桿；移除 FittedBox 修正預設字型過大問題 |
| v2.1.4 | 2026-03-08 | 每張卡片「AI 生成中」badge 換成 🐱🐭 迷你彈跳動畫 |
| v2.1.3 | 2026-03-08 | 修正 linter errors（unused import、unnecessary import） |
| v2.1.1 | 2026-03-08 | 等待動畫改為趣味貓追老鼠（_FunLoadingView + _ChaseStage） |
| v2.1.0 | 2026-03-08 | 新增字型選擇（5 種繁中）與產圖風格選擇（Q版/普普/像素/素描） |
| v2.0.27 | 2026-03-07 | 點圖開啟編輯 popup：縮放/位移、文字、配色 |
| v1.9 | 2026-03-06 | 全新架構：Gemini 直接生成完整圓形貼圖；Tinder 滑卡 UI |
| v1.4 | 2026-03-06 | LINE Creators Market 規格合規：370×320 px PNG，< 1 MB |
| v1.0 | 2026-03-04 | 初版：去背核心、AI 早安文案、GitHub Actions CI/CD |
