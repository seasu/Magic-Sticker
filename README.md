# Magic Sticker — AI 一鍵產 LINE 貼圖

> 選一張照片、挑你要的情緒、Gemini AI 自動生成專屬 LINE 貼圖，Tinder 滑卡逐一製作，一鍵存入相簿。

---

## 功能特色

| 功能 | 說明 |
|---|---|
| 📷 選取照片 | 從相簿選取或直接拍攝任意人物／寵物／物件照片 |
| 🎨 6 種貼圖風格 | Q版卡通、Pop Art、像素風、素描、水彩、寫實照片 |
| 😄 自訂情緒組合 | 從 16 種情緒中選 4–12 種，自由搭配你想要的貼圖套組 |
| 🤖 AI 免費預覽 | Gemini 分析照片，免費生成每種情緒的貼圖文案與配色 |
| 🃏 Tinder 滑卡挑選 | 右滑保留 ❤️（耗 1 點）左滑跳過 ✕，逐張確認後才花點數 |
| ✏️ 即時編輯 | 點圖進入編輯器：文字、字型、字體大小、文字位置、配色、風格 |
| 💾 一鍵儲存 | 存入相簿，符合 LINE Creators Market 規格（370×320 px PNG） |
| 📜 生成紀錄 | 自動保存所有生成過的貼圖，方便回顧與再下載 |

---

## 使用流程

```
1. 📷 選照片（相簿或相機）
        ↓
2. 🎨 選風格 + 形狀（圓形 / 方形）
        ↓
3. 😄 選情緒（4–12 種，預設 8 種）
        ↓
4. 🤖 AI 免費分析 → 生成每種情緒的文案概念
        ↓
5. 🃏 Tinder 滑卡：
     右滑 → 花 1 點生成這張貼圖 → 自動儲存相簿
     左滑 → 跳過這種情緒
        ↓
6. ✅ 全部滑完 → 貼圖套組完成！
```

---

## 點數說明

| 動作 | 點數消耗 |
|---|---|
| 分析照片＋生成文案概念 | **免費** |
| 生成一張貼圖圖片 | **1 點** |
| 生成失敗（API 錯誤） | **自動退還** |

取得點數：每日看廣告、登入獎勵、或購買點數包（8 / 24 / 80 點）。

---

## 快速開始

### 環境需求
- Flutter 3.19+
- Dart 3.3+
- Android 8.0+ (`minSdkVersion 26`) / iOS 15.0+

### 安裝執行

```bash
# 安裝依賴
flutter pub get

# Debug 模式（使用 Firebase Cloud Functions，金鑰由 Secret Manager 管理）
flutter run

# Release APK
flutter build apk --release

# Release AAB（上架 Google Play）
flutter build appbundle --release
```

### Firebase 設定

1. 在 [Firebase Console](https://console.firebase.google.com) 建立或連接專案
2. 下載 `google-services.json` 放至 `android/app/`
3. 下載 `GoogleService-Info.plist` 放至 `ios/Runner/`
4. 部署 Cloud Functions：`cd functions && firebase deploy --only functions`

---

## 技術架構

```
Flutter (Dart)
├── 狀態管理：Riverpod (NotifierProvider / FutureProvider)
├── 路由：go_router
├── AI 生成：Gemini API（透過 Firebase Cloud Functions 代理，不在 App 內存金鑰）
├── 圖片儲存：gal
├── 字型：google_fonts
├── 廣告：Google Mobile Ads
├── 付款：in_app_purchase
└── 監控：Firebase Crashlytics + Analytics
```

### 安全架構

- Gemini API Key 存於 **Cloud Functions Secret Manager**，App 端完全不持有金鑰
- Cloud Functions 以 **Firebase Auth** 驗證用戶身份，防止未登入呼叫
- Firestore 以 Security Rules 確保使用者只能讀寫自己的資料

### 生成流程（技術）

```
選圖 → Resize ≤1080px (Flutter 端)
  → generateStickerSpecs (Cloud Function, 免費)
    └─ 驗證 Auth → 呼叫 Gemini Text API → 回傳 N 組 {text, emotion, bgColor, categoryId}
  → 使用者滑卡右滑
    → generateStickerImage (Cloud Function, 扣 1 點)
      └─ 驗證 Auth → Transaction 原子扣點 → 呼叫 Gemini Image API → 回傳 PNG
  → RepaintBoundary 合成最終貼圖 → Gal 儲存相簿
```

---

## LINE Creators Market 貼圖規格

| 項目 | 規格 |
|---|---|
| 尺寸 | 370×320 px |
| 格式 | PNG（透明背景） |
| 單檔上限 | 1 MB |
| 最少數量 | 8 張（本 App 每次最少可產 4 張）|

儲存後可直接至 [LINE Creators Market](https://creator.line.me) 上架。

---

## 版本歷史

詳見 [PRD.md](./PRD.md#6-版本歷史)

---

## 開發指令集

詳見 [CLAUDE.md](./CLAUDE.md)（AI 開發規範）

---

## License

MIT
