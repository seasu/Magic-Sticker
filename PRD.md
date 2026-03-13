📝 產品需求文件 (PRD) - Magic Sticker App
| 屬性 | 描述 |
|---|---|
| 專案名稱 | Magic Sticker（AI 一鍵產 LINE 貼圖） |
| 版本號規範 | SemVer (Major.Minor.Patch+Build) |
| 目前版本 | v3.1.47+168 |
| 開發平台 | Flutter (Android & iOS) |
| 監控系統 | Firebase Crashlytics & Analytics |
| 核心技術 | Gemini 2.0 Flash Exp Image Generation（圖片生成）|

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
  → Cloud Function: generateStickerSpecs（免費）
      ├── 驗證 Firebase Auth
      └── 呼叫 Gemini 2.0 Flash（文字）→ 取得 8 組規格（不扣點）
  → Editor 顯示 8 張 Spec 預覽卡片（文字 + 情緒 + 背景色）
  → 使用者點擊「生成 · 1點」觸發個別貼圖生成
      → Cloud Function: generateStickerImage（1 點/張）
          ├── 驗證 Firebase Auth
          ├── Firestore Transaction 原子性扣 1 點
          ├── 寫入 creditHistory 紀錄
          └── 呼叫 Gemini 2.5 Flash（圖片）→ 回傳 PNG base64
  → 生成失敗自動退點 + 寫入退點紀錄
```

**Cloud Functions 規格**
| Function | 記憶體 | 逾時 | 說明 |
|---|---|---|---|
| `generateStickerSpecs` | 512 MiB | 60s | AI 文字規格（免費，不扣點）|
| `generateStickerImage` | 1 GiB | 120s | AI 圖片生成（1點/張，含 creditHistory）|

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
creditHistoryProvider → List<CreditHistoryEntry> (最近 50 筆異動紀錄)
├── 訪客首次 1 點（降低重裝誘因）
├── 登入升級 5 點
├── 看廣告 +1 點（AdMob Rewarded Ad）
├── 購買點數包（未來 IAP 串接）
├── 每張圖片生成扣 1 點（1 點 = 1 張，非 1 點 = 8 張）
├── 所有點數異動寫入 users/{uid}/creditHistory（供使用者查閱）
└── Firestore: users/{uid}/credits（原子性 Transaction）

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
| v3.1.47 | 2026-03-13 | **fix(diag)**：根本原因確認：`UNAUTHENTICATED`（全大寫）= Cloud Run IAM 在 function 程式碼前攔截，非 token 問題。(1) `GeminiService`/`StickerGenerationService` 新增 `_isIamBlock()` 靜態方法，偵測 `e.message == 'UNAUTHENTICATED'` 時立即停止 retry、以 `iam_blocked` reason 上報 Crashlytics；(2) Cloud Functions `index.ts` 在 `resolveUid` 前加 `invoked` log（含 `hasAuth`、`hasAuthHeader` 欄位），出現此 log = IAM 通過，消失 = IAM 攔截。**修復方法：`firebase deploy --only functions` 重新部署讓 `invoker:public` 生效** |
| v3.1.33 | 2026-03-12 | **fix**：修正 Google 登入後三個問題：(1) `_promoteUser` 改用 in-transaction read `currentCredits`（修正 `previousCredits` 過期問題）；(2) `authStateProvider` 改用 `userChanges()` 確保 `linkWithCredential` 後 `isAnonymous` 即時更新；(3) `CreditNotifier` 偵測 `isAnonymous` 變化時重載點數 |
| v3.1.32 | 2026-03-12 | **fix**：`StickerGenerationService` `unauthenticated` retry 加入指數退避延遲（1s/2s/4s），解決 `linkWithCredential` token rotation 視窗內連續重試全失敗、Crashlytics 誤報 `sticker_single_gen_fn_failed_index0` 問題 |
| v3.1.31 | 2026-03-12 | **CI fix**：`generate_previews.yml` commit 前自動遞增 `pubspec.yaml` 版號 + 更新 `PRD.md`，通過 Version Guard |
| v3.1.30 | 2026-03-12 | **CI fix**：`generate_previews.yml` commit 前自動遞增 `pubspec.yaml` 版號 + 更新 `PRD.md`，通過 Version Guard |
| v3.1.29 | 2026-03-12 | **CI fix**：`generate_previews.yml` 移除不存在的 `auto-generated` label，避免 `gh pr create` 失敗 |
| v3.1.28 | 2026-03-12 | **fix**：`generate_style_previews_ci.py` 修正圖片擷取邏輯（支援 bytes/base64 雙格式）、加入 null-safe 檢查、失敗自動重試 2 次、部分成功不再 exit 1 |
| v3.1.46 | 2026-03-13 | **ux**：圖片生成階段 loading 改用全新 `_PaintStage` 動畫——貓咪坐在畫架前，筆刷（🖌️）沿橢圓軌跡掃動模擬塗抹，顏料粒子（🔴🔵🟡）跳動，三顆星芒（✨💫⭐）以不同相位在畫布周圍閃爍；追貓場景（`_ChaseStage`）保留給分析照片階段；新增 `cos` 到 `dart:math` show 清單 |
| v3.1.45 | 2026-03-13 | **ux**：重新規劃使用流程三個卡關點：(1) 風格選擇 Sheet 副標題改為三步流程圖示（`_FlowStep` + `_FlowArrow`），明確區分「免費分析」與「各 1 點產圖」；(2) `_FunLoadingView` 新增 `title`/`subtitle`/`isImageGen` 參數，並拆分兩組 rotating messages（spec 分析組 vs 圖片生成組），在動畫上方顯示大標題（如「AI 分析照片中 · 免費 · 約 5~10 秒」vs「AI 繪製貼圖中 · 第 N 張 · 已扣 1 點 · 約 20~30 秒」）；(3) `editor_screen.dart` 加入 `ref.listen` 在 `generatingTexts → ready` 轉換時自動彈出引導 SnackBar「✨ 8 款概念生成完畢！點擊『生成 · 1點』…」 |
| v3.1.44 | 2026-03-12 | **fix**：(1) `StickerCanvas._hasAiImage` 從 `isNotEmpty` 改為 `length > 1`，修正未生成 sentinel（`Uint8List(1)`）被當作有效圖片資料傳給 `Image.memory()` 導致的 `Exception: Invalid image data` FlutterError；(2) `GeminiService` 新增 `_forceReAuth()` 取代 retry 迴圈中原本無效的 `signInAnonymouslyIfNeeded()`（user 已存在時為 no-op），改為強制 `getIdToken(true)` 刷新、刷新失敗時對匿名帳號執行完整 signOut + re-signIn，與 `StickerGenerationService._ensureValidAuth` 行為一致 |
| v3.1.43 | 2026-03-12 | **fix（根因）**：所有 Cloud Functions `onCall` 加入 `invoker: "public"` — v2 callable 跑在 Cloud Run 上，預設不允許未經 GCP IAM 驗證的呼叫，手機 App 的 Firebase Auth token 不等於 GCP IAM 認證，請求在到達 function handler 前就被 Cloud Run 擋掉回傳 UNAUTHENTICATED |
| v3.1.42 | 2026-03-12 | **fix**：Cloud Functions 新增 `resolveUid()` — 當 v2 callable `request.auth` 為 null 時，手動從 Authorization header 解析並 `verifyIdToken` 作為 fallback；加入 server-side structured logging 記錄 auth 狀態，便於診斷 |
| v3.1.41 | 2026-03-12 | **Bug fix**：修正 UNAUTHENTICATED 真正根因 — Firebase Auth session 跨 app launch 持久化但 ID token 1 小時過期：(1) `main.dart` 啟動時呼叫 `ensureValidToken()` 強制刷新；(2) `GeminiService.generateStickerSpecs` 加入 token 前置刷新 + UNAUTHENTICATED retry 2 次；(3) `AuthService` 新增公開 `ensureValidToken()` 方法 |
| v3.1.40 | 2026-03-12 | **UI**：editor 畫面尚未生成時，風格示意圖放大至畫布 75% 寬度居中顯示，白底，作為生成前的預覽參考 |
| v3.1.39 | 2026-03-12 | **rename**：專案名稱從 MagicMorning 統一改為 Magic Sticker（README / PRD / CLAUDE.md / CI workflow / App title / class name / 臨時檔名） |
| v3.1.38 | 2026-03-12 | **Bug fix**：修正 `UNAUTHENTICATED` 錯誤根因：(1) `main.dart` 改用 `Firebase.initializeApp()` 不帶 placeholder options，避免與 `google-services.json` native 初始化衝突；Crashlytics handler 移到 try 外面確保一定執行；(2) `StickerGenerationService` 新增 `_ensureValidAuth()` — 強制刷新 token 並驗證非空，刷新失敗時做完整 re-auth（signOut + signInAnonymously）；retry 退避延遲加倍（2s/4s/8s） |
| v3.1.37 | 2026-03-12 | **CI/CD**：(1) deploy-functions 後新增 smoke test，呼叫 `getConfig` 驗證 Cloud Functions 存活且回傳正確 model；(2) PR Check 新增 Cloud Functions TypeScript 編譯檢查 |
| v3.1.27 | 2026-03-12 | **CI fix**：`generate_previews.yml` 改為建立 PR 而非直接 push main，符合 branch protection rules |
| v3.1.26 | 2026-03-12 | **fix**：Gemini image model 預設值從已淘汰的 `gemini-2.5-flash-preview-05-20` 改為 GA 版 `gemini-2.5-flash-image`（修正 CI 404 NOT_FOUND） |
| v3.1.25 | 2026-03-11 | **CI/CD**：deploy-functions job 在部署前從 GitHub Variables（`GEMINI_TEXT_MODEL` / `GEMINI_IMAGE_MODEL`）產生 `functions/.env`；`.gitignore` 加入 `functions/.env` |
| v3.1.24 | 2026-03-11 | **feat**：新增 `getConfig` Cloud Function（回傳目前部署的 text/image model name）；debug 畫面改為即時從 Cloud Functions 拉取顯示，取代硬編碼常數 |
| v3.1.23 | 2026-03-11 | **重構**：Cloud Functions 的 Gemini text model（`GEMINI_TEXT_MODEL`）和 image model（`GEMINI_IMAGE_MODEL`）改用 `defineString` 參數化，可在 Firebase Console 或 `functions/.env` 直接修改，無需改 code 重新部署 |
| v3.1.22 | 2026-03-11 | **feat(dev-log)**：debug 畫面頂部新增 Gemini Models 資訊卡，顯示 Specs/Image 兩個 model name 及 App 版號；長按 model name 可複製 |
| v3.1.21 | 2026-03-11 | **重構**：Gemini image model name 從硬編碼改為讀取 `GEMINI_IMAGE_MODEL` 環境變數（fallback `gemini-2.5-flash-preview-05-20`）；workflow 從 GitHub Variable `vars.GEMINI_IMAGE_MODEL` 注入，日後換 model 只需在 GitHub Settings → Variables 修改，無需改 code |
| v3.1.20 | 2026-03-11 | **CI fix**：3 支 Python 腳本的 Gemini image model 統一改為 `gemini-2.5-flash-preview-05-20`（與 Cloud Functions 一致），修正 `generate_style_previews_ci.py` 404 NOT_FOUND |
| v3.1.19 | 2026-03-11 | **CI fix**：修正 `dart analyze --fatal-infos` 的 33 個 info/warning：移除未使用的 `_StatusBadge.failed`、補齊 `const` 建構子、修正 `curly_braces_in_flow_control_structures`、`unnecessary_brace_in_string_interps`、`library_private_types_in_public_api` |
| v3.1.18 | 2026-03-11 | **Merge fix**：合併 main 分支，`_promoteUser` 採用 Cloud Functions 專責寫入 `creditHistory` 的架構（移除客戶端 `_writeCreditHistory` 呼叫），避免 Firestore `permission-denied` |
| v3.1.16 | 2026-03-11 | **UI/UX fix**：EditorScreen 生成失敗狀態三項修正：(1) 底部按鈕邏輯修正——失敗（`Uint8List(0)`）時改顯示「生成·1點」而非「儲存貼圖」，避免 token 時序混淆；(2) `_accept()` 新增失敗狀態 guard，防止匯出空白圖；(3) 錯誤提示從頂部小 badge 改為全卡片居中大型覆蓋層（`_FailedOverlay`），文字 24sp+加粗+重試按鈕，視覺更清晰 |
| v3.1.15 | 2026-03-11 | **Bug fix**：(a) 修正 `StickerGenerationService` 在 `unauthenticated` 錯誤時的 retry 無效問題，改用 `user.getIdToken(true)` 強制刷新 ID token；(b) 移除 `AuthService` 中所有從客戶端寫入 `creditHistory` 的呼叫，`creditHistory` 寫入僅由 Cloud Functions 處理；新增 `ensure_user_doc_failed` 獨立 Crashlytics 錯誤標籤 |
| v3.1.14 | 2026-03-11 | **Bug fix**：(a) 修正 Google 登入後點數未更新的 3 個問題（`_promoteUser` 改用 in-transaction read、`authStateProvider` 改用 `userChanges()`、`CreditNotifier` 偵測 `isAnonymous` 變化）；(b) **CI fix**：`generate_style_previews_ci.py` 更新 Gemini model name 為 `gemini-2.0-flash-exp-image-generation` |
| v3.1.9 | 2026-03-11 | **CI fix**：移除 `editor_screen.dart` 中未使用的 `_kNopeColor` 常數與 `_CircleButton`/`_CircleButtonState` 死碼，修正 `dart analyze --fatal-infos` 的 5 個 `unused_element`/`unused_element_parameter` 警告 |
| v3.1.8 | 2026-03-11 | **CI fix**：移除 `editor_screen.dart` 中已棄用的 `_ProgressBar` 與 `_TinderButtons` 兩個 unused class，修正 `dart analyze --fatal-infos` 報告的 `unused_element` 警告，CI 恢復正常 |
| v3.1.7 | 2026-03-11 | **風格示意圖**：`assets/images/` 加入 6 張色塊佔位 PNG（chibi/popArt/pixel/sketch/watercolor/photo）；`_StyleCard` 改用 `Image.asset` 顯示預覽圖（errorBuilder 回退 emoji）；新增 `scripts/generate_style_previews_ci.py` 與 `.github/workflows/generate_previews.yml`（workflow_dispatch 手動觸發，使用 GEMINI_API_KEY secret 生成真實 AI 圖並 commit 回 repo，完成後可移除 workflow 與腳本）|
| v3.1.6 | 2026-03-11 | **UX 升級**：重新設計登入 Bottom Sheet（initial / loading / success / error 四狀態機）；success 狀態顯示 Google 大頭貼、歡迎名字、+5 點動畫 badge；error 狀態改為 sheet 內重試（不再用 SnackBar）；`CreditBadge` 登入後顯示使用者頭像小圓；首頁版本號移至底部頁尾（不再佔據 AppBar 右側空間）|
| v3.1.5 | 2026-03-11 | **UI 簡化**：選擇貼圖畫面移除頂部八點進度條、卡片堆疊效果及底部 X/❤️ Tinder 按鈕；改為單張卡片顯示，「生成」按鈕移至底部，生成後出現「儲存貼圖」綠色按鈕；圖片未生成時編輯鉛筆按鈕自動 disable |
| v3.1.4 | 2026-03-11 | **UI 調整**：未生成貼圖時在畫布中央顯示貓咪 🐱 emoji 與「點擊生成貼圖」提示文字，取代純色空白佔位 |
| v3.1.3 | 2026-03-11 | **UI 調整**：放大「生成 · 1點」按鈕（padding 20/10→32/16、字體 14→18、icon 16→22、圓角 24→32）提升點擊體驗 |
| v3.1.2 | 2026-03-11 | **Bug fix**：`StickerGenerationService` 呼叫 Cloud Function 前加入 auth 預檢；若 `currentUser == null`（啟動時匿名登入失敗）則先執行 `signInAnonymouslyIfNeeded()` 再呼叫；`unauthenticated` 錯誤加入 retry + 重新認證邏輯，防止 Crashlytics `sticker_single_gen_fn_failed_index0` |
| v3.1.1 | 2026-03-11 | **CI fix**：Functions deploy 加 `--force` 自動設定 Artifact Registry cleanup policy，避免容器映像累積產生費用；`firebase-functions` 升級至 `^6.0.0` |
| v3.1.0 | 2026-03-11 | **計費重構**：1 點 = 1 張圖片（原為 1 點 = 8 張）；`generateStickerSpecs` 免費、`generateStickerImage` 原子性扣 1 點；新增 `creditHistory` Firestore 子集合記錄所有點數異動；新增「點數紀錄」UI 頁面；`CreditBadge` 點擊可查閱異動紀錄；`functions/package.json` Node 22 |
| v3.0.23 | 2026-03-10 | **資源更新**：更新 `assets/app_icon.png` |
| v3.0.22 | 2026-03-10 | **清理**：刪除未使用的 `assets/HEIF影像.jpeg` |
| v3.0.21 | 2026-03-10 | **資源更新**：手動更新 `app_icon.png` |
| v3.0.20 | 2026-03-10 | **CI 簽名**：Android Release 簽名改由 GitHub Actions 讀取 Secrets 產生 keystore，`build.gradle` 加入 `key.properties` 讀取邏輯 |
| v3.0.19 | 2026-03-10 | **內容更新**：privacy.html 聯絡 email 更換為 seasuwang+magicsticker@gmail.com |
| v3.0.18 | 2026-03-10 | **CI fix**：拆分 functions 與 firestore:rules 為獨立 deploy step，rules step 加 continue-on-error 避免 API 未啟用時卡住 functions 部署 |
| v3.0.17 | 2026-03-10 | **Bug fix**：新增 Android Adaptive Icon（`mipmap-anydpi-v26`），背景填 `#F06292` 消除 icon 圓角黑邊 |
| v3.0.16 | 2026-03-10 | **Bug fix**：新增 `firestore.rules`，允許匿名用戶讀寫自己的 `users/{uid}` 文件，修正 `permission-denied` 導致匿名登入失敗與點數無法載入問題；CI 加入 `firestore:rules` 自動部署 |
| v3.0.15 | 2026-03-10 | **Bug fix**：修正看廣告後未加點問題；`AdsService.showRewardedAd` 改用 Completer 等待廣告關閉再 return，確保 `rewarded` 旗標正確；`AuthService.addCredits` 改用 `set merge` 防止文件不存在時靜默失敗 |
| v3.0.6 | 2026-03-10 | **App Icon 修正**：adaptive icon 前景/背景拆層設定；CI 加入前景圖缺失 fallback，避免 build 失敗 |
| v3.0.5 | 2026-03-10 | **App Icon**：更換全新貓咪 icon（Magic Sticker 一鍵貼圖）；CI/CD 加入 `dart run flutter_launcher_icons` 自動生成所有尺寸 |
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
