# Google Play 上架資料 — Magic Sticker

> 最後更新：2026-03-10 ｜ 版本 v3.0.2+97

---

## 1. 基本資料

| 欄位 | 內容 |
|---|---|
| **應用程式名稱** | Magic Sticker |
| **套件名稱（Package ID）** | `com.magicsticker.magic_sticker` |
| **版本名稱** | 3.0.2 |
| **版本代碼（Version Code）** | 97 |
| **最低 Android 版本** | Android 8.0（API 26） |
| **目標 Android 版本** | Android 14（API 34） |
| **類別** | 工具 / 攝影 |
| **內容分級** | 所有人（Everyone）|
| **定價** | 免費（含廣告 + 點數 IAP） |

---

## 2. 商店說明文字

### 簡短說明（80 字以內）
```
AI 一鍵把你的照片變成 LINE 貼圖！Gemini 自動生成 8 張 Q 版卡通貼圖，右滑收藏直接上架。
```

### 完整說明（4000 字以內）
```
✨ 只需一張照片，30 秒變成專屬 LINE 貼圖！

Magic Sticker 是全台首款 AI 自動貼圖生成器：
選一張你的照片 → AI 自動產出 8 張符合 LINE Creators Market 規格的圓形卡通貼圖
→ 像 Tinder 一樣滑卡挑選 → 一鍵儲存至相簿 → 直接上架！

🎨 核心功能
• AI 自動生成：Gemini 2.0 Flash 分析人物氣質，產出 8 張風格各異的 Q 版貼圖
• Tinder 滑卡：右滑收藏 ❤️，左滑跳過 ✕，挑選最喜歡的
• 即時編輯：點圖可修改文字、字型、配色、圖片縮放與位移
• 多種風格：Q版卡通 / 普普風 / 像素風 / 素描，一鍵切換重新生成
• 5 種繁中字體：黑體、圓體、書法、可愛、手寫
• 符合 LINE 規格：370×320 px PNG 透明背景，< 1 MB，直接上架無需裁切

🔒 隱私安全
• Gemini API Key 存放於 Firebase Cloud Functions，不打包進 App
• 照片僅傳送至 AI 生成使用，不儲存於伺服器

💡 點數系統
• 首次免費體驗
• 看廣告可獲得額外點數
• 登入帳號享更多點數

---
⚠️ 本 App 使用 Google Gemini AI 生成圖片，需要網路連線。
生成圖片風格為卡通插畫，非照片或寫實圖像。
```

---

## 3. 關鍵字（ASO）

```
LINE貼圖, 貼圖製作, AI貼圖, 貼圖生成器, 自製貼圖, 照片貼圖, 卡通貼圖,
AI生成, Gemini, 貼圖上架, LINE Creators, 表情貼圖, 個人化貼圖
```

---

## 4. 圖片素材規格

| 素材 | 規格 | 說明 |
|---|---|---|
| **App 圖示** | 512 × 512 px PNG（無透明） | 已有 `assets/app_icon.png` |
| **功能圖片（Feature Graphic）** | 1024 × 500 px JPG/PNG | 需製作 |
| **手機截圖** | 最少 2 張，建議 4–8 張 | 16:9 或 9:16，≥ 1080px |
| **平板截圖** | 選填 | 7吋 / 10吋 |

### 建議截圖內容
1. 首頁選圖畫面（選取照片 CTA）
2. AI 生成中動畫（貓追老鼠等待畫面）
3. Tinder 滑卡結果（8 張貼圖堆疊）
4. 貼圖編輯底部抽屜（字型 / 配色選擇）
5. 最終儲存成功畫面

---

## 5. 權限說明（Play 政策申報）

| 權限 | 用途 | 是否必要 |
|---|---|---|
| `CAMERA` | 拍照選取人物照片 | 非必要（可改用相簿） |
| `READ_MEDIA_IMAGES` | Android 13+ 讀取相簿圖片 | **必要** |
| `READ_EXTERNAL_STORAGE` | Android 12 以下讀取相簿 | 必要（舊版相容） |
| `WRITE_EXTERNAL_STORAGE` | Android 9 以下儲存圖片 | 必要（舊版相容） |
| `INTERNET` | 呼叫 Gemini AI / Firebase | **必要** |

---

## 6. 內容分級問卷（IARC）

| 問題 | 答案 |
|---|---|
| 暴力內容 | 無 |
| 性暗示內容 | 無 |
| 語言 | 無不雅語言 |
| 賭博 | 無 |
| 使用者產生內容（UGC） | 無（圖片不上傳至社群） |
| 位置資訊 | 不使用 |
| 個人資料蒐集 | Firebase Auth（匿名/Google/Apple），用於點數系統 |

→ 預計分級：**Everyone（E）**

---

## 7. 資料安全申報（Data Safety）

| 資料類型 | 蒐集 | 分享 | 用途 |
|---|---|---|---|
| 使用者 ID（Firebase UID） | ✅ | ❌ | 點數管理 |
| 照片 / 圖片 | ✅（傳送給 AI） | ❌（不儲存） | 生成貼圖 |
| 應用程式互動（Analytics） | ✅ | ❌ | 改善體驗 |
| 崩潰日誌（Crashlytics） | ✅ | ❌ | 除錯 |
| 廣告 ID（AdMob） | ✅ | ✅（Google） | 廣告投放 |

**傳輸加密：** 是（HTTPS）
**刪除請求：** 使用者可要求刪除帳號（Firebase Auth 刪除）

---

## 8. AdMob 設定

| 項目 | 值 |
|---|---|
| **AdMob App ID** | `ca-app-pub-0557904547936841~2165720919` |
| **廣告類型** | Rewarded Ad（看廣告換點數） |
| **廣告政策** | 不在兒童導向 App 中投放個人化廣告 |

---

## 9. 上架檢查清單

### 技術
- [ ] 簽名 KeyStore 已建立並備份（`key.properties` 不進 git）
- [ ] `flutter build appbundle --release` 產出 `.aab`（Play Store 要求）
- [ ] ProGuard/R8 規則確認（`proguard-rules.pro`）
- [ ] Firebase App Distribution 測試通過

### 商店資料
- [ ] App 圖示 512×512 px 上傳
- [ ] Feature Graphic 1024×500 px 上傳
- [ ] 截圖至少 2 張上傳
- [ ] 簡短說明填寫（80 字內）
- [ ] 完整說明填寫
- [ ] 內容分級問卷填寫完成
- [ ] 資料安全申報填寫完成
- [ ] 隱私政策 URL 填寫（**必填，無法上架**）

### 政策
- [ ] 隱私政策頁面上線（Firebase Hosting 或其他）
- [ ] 廣告政策申報（含 AdMob）
- [ ] 若使用 Google Sign-In：OAuth 驗證申請（Google API Console）

---

## 10. 隱私政策（必填）最低內容

隱私政策需公開於網路（例如 Firebase Hosting），包含：

```
1. 蒐集哪些資料：Firebase Auth、匿名 ID、使用行為、崩潰日誌
2. 如何使用：提供 App 功能、改善服務
3. 第三方服務：Google Firebase、Google AdMob、Google Gemini AI
4. 資料保留：帳號刪除後移除
5. 聯絡方式：開發者 email
```

---

## 11. 發布流程

```
1. flutter build appbundle --release
   → build/app/outputs/bundle/release/app-release.aab

2. Google Play Console → 製作版本 → 上傳 .aab

3. 填寫版本說明（中文）：
   版本 3.0.2
   • AI 貼圖生成架構升級，Gemini API 金鑰完全不存於 App
   • 效能與穩定性改善

4. 推送至正式版（或先推 20% 分階段發布）
```
