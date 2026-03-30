# 用 Claude Code 和一支手機，從零打造一款上架 App

## 背景

我的身份是產品經理，有一些程式開發的基礎——看得懂程式碼、寫得出 pseudo code，但從來沒有獨立完成過一個完整的生產級 App。

這個限制讓我在工作上長期處於一個尷尬位置：夠懂技術、能跟工程師溝通，但一旦沒有工程師，就什麼也做不了。

直到我開始用 Claude Code。

---

## 這個專案是什麼

**Magic Sticker** 是一款 AI LINE 貼圖生成器。用戶選一張照片、挑情緒風格，Gemini AI 自動生成符合 LINE Creators Market 規格的 Q 版卡通貼圖，透過 Tinder 式滑卡介面挑選後一鍵存入相簿，即可直接上架。

現在它已經同時上架 Google Play 和 App Store。

---

## 開發環境：一支 iPhone

這個專案最特別的限制是：**我幾乎全程用手機開發**。

Claude Code 的 iOS App 讓我可以在通勤、睡前、等待的碎片時間直接寫 issue、看錯誤、下指令。這不是一個「用 AI 幫你生成程式碼貼上去」的流程——而是一個真正的對話式開發：描述問題、看 Claude 修改、確認結果、繼續下一步。

---

## 技術規模

從 3 月 1 日建立 Git 專案，到 3 月底雙平台送審，**整個過程不到一個月**。這段時間我沒有請假，沒有整塊的開發時間——利用的是照顧小孩的空檔、通勤路上、下班後的零碎時間。

這個專案最終長成這樣：

| 指標 | 數字 |
|---|---|
| Dart 程式碼 | 66 個檔案 / 約 18,000 行 |
| Git commits | 128 個 |
| Flutter 套件依賴 | 25+ 個 |
| Cloud Functions | 6 個（Gemini 代理、IAP 驗證、App Config） |
| GitHub Actions Workflows | 4 個 |
| 上架平台 | Google Play + App Store |

---

## 功能深度

表面上是一個「選照片生成貼圖」的 App，但底層工程比想像中複雜。

**AI 生成架構**

Gemini API Key 從來不進 App。所有 AI 呼叫都透過 Firebase Cloud Functions 代理，結合 Firebase App Check（Android 用 Play Integrity）和 Firebase Auth 雙重驗證，確保 API 只服務真實的已登入用戶，防止金鑰洩漏和濫用。

生成流程也刻意設計成延遲觸發——用戶進入編輯畫面時立刻看到佔位卡片，右滑的瞬間才觸發 AI 分析，讓操作感受流暢不卡頓。

**點數與變現系統**

整套點數系統都是原子性操作：Cloud Functions 在扣點和呼叫 Gemini API 之間做 Firestore Transaction，確保不會有扣了點但沒生成、或生成失敗點數沒退回的邊緣情況。

變現則整合了：
- Google AdMob Rewarded Ad（看廣告換點數）
- iOS / Android In-App Purchase（購買點數包、Pro 自訂功能）
- 收據驗證也走 Cloud Functions，不在 App 端處理

**Pro 自訂模式**

用戶可以輸入任意風格描述（「賽博龐克霓虹」）和情緒描述（「被截止日期追殺的崩潰感」），生成完全客製化的貼圖。這涉及 4 種不同的生成路由矩陣，要根據「有沒有自訂風格 × 有沒有自訂情緒」的組合決定是否跳過 Tinder 滑卡、跳轉哪個頁面、消耗幾點。

---

## CI/CD：我沒有 Mac，所以 CI 幫我 build iOS

這是我在這個專案裡最有成就感的部分之一。

我沒有 macOS 設備，但 iOS App 必須在 Mac 上 build 和簽名。解法是把整個 iOS build 流程搬到 GitHub Actions：

- **`main_build.yml`**：push 到 main 或手動觸發，執行 Dart 分析、Android AAB build + 上傳 Firebase App Distribution、iOS IPA build + 上傳 TestFlight，以及 Cloud Functions 和 Firestore Rules 的 deploy
- **`deploy_hosting.yml`**：只在 `public/` 靜態網頁有變更時觸發，獨立部署 Firebase Hosting，與 App release 流程完全解耦
- **`pr_check.yml`**：每個 PR 先跑 version guard（版本號沒遞增就擋住）、Dart analyze、Flutter test、Cloud Functions TypeScript 編譯
- **`generate_previews.yml`**：自動生成貼圖預覽圖

iOS build 涉及 Apple Developer Certificate、Provisioning Profile、App Store Connect API Key——這些全部存在 GitHub Secrets，CI runner 在 build 時動態注入，整個流程不需要我開一次 Xcode。

---

## 遇到的幾個有趣問題

**LLM 的錨定偏差**

Cloud Function 的 prompt 裡用了單一範例（「打招呼」情緒），結果所有貼圖的情緒都往「打招呼」靠攏——即使我要求生成「擔心」。

解法是兩層防禦：改 prompt 給 3 個差異化範例降低偏差，再加一個 `normalizeSpecs()` server-side 函數強制覆蓋錯誤的 categoryId，讓 LLM 的幻覺不影響最終結果。

**CSS source order 的老陷阱**

靜態隱私政策頁面的桌機雙欄排版一直不正常，查了很久才發現：`.toc { display: none }` 這條規則被放在 `@media (min-width: 1100px)` 的後面，因為 CSS 相同 specificity 下後面的規則贏，導致 TOC 在桌機也永遠隱藏，main 內容跑到那個 200px 的 grid 欄位裡。

**Android Gradle DSL 位置**

`ndk { debugSymbolLevel 'FULL' }` 必須放在 `buildTypes.release {}` 裡面，放在 `android {}` 頂層會報「找不到這個方法」——但錯誤訊息非常不直觀，花了一段時間才定位到。

---

## 這個過程讓我學到什麼

用 Claude Code 開發和傳統找外包、找工程師協作最大的差異，不是「生成速度快」，而是**決策的所有權**。

每一個技術決策——要用 Riverpod 還是 Provider、Cloud Functions 要怎麼拆、CI pipeline 要不要拆分、iOS build 要怎麼簽名——我都必須理解、做決定、對結果負責。Claude 是我的執行夥伴，不是黑盒子。

這讓我對技術的理解從「我知道這個東西存在」升級到「我知道這個東西在我的系統裡是怎麼運作的」。

對一個 PM 來說，這個差距比想像中大。

---

## 數字總結

- **1 個月**，從零到雙平台送審
- 利用零碎時間：通勤、照顧小孩的空檔、下班後
- 約 18,000 行 Dart 程式碼 / 128 個 commits
- 完整的 CI/CD pipeline，沒有用過一次 Xcode
- 主要開發工具：Claude Code iOS App + 一支 iPhone

---

*Magic Sticker 已上架：[Google Play](https://play.google.com/store/apps/details?id=com.magicsticker.magic_sticker) ｜ [App Store](https://apps.apple.com/app/id6761015408)*

---

## Resume 摘要（英文）

> Built *Magic Sticker*, an AI-powered LINE sticker generator (Flutter, Android + iOS), solo in one month using Claude Code on mobile during fragmented time — commuting, after work, and while parenting. Delivered ~18,000 lines of Dart code, 6 Firebase Cloud Functions, and a full GitHub Actions CI/CD pipeline including automated iOS builds and App Store submissions, without dedicated engineering resources or a Mac.
