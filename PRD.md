📝 產品需求文件 (PRD) - Magic Sticker App
| 屬性 | 描述 |
|---|---|
| 專案名稱 | Magic Sticker（AI 一鍵產 LINE 貼圖） |
| 版本號規範 | SemVer (Major.Minor.Patch+Build) |
| 目前版本 | v3.7.0+300 |
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
- Flutter 端先 Resize ≤ 768px（`image_processor.dart`），避免傳送巨圖給 API 造成 OOM；768px 為 Gemini tile 邊界（768×768 = 1 tile），超過則跳為 4 tile，token 費用增加 4 倍
- Resize 後以 Base64 傳送至 Gemini

### 2.2 AI 貼圖生成（Gemini 2.0 Flash — 透過 Cloud Functions）

**安全架構（v3.0 起）**

> Gemini API Key 不再打包進 App，完全存放於 Firebase Cloud Functions 環境變數，防止反編譯洩漏。

**v3.1.84 新增：Firebase App Check**

> 所有 Cloud Functions 與 Firestore 存取均須通過 App Check 裝置驗證（Android: Play Integrity / Debug Token；iOS Phase 2: DeviceCheck），防止非官方客戶端盜用 API。

**生成流程（v3.3.0 延遲分析架構）**
```
選圖 → 選風格 → 選情緒 → 進入 Editor（立即顯示，無需等待分析）
  → Editor 顯示 N 張情緒 Placeholder 卡片（可立即右滑觸發生成）
  → 使用者右滑 / 點擊「生成 · 1點」：
      ┌─ 若尚未分析（首次）：
      │   → Cloud Function: generateStickerSpecs（免費，延遲執行）
      │       ├── 驗證 App Check
      │       ├── 驗證 Firebase Auth
      │       └── 呼叫 Gemini 2.0 Flash → 取得全組規格（快取，後續不重複）
      └─ → Cloud Function: generateStickerImage（1 點/張）
              ├── 驗證 App Check（enforceAppCheck: true）
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
| **配色方案** | 8 組預設色系（橘、藍、黃、粉、紅、綠、紫、水藍）；獨立「配色」Tab 選色 |

底部三 Tab 說明：
- **調整圖片**：進入即預設啟動，Canvas 可單指拖動位移、雙指縮放旋轉
- **調整文字**：文字輸入 + 字型選擇
- **配色**：8 色盤選擇（原「產圖風格」Tab 位置）

> 產圖風格在風格選擇頁決定，進入編輯器後不再提供切換，避免中途重新生成破壞編輯流程。

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
│       └── image_processor.dart      # Resize ≤ 768px（Gemini 1-tile 邊界）
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
| v3.7.0 | 2026-03-20 | **ci(ios)**：Phase 2 iOS CI/CD 啟動 — `main_build.yml` 新增 `ios-build` job（`macos-latest` runner，免費 for public repo）；自動初始化 ios/ 目錄、設定 Bundle ID `com.magicsticker.magic_sticker`、iOS 15.0+ 部署目標、匯入 Distribution Certificate + Provisioning Profile、產生 ExportOptions.plist、`flutter build ipa`、上傳至 TestFlight（`apple-actions/upload-testflight-build@v3`）；`pubspec.yaml` 啟用 `flutter_launcher_icons` iOS 圖示生成。 |
| v3.6.12 | 2026-03-20 | **docs(readme)**：更新 README 反映最新 App 狀態 — 風格 6→12 種、情緒 16→24 種、選擇門檻 4→1 種、延遲分析架構、點數商店、App Check 安全性、768px Resize、GIF loading、背景色功能。 |
| v3.6.11 | 2026-03-20 | **fix(ci)**：`generate_style_previews_ci.py` 補入缺少的 8 種情感（sleepy/beg/worried/hungry/celebrate/no/encourage/pain），修正產圖數量 192 → 288（12 × 24），與 workflow yml 及 `kEmotionCategories` 一致。 |
| v3.6.10 | 2026-03-20 | **fix(ci)**：`generate_previews.yml` 修正 header comment 與 PR body 中情感數量錯誤（16 種 → 24 種、192 張 → 288 張），與 `kEmotionCategories` 實際定義一致。 |
| v3.6.3 | 2026-03-20 | **fix(editor)**：`initialize()` 修正示意圖三個 bug —— ① `categoryIds` 預先從 `selectedCategoryIds` 填入，fallback 顯示正確情緒預覽圖；② `stickerTexts` 初始化為空字串 list，避免顯示與情緒無關的佔位文字（哈囉！等）；③ 同時修正使用者選超過 8 種情緒時 `stickerTexts` 長度不足導致 index out of range 的問題。 |
| v3.6.2 | 2026-03-19 | **ci**：新增 PR label `release` 觸發機制——merge PR 時若有 `release` label 則自動跑完整 build + deploy，不需額外打 tag 或手動觸發。 |
| v3.6.1 | 2026-03-19 | **ci**：CI 改為雙軌觸發——push main 只跑 `dart analyze`；push tag `v*` 或手動 `workflow_dispatch` 才跑完整 build + deploy（Android / Firebase / Play Store）；新增 `workflow_dispatch` 輸入欄位支援自訂發版說明。 |
| v3.6.0 | 2026-03-19 | **perf(assets)**：214 張預覽圖從 PNG 轉換為 WebP（quality=85），assets 體積 40.9MB→8.2MB（省 32.6MB / 80%）；更新 `style_selection_screen.dart` 和 `sticker_canvas.dart` 引用為 `.webp`；`build.gradle` 啟用 `shrinkResources true` 並加入 AAB `bundle { language/density/abi splits }`。 |
| v3.5.13 | 2026-03-19 | **fix(ci)**：Google Play 上傳 status 從 `completed` 改為 `draft` — App 首次上架前為 draft 狀態，`completed` 會導致 `Only releases with status draft may be created on draft app` 錯誤。 |
| v3.5.12 | 2026-03-19 | **fix(canvas)**：`StickerCanvas._buildFallback()` 修正佔位示意圖永遠顯示 `greeting` 的 bug — 改依 `categoryId` 選擇 `preview_{style}_{emotion}.png`，`categoryId` 為空時退回 `greeting`。 |
| v3.5.11 | 2026-03-19 | **chore(assets)**：無損壓縮靜態圖片資源 — `app_icon.png` 4836KB→3614KB (-25%)、`cat_source.png` 887KB→818KB (-8%)，合計節省 ~1.3MB，尺寸不變。 |
| v3.5.10 | 2026-03-19 | **fix**：登入成功 badge「+5 點 已入帳」僅在訪客首次升級時顯示（`AuthResult.wasPromoted`）；`_maxDimension` 1080→768px（Gemini 1-tile 邊界）。 |
| v3.5.4 | 2026-03-19 | **ci(play-store)**：`main_build.yml` 新增 Google Play Store 自動發布 job（`play-store-deploy`）— 每次 merge to main 自動 build AAB 並上傳至 internal track；同步改 mapping.txt 為每次都上傳（原本僅 tag 時）；需設定 `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret。 |
| v3.5.3 | 2026-03-19 | **fix(prompts)**：修正 6 個貼圖風格的 `characterDesc` 導致角色被截斷的問題 — 移除「肖像」描述詞（popArt / sketch / watercolor / showaManga），改為明確要求完整身形；yuruDoodle 補入「身體四肢完整可見」；claymation 補入「頭頂至腳底不被截斷」；showaManga 新增「速度線僅集中於角色周邊，不延伸至畫布邊緣」約束。 |
| v3.5.2 | 2026-03-18 | **feat(editor)**：「配色」Tab 新增「背景色」區塊 — 9 個 preset（透明＋8 種淺色）可獨立選擇，取代棋盤格透明底；背景色填入 `StickerCanvas` Stack 最底層，亦寫入匯出 PNG；`EditorState` 新增 `bgColorIndices`（每張貼圖獨立記錄），`kBgColors` 定義於 `sticker_edit_sheet.dart`，同步支援 replay 畫面。 |
| v3.5.1 | 2026-03-18 | **refactor(editor)**：移除編輯器底部「產圖風格」Tab（風格已於前頁選定，中途切換需重新生成，流程斷裂）；「配色」升格為獨立第三 Tab（取代原「產圖風格」位置）；進入編輯器預設啟動「調整圖片」模式，省去多餘點擊。 |
| v3.5.0 | 2026-03-18 | **feat(emotions)**：情緒類別從 16 擴充至 24 種（新增 sleepy/beg/worried/hungry/celebrate/no/encourage/pain，全部 defaultOn: false）；清理 `_buildFallback()` 死碼，終極 fallback 改為品牌色底 + 風格 emoji 的 `_StyleEmojiPlaceholder`（不再錯誤顯示 chibi）；`generate_style_thumbnails.py` 補入 3 個新風格定義（yuruDoodle/showaManga/claymation）；CI `generate_previews.yml` ALL_EMOTIONS 同步更新為 24 種。 |
| v3.4.2 | 2026-03-18 | **refactor(canvas)**：`_buildFallback()` 改為直接重用 greeting 縮圖作佔位圖，不再依賴 12×16 組合圖；`generate_previews.yml` 停用 push 自動觸發（保留 workflow_dispatch 供日後復原），節省 Gemini API 費用。 |
| v3.4.1 | 2026-03-18 | **ci(workflows)**：`gen_style_thumbnails.yml` 的 styles 參數改為下拉選單（12 種風格 + 全部），並修正 `PREVIEW_STYLES` 環境變數未傳入腳本的 bug；`generate_previews.yml` styles/emotions 描述列出所有可用值，`ALL_STYLES` 補入 3 個新風格，PR body 數量更新為 12×16=192。 |
| v3.4.0 | 2026-03-18 | **feat(styles)**：新增 3 種貼圖風格（ゆるい塗鴉、昭和漫畫、黏土捏塑），風格總數從 9 增至 12（3×4 滿版）；預覽圖以 emoji 佔位；「重新來過」右上角按鈕改為確認對話框（提示不存檔 / 記錄不顯示）後導回首頁，讓使用者可重選照片與風格。 |
| v3.3.2 | 2026-03-18 | **ux(emotion)**：情緒選擇最低門檻從 4 種降為 1 種（`_kMin = 1`），只要勾選至少 1 個情緒即可確認進入下一步；副標題說明文字同步更新為「可選 1–12 種」。 |
| v3.3.1 | 2026-03-18 | **ui(loading)**：`CatLoadingWidget` 改為粉紅品牌色系並修正滿版問題 — 貓咪主色改為品牌珊瑚粉 `#FD297B`、亮部改為淡粉紅 `#FFB3C6`、背景改為極淡玫瑰白 `#FFF0F3`；根 widget 改用 `SizedBox.expand` 確保在 Stack overlay 中完整填滿螢幕。 |
| v3.2.51 | 2026-03-18 | **fix(assets)**：更新 `normalize_previews.py` 加入去背功能（`_apply_bg_removal`），在正規化構圖後對已知純色背景做精確 alpha 遮罩（threshold=28, feather=22），輸出 RGBA 透明 PNG；對全部 160 張 preview 圖執行正規化＋去背，取代彩色背景版本，新圖生成後亦自動套用。 |
| v3.2.50 | 2026-03-18 | **fix(assets)**：以 `normalize_previews.py --all` 正規化全部 160 張 preview 圖片，修正腳本改用「四角採樣背景色 + 顏色距離」偵測人物（原腳本錯誤假設透明或白底，實際為 RGB 彩色背景）；所有圖片人物頂端統一 7%、高度統一 78%、水平置中，視覺一致性大幅提升。 |
| v3.2.49 | 2026-03-18 | **feat(scripts)**：新增 `normalize_previews.py` 後處理腳本，以 PIL bounding box 偵測人物像素後統一縮放（高度78%）並置中排版（頂部7%），解決 Gemini 生成 preview 圖片人物高低不齊問題；整合至 `generate_style_previews_ci.py`（透明背景）與 `generate_style_thumbnails.py`（白底縮圖），新圖生成後自動正規化；另提供 CLI `--all/--thumbnails/--styles/--emotions/--dry-run` 可一次處理現有所有圖片。 |
| v3.2.48 | 2026-03-18 | **refactor(editor)**：新增 `StickerCanvasFrame` 共用元件（`sticker_canvas_frame.dart`），統一管理棋盤格背景、形狀裁切、陰影外框、虛線邊界、編輯按鈕；同時修正編輯 Sheet 中棋盤格超出形狀邊界的 bug（原本 `_CheckerboardPainter` 畫在整個正方形上而 canvas 才套用 ClipOval/ClipRRect）。移除 `editor_screen.dart` 與 `sticker_edit_sheet.dart` 中重複的 `_CheckerboardPainter` 與 `_BoundaryPainter`。 |
| v3.2.46 | 2026-03-17 | **refactor(loading)**：以 GIF 動畫取代 `video_player` MP4 loading——分析階段用 `cat-research-loading.gif`、繪圖階段用 `cat-drawing-loading.gif`；`_FunLoadingView` 從 StatefulWidget 簡化為 StatelessWidget；移除 `video_player` 依賴。 |
| v3.2.45 | 2026-03-17 | **feat(assets/ci)**：新增 `generate_style_thumbnails.py` 腳本與 `gen_style_thumbnails.yml` CI workflow，專門產生 9 張風格選擇縮圖（seasu-source.jpg × greeting 情緒）；Prompt 與 App 產圖完全一致（中文 Chroma Key 模式），額外加入縮圖一致性規範確保 9 張構圖比例相同。 |
| v3.2.44 | 2026-03-17 | **fix(ui)**：編輯 Sheet 與歷史貼圖（sticker_replay_screen）畫布加入棋盤格透明示意背景；歷史編輯畫面同步補上虛線邊界圓，兩處 painters 均在 RepaintBoundary 外層，不影響 export 輸出。 |
| v3.2.43 | 2026-03-17 | **fix(prompt+algo)**：Chroma Key 背景從綠幕（#00FF00）改為白幕（#FFFFFF）— Prompt 要求純白平塗背景；`image_processor.dart` 白色像素偵測改為 R/G/B > 220，edge cleanup 由 3 輪降為 2 輪避免誤刪角色淺色邊緣；去背失敗時殘留白邊比綠邊更自然不影響貼圖使用。 |
| v3.2.42 | 2026-03-17 | **fix(prompt)**：強化 Chroma Key 去背 Prompt — 明確告知 Gemini 背景為純技術遮罩色，禁止光暈、漸層、反光、筆觸、紋理、陰影投射等所有藝術加工，確保背景像素穩定維持精確 #00FF00，提升 chroma key 去背成功率。 |
| v3.2.41 | 2026-03-17 | **fix(ui)**：貼圖預覽卡片左右加 24px 邊距，避免圖片貼邊視覺不適。 |
| v3.2.34 | 2026-03-17 | **fix(functions)**：移除 `generationConfig` 中非法的 `responseImageMimeType` 欄位 — Gemini REST API v1beta 的 `GenerationConfig` 不存在此欄位，導致所有圖片生成請求回傳 HTTP 400 `INVALID_ARGUMENT`；移除後使用 API 預設圖片格式，Cloud Function 原有 `inlineData.mimeType.startsWith("image/")` 解析邏輯不受影響。 |
| v3.2.33 | 2026-03-17 | **fix(ui)**：Google 登入後頭像即時顯示 — 將 `_LoggedInBadge` 從 `StatelessWidget` 改為 `ConsumerWidget`，改由 `ref.watch(currentUserProvider)` 取得使用者資料（原本直接讀 `FirebaseAuth.instance.currentUser`）；`_UserAccountSheet` 同步改用 Riverpod provider；移除 `credit_badge.dart` 中多餘的 `firebase_auth` 直接 import。確保 `userChanges()` 觸發時頭像圖片立即刷新。 |
| v3.2.32 | 2026-03-17 | **feat(prompt/ui)**：(1) 風格選擇縮圖改用各風格的 greeting（打招呼）情緒示意圖（`preview_[style]_greeting.png`）；(2) 圖片生成 Prompt 四個 variants（圓形透明、圓形不透明、方形透明、方形不透明）均新增防裁切指令：頭頂與身體下緣保留至少 5% 邊距、左右保留 10% 邊距，並明確禁止任何部位（頭頂、耳朵、手臂、腳等）被畫布邊緣截斷。 |
| v3.2.4 | 2026-03-15 | **fix(ci)**：修正 CI smoke test 因 Cloud Run IAM 傳播延遲（10–30s）導致 `getConfig` 返回 403 而失敗 — 將 `curl -sf` 改為帶 HTTP status code 捕獲的寫法，加入最多 5 次重試（初始等待 15s，每次遞增 10s），每次嘗試輸出 HTTP status 與 body 方便 debug；最終仍失敗才 `exit 1`。 |
| v3.2.3 | 2026-03-15 | **fix(auth)**：修正 Google Login 出現 `permission-denied` 錯誤 — 根本原因：`signInWithCredential` / `linkWithCredential` 完成後 Firebase Auth 立即 fire `userChanges()`，但新 ID token 尚未傳遞至 Firestore SDK，導致後續的 Firestore read/write 被拒絕；`_ensureUserDoc` / `_promoteUser` 也無 try-catch，exception 一路冒泡至 `PlatformDispatcher`。修正：(1) `CreditNotifier._loadCredits` 在讀 Firestore 前強制 `getIdToken(true)`，並對 `permission-denied` 靜默處理；(2) `_signInWithCredential` 各路徑在 Firestore 操作前加 `getIdToken(true)`，並以 try-catch 包裹 `_ensureUserDoc` / `_promoteUser`，確保 Auth 成功就回傳 success，不讓 Firestore 錯誤中斷登入流程。 |
| v3.2.2 | 2026-03-15 | **feat(copy)**：全面整理三步驟引導文字 — (1) HomeScreen：tagline 換為三步驟橫列（① 📷 選照片 › ② 🎨 選風格 › ③ 😄 選情緒），按鈕區上方加「步驟 1／3」說明；(2) StyleSelectionScreen：副標改為「先選外框形狀，再選最喜歡的視覺風格」，未選提示改為「點一下卡片即可選取」，CTA 改為「確認風格，選情緒 →」；(3) EmotionSelectionScreen：副標改為「每種情緒各生成一張，可選 4–12 種」；(4) EditorScreen：TopBar 改為「右滑生成・左滑跳過」，loading 副標動態顯示實際情緒數量（不再 hardcode 8），SnackBar 改為「✨ N 款概念就緒！右滑生成（耗 1 點），左滑跳過」。 |
| v3.2.1 | 2026-03-15 | **fix(nav)**：將步驟 2「選擇風格」從 modal bottom sheet 改為全螢幕路由 `StyleSelectionScreen` — (1) 新增 `lib/features/home/screens/style_selection_screen.dart`：與 `EmotionSelectionScreen` 相同的標頭樣式（返回鍵 + 步驟 2／3 badge + 底部 CTA bar），風格卡片改為「點選選取 + 勾選角標」互動（取代舊的「點即跳轉」）；(2) 新增 `StyleSelectArgs` 與 `/style-select` 路由；(3) `home_screen.dart` 改為 `context.push('/style-select')`，移除 `showModalBottomSheet` 及相關 class；(4) Back 按鈕導向修正：步驟 3 返回步驟 2、步驟 2 返回首頁，符合預期導覽行為。 |
| v3.2.0 | 2026-03-15 | **feat(ux)**：新增「情緒選擇」步驟，重構使用者動線為三步驟（選圖 → 選風格 → 選情緒 → 製作）— (1) 新增 `EmotionSelectionScreen`：全螢幕 4×4 情緒格子，顯示 emoji + 中文名稱，預設選 8 種，最多 12 種，底部顯示「開始製作 N 款」CTA；(2) 新增 `/emotion-select` 路由與 `EmotionSelectArgs`；(3) `EditorArgs` 新增 `categoryIds` 欄位；(4) `editor_provider.initialize()` 新增 `initialCategoryIds` 參數，在進入 Editor 前即套用使用者選擇；(5) `EditorScreen` 將情緒標頭移至卡片上方（大 emoji 36px + 情緒名稱 20px + AI 標語），取代原有小 pill；(6) 更新 `README.md` 反映新流程與架構。 |
| v3.1.85 | 2026-03-15 | **fix(rules)**：移除 `firestore.rules` 中 `users/{uid}` 與 `creditHistory` 的 `request.app != null` 條件 — 因客戶端尚未整合 App Check SDK，`request.app` 恆為 null，導致點數讀取（`getCredits`）、點數增加（`addCredits`）、點數歷史讀取（`creditHistoryProvider`）全部 `permission-denied`；安全性改由 Cloud Functions 層的 `enforceAppCheck: true` + `if (!request.app)` 雙重保護。 |
| v3.1.84 | 2026-03-14 | **feat(security)**：新增 Firebase App Check 保護 Cloud Functions — `generateStickerSpecs` 與 `generateStickerImage` 加入 `enforceAppCheck: true`，並在 handler 內補上 `if (!request.app)` 手動檢查；`firestore.rules` 加入 `request.app != null` 條件。 |
| v3.1.77 | 2026-03-14 | **feat(loading)**：以影片取代 Flutter 手刻 loading 動畫 — (1) 新增 `video_player: ^2.9.2` 依賴；(2) `_FunLoadingViewState` 改用 `VideoPlayerController.asset('assets/loading_animation.mp4')`，靜音迴圈播放，`FittedBox.cover` 填滿 70% 動畫區；(3) 刪除 `_ChaseStage`、`_GroomStage`（共 -423 行）；(4) 更新 `_imageMessages` 移除「貓洗臉」文案；(5) 保留相同的旋轉提示文字 + `_BounceDots` 進度指示器；錯誤 fallback：影片初始化失敗時靜默降級（`_videoError = true`）不 crash。 |
| v3.1.83 | 2026-03-14 | **fix(ui)**：修正首頁 "Magic Sticker" 標題字母 descender 被 ShaderMask 裁切問題 — `height` 從 1.1 調整為 1.2，給予足夠行高空間。 |
| v3.1.82 | 2026-03-14 | **chore(assets)**：替換 loading 動畫為 `loading_animation-square.mp4`，`VideoPlayerController` 對應更新。 |
| v3.1.81 | 2026-03-14 | **fix(prompt)**：Gemini 圖片生成 Prompt 全面改為繁體中文 — `sticker_generation_service.dart` 圓形／方形 Prompt 主體翻譯為中文結構（【畫布規格】【角色設計】【裝飾】【配色】【輸出】）；`sticker_style.dart` 的 `characterDesc`（6 種風格）與 `promptSuffix`（6 種風格）同步中文化，動態變數（`spec.emotion`、`spec.bgColor`）仍維持英文。 |
| v3.1.80 | 2026-03-14 | **fix(precision)**：優化貼圖精準度 — (1) `sticker_canvas.dart` Auto-fit scale 改用正確 Cover 公式：`max(iW/contentW, iH/contentH) × 1.05`，修正原本 `max÷max` 導致非正方形內容短軸留空隙的問題；(2) `sticker_generation_service.dart` 強化圓形 Prompt：改為逐項 CRITICAL 結構，新增「4 corner pixels MUST be transparent」具體約束、明確指定角色位於圓圈上方 70% 區域、circle edge 改為「hard sharp alpha cutoff」措辭，提升 Gemini 理解精準度。 |
| v3.1.79 | 2026-03-14 | **chore(deps)**：`flutter pub get` 解析 `in_app_purchase ^3.2.0` 全部 transitive 依賴，更新 `pubspec.lock`（`in_app_purchase 3.2.3`、`in_app_purchase_android`、`in_app_purchase_platform_interface` 等）。 |
| v3.1.78 | 2026-03-14 | **feat(billing)**：點數商店上線 — 新增 `CreditShopSheet`（嘗鮮包 8pt NT$30 / 創作者包 24pt NT$79 / 達人包 80pt NT$199），`in_app_purchase ^3.2.0` 串接 Google Play；廣告每日上限 3 次（`SharedPreferences` 跨日重置）；購買入口整合至首頁 credit badge 帳號 sheet。 |
| v3.1.77 | 2026-03-14 | **feat(loading)**：以 `loading_animation.mp4` 取代手刻貓咪 Loading 動畫，移除 `_ChaseStage`/`_GroomStage`（-423 行），改用 `VideoPlayerController`。 |
| v3.1.76 | 2026-03-14 | **chore(assets)**：新增 loading 動畫影片素材（`assets/loading_animation.mp4`，從原始長檔名重命名），供後續取代現有 Flutter 動畫 loading 使用。 |
| v3.1.75 | 2026-03-14 | **fix(canvas)**：Auto-fit 改進 — (1) `_findContentBounds` 新增近黑色像素排除（R/G/B < 40），消除黑色外框干擾 bounding box；加入 fallback pass（排除黑色後無彩色像素時改用 alpha-only）；回傳值補上 `imageHeight`；(2) `_autoFitGeneratedImage` 新增置中 offset 計算，將彩色內容中心對齊畫布中心（Transform.scale 公式補償）；新增 `_canvasSize == Size.zero` 防呆，`initState` 呼叫時延至下一幀再執行；(3) `StickerGenerationService` 加入 `kDebugMode` Prompt 印出（格式化 debugPrint），方便測試調整 Prompt 內容。 |
| v3.1.67 | 2026-03-14 | **feat(history)**：新增「生成紀錄」功能 — (1) `StickerArchiveService`：點數圖片生成後立即以 fire-and-forget 方式將 AI PNG 存入 `app_documents/sticker_archives/`，元資料存於 `SharedPreferences`，上限 200 筆自動淘汰最舊；(2) `StickerHistoryScreen`：2 欄 Grid，支援下載至相簿（`gal`）、長按刪除；(3) HomeScreen AppBar 新增 `history_rounded` 入口按鈕；(4) 新增 `/sticker-history` 路由；零新依賴。 |
| v3.1.66 | 2026-03-14 | **fix(billing)**：`creditHistoryProvider` 在查詢前呼叫 `user.getIdToken()` 強制刷新 JWT（修正 `userChanges()` emit 與 Firestore token 傳播的 race condition）；`permission-denied` 改為 graceful 降級回傳 `[]` 並記錄 info log，不再寫入 Crashlytics，消除誤報警告。 |
| v3.1.65 | 2026-03-14 | **fix(billing)**：`creditHistoryProvider` 改為 `rethrow` 取代 `return []`，讓 Firestore 查詢失敗時 UI 正確顯示「載入失敗，請稍後再試」而非誤顯「還沒有點數紀錄」。 |
| v3.1.64 | 2026-03-14 | **feat(loading)**：AI 生圖 loading 動畫改為「貓咪洗臉」— `_PaintStage` → `_GroomStage`：舔爪（0~18%）→ 橢圓軌跡洗臉（18~78%）→ 落爪＋✨閃光＋💕愛心上浮（78~100%）；背景改為 🫧 泡泡漂移；訊息同步更新為洗臉主題。 |
| v3.1.63 | 2026-03-14 | **fix(edit)**：編輯畫面圓形貼圖改用圓形虛線框 — `_BoundaryPainter` 加入 `stickerShape` 參數，圓形時改畫 `addOval` 虛線；外層 ClipRRect 圓形時改為 `ClipOval`。 |
| v3.1.62 | 2026-03-14 | **fix(cf)**：更新 `GEMINI_TEXT_MODEL` 預設值 `gemini-2.0-flash` → `gemini-2.5-flash`（2.0-flash 將於 2026-06-01 退役；`gemini-3-flash` 為不存在的 model ID，導致 404 錯誤）。 |
| v3.1.61 | 2026-03-13 | **fix(canvas)**：編輯 popup 也套用 Auto-fit — `initState` 補上 `_autoFitGeneratedImage()` 呼叫，解決編輯畫面開啟時 `generatedImage` 已存在導致 `didUpdateWidget` 條件不觸發的問題。 |
| v3.1.60 | 2026-03-13 | **feat(canvas)**：AI 圓形貼圖自動填滿畫布 — (1) Gemini Prompt 修正：圓圈改為填滿 100% 畫布、明確禁止任何顏色的描邊/外框；(2) `StickerCanvas` 新增 `_autoFitGeneratedImage()`：圖片首次到達時以 `compute()` 在 isolate 偵測非透明 bounding box，計算精確 scale（1.05× overshoot 裁掉殘留薄邊框），取代固定 `1.12×`。 |
| v3.1.59 | 2026-03-13 | **chore**：merge main (v3.1.55+176) → `claude/fix-gemini-auth-errors-O28Sx`，解決 PR #129 版本衝突，版本遞增至 v3.1.59+180。 |
| v3.1.55 | 2026-03-13 | **chore**：解決 PR #129 合併衝突（同步版本文件），更新 `pubspec.yaml` 與 `PRD.md` 版本號，確保分支可順利合併。 |
| v3.1.51 | 2026-03-13 | **fix(ux)**：情感標籤 fallback + EmotionPickerSheet 捲動修復 — (1) `_EmotionLabel` 改為 fallback：AI 未回傳 categoryId（舊 CF 版本）時自動使用 `selectedCategoryIds[i]`，確保標籤永遠顯示；(2) `EmotionPickerSheet` 外層改為 `SingleChildScrollView`，防止 4×4 格在小螢幕溢出並確保確認按鈕可見；(3) 標題列選取數改為即時顯示「已選 N 種（4–12）」 |
| v3.1.50 | 2026-03-13 | **feat**：情感類型標示 + 自訂情感 + SnackBar 修復 — (1) 新增 `EmotionCategory` 模型（16 種，前 8 預設）及 `kDefaultCategoryIds`；`StickerSpec` 加入 `categoryId` 欄位；`GeminiService.generateStickerSpecs` 加入 `categoryIds` 參數，改為固定類別生成（client 傳 categoryIds，server 依清單順序呼叫 Gemini 並要求回傳 categoryId）；Cloud Function `generateStickerSpecs` 加入 server-side `CATEGORY_HINTS` 對照表，支援 4–12 種 categoryIds；(2) `EditorState` 加入 `categoryIds`/`selectedCategoryIds`；`EditorProvider` 同步 categoryIds 並新增 `updateSelectedCategories()`；(3) `editor_screen.dart` 在卡片下方新增 `_EmotionLabel` chip 顯示「👋 打招呼 · 1/8」；`_TopBar` 加入情感 picker 按鈕（😊）；新增 `EmotionPickerSheet`（4×4 格子，4–12 選，勾選動畫）；(4) 所有浮動 SnackBar 加入 `margin: EdgeInsets.fromLTRB(12, 0, 12, 96)` 避免遮住底部按鈕 |
| v3.1.49 | 2026-03-13 | **ux**：`StickerEditSheet` 編輯畫面擴大為滿版——sheet 改為 90% 螢幕高度，canvas 由 `ConstrainedBox(maxHeight: 30%)` 改為 `Expanded + LayoutBuilder`（取寬高最小值確保正方形），填滿可用空間；控制列縮至底部；移除 `Flexible + SingleChildScrollView` |
| v3.1.48 | 2026-03-13 | **fix(deploy)**：`functions/package.json` deploy script 拆為三步驟：`build → firebase deploy → set-iam`，新增獨立 `set-iam` script 在每次部署後強制以 gcloud 設定 `allUsers → roles/run.invoker`（`generatestickerspecs` + `generatestickerimage`），徹底解決 `firebase deploy` 不穩定套用 `invoker:public` 造成 Cloud Run IAM 攔截的問題 |
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
