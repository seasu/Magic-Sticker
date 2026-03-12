# Magic Sticker — AI 一鍵產 LINE 貼圖

> 選一張照片，Gemini AI 自動幫你生成 8 張圓形卡通 LINE 貼圖，Tinder 滑卡挑選，一鍵存入相簿。

---

## 功能特色

| 功能 | 說明 |
|---|---|
| 📷 選取照片 | 從相簿選取任意人物/寵物/物件照片 |
| 🤖 AI 自動生成 | Gemini 2.0 Flash 依照片內容生成 8 張 Q 版卡通 LINE 貼圖 |
| 💬 8 種情感貼圖 | 打招呼、讚美、驚訝、尷尬、生氣、開心、思考、道別 |
| 🃏 Tinder 滑卡 | 右滑保留 ❤️ 左滑跳過 ✕，直覺挑選喜歡的貼圖 |
| ✏️ 即時編輯 | 點圖開啟編輯器：文字、字型、字體大小、文字位置、配色、產圖風格 |
| 💾 一鍵儲存 | 直接存入相簿，符合 LINE Creators Market 規格（370×320 px PNG） |

---

## 截圖

| 首頁 | 生成中 | 滑卡挑選 | 貼圖編輯 |
|---|---|---|---|
| 選取照片 | 🐱 貓追老鼠等待動畫 | Tinder 風格卡片 | 字體/配色/位置調整 |

---

## 快速開始

### 環境需求
- Flutter 3.19+
- Dart 3.3+
- Android SDK 26+ / iOS 15.0+

### 安裝執行

```bash
# 安裝依賴
flutter pub get

# 設定 Gemini API Key（在 .env 或 dart-define）
flutter run --dart-define=GEMINI_API_KEY=your_key_here

# Debug 模式
flutter run

# Release APK
flutter build apk --release
```

### Firebase 設定

1. 在 [Firebase Console](https://console.firebase.google.com) 建立專案
2. 下載 `google-services.json` 放至 `android/app/`
3. 下載 `GoogleService-Info.plist` 放至 `ios/Runner/`

---

## 技術架構

```
Flutter (Dart)
├── 狀態管理：Riverpod
├── 路由：go_router
├── AI 生成：google_generative_ai (Gemini 2.0 Flash)
├── 圖片儲存：gal
├── 字型：google_fonts
└── 監控：Firebase Crashlytics + Analytics
```

### 生成流程

```
選圖 → Resize (≤1080px)
  → Gemini generateStickerSpecs (8 組文案)
  → 並行生成 8 張貼圖圖片
  → 每張完成後即時顯示
  → 使用者滑卡挑選 → 儲存相簿
```

---

## LINE Creators Market 貼圖規格

| 項目 | 規格 |
|---|---|
| 尺寸 | 370×320 px |
| 格式 | PNG（透明背景） |
| 單檔上限 | 1 MB |
| 最少數量 | 8 張（本 App 一次產出完整 8 張）|

儲存後可直接至 [LINE Creators Market](https://creator.line.me) 上架。

---

## 版本歷史

詳見 [PRD.md](./PRD.md#6-版本歷史)

---

## 風格示意圖 (Style Previews)

編輯器中的 6 種風格選擇（Chibi、Pop Art、Pixel、Sketch、Watercolor、Photo）各有一張示意圖，存放於 `assets/images/preview_<style>.png`。

示意圖由 Gemini 2.0 Flash 依據 `assets/images/cat_source.png` 轉換生成。

### 重新生成示意圖

至 GitHub Actions → **Generate Style Preview Images** → **Run workflow**。

| 參數 | 說明 |
|---|---|
| `force_regenerate` | `false`（預設）：只補生缺少的圖；`true`：強制全部重新生成 |

> **備註：** 若 `cat_source.png` 不存在，腳本會先用 Gemini 自動生成一張，再進行風格轉換。

---

## 開發指令集

詳見 [CLAUDE.md](./CLAUDE.md)（AI 開發規範）

---

## License

MIT
