# PM 最常被嘲笑「只會出一張嘴」— 這次，我真的用嘴做出了一個產品

> 一個工程師轉 PM，用一支 iPhone 和 Claude Code，30 天內從零交付雙平台上架的生產級 App。862 個 commits、18,000 行程式碼、完整 CI/CD pipeline — 而且從沒打開過 Xcode。

---

## 不上不下的尷尬

我的背景是工程師轉 PM。

這意味著我看得懂程式碼、寫得出 pseudo code、能跟工程師用技術語言對話。但有一個問題：**我從來沒有獨立完成過一個完整的生產級 App。**

這讓我在工作上長期處於一個尷尬位置 — 夠懂技術、能拆需求、能 review code，但一旦沒有工程師，就什麼也交付不了。

你可能覺得「那就學啊」。但現實是：我有一個小孩要照顧，沒有整塊的學習時間，沒有 Mac 可以 build iOS，而且從 Flutter 到上架的完整鏈路，光是工具鏈就夠一個人卡三個月。

直到我開始用 Claude Code。

---

## 這個產品是什麼

**Magic Sticker** 是一款 AI LINE 貼圖生成器。

用戶的操作流程是這樣的：

1. **選一張照片** — 從相簿挑一張人像
2. **選風格** — 12 種預設風格（Q 版卡通、普普風、水彩…）或 Pro 自訂輸入
3. **選情緒** — 24 種情緒類別或 Pro 自訂描述
4. **Tinder 式滑卡** — 8 張貼圖逐一呈現，右滑生成並存入相簿，左滑跳過
5. **自行上架** — 帶著存好的貼圖去 LINE Creators Market 上傳

App 的職責到「存入相簿」為止。它不替你上架，但它把最耗時的部分 — AI 生成符合 LINE 規格的貼圖 — 全部自動化了。

現在它同時上架在 Google Play 和 App Store。

---

## 30 天，862 個 Commits

從 2026 年 3 月 4 日建立 Git 專案，到 4 月 2 日雙平台送審通過，**整整 30 天**。

這段時間我沒有請假，沒有整塊的開發時間。利用的全是碎片 — 通勤路上、小孩午睡的空檔、下班後到睡前的一兩個小時。

但碎片堆起來，長成了這個規模：

| 指標 | 數字 |
|---|---|
| **Git commits** | **862 個** |
| **Dart 程式碼** | 66 個檔案 / 約 18,000 行 |
| **Cloud Functions** | 1,745 行 TypeScript |
| **Flutter 套件依賴** | 30+ 個 |
| **GitHub Actions Workflows** | 5 個 |
| **上架平台** | Google Play + App Store |

862 個 commits 除以 30 天，平均每天將近 **29 個 commits**。

這不是「讓 AI 幫我生成一坨 code 然後 push」的數字。每一個 commit 背後都是一個對話：描述問題、看 Claude 修改、確認結果、遇到問題再描述、再修改。是一個真實的迭代過程。

---

## 開發環境：一支 iPhone + 對話

這個專案最特別的限制是：**我幾乎全程用手機開發。**

Claude Code 的 iOS App 讓我可以在任何地方、任何時間進入開發狀態。但這不是你想像的「手機上寫程式」— 我從頭到尾沒有手動寫過一行 production code。

我做的事情是：**用自然語言描述我要什麼，讓 Claude 去執行。**

一個典型的開發片段長這樣：

> **早上通勤（20 分鐘）：**
> 「昨天的 Rewarded Ad 在 iOS 上 fill rate 趨近 0，查一下是不是 ATT 授權的問題」
> → Claude 分析原因、修改 ads_service.dart、加入 ATT request、更新 Info.plist 的 SKAdNetworkItems
>
> **中午帶小孩放風的空檔（10 分鐘）：**
> 「PR check 的 version guard 沒有正確寫入 commit status，看一下 workflow」
> → Claude 修正 GitHub Actions YAML、push、確認 CI 通過
>
> **晚上小孩睡了（1.5 小時）：**
> 「Apple 退審了，說需要 Sign in with Apple。幫我加，包含 Cloud Function 的帳號刪除功能」
> → 從 auth_service、UI、Cloud Function、Firestore rules 一路改完

這就是「用嘴做產品」的意思。不是比喻 — Claude Code 就是對話式開發，你描述問題和需求，它讀懂你的 codebase、做出修改、你確認結果。整個過程的介面就是自然語言。

差別在於，每一個技術決策 — 要用 Riverpod 還是 Provider、Cloud Functions 怎麼拆、CI pipeline 要不要分離、iOS 簽名怎麼處理 — **我都必須理解、做決定、對結果負責。** Claude 是執行夥伴，不是黑盒子。

---

## 表面簡單，底層不簡單

表面上是一個「選照片生成貼圖」的 App，但如果你打開 PRD 會發現底層工程超乎想像。

### AI 安全架構

Gemini API Key 從來不進 App。

所有 AI 呼叫都透過 Firebase Cloud Functions 代理，結合 Firebase App Check（Android: Play Integrity）和 Firebase Auth 雙重驗證，確保 API 只服務真實的已登入用戶。這不是過度工程 — 反編譯一個 APK 拿到 API Key 大概只需要五分鐘。

生成流程也刻意做成延遲觸發：用戶進入編輯畫面時看到的是佔位卡片，右滑的瞬間才真正觸發 AI 生成。這讓操作感受流暢，也避免浪費算力在用戶可能左滑跳過的貼圖上。

### 點數系統的原子性

整套點數系統都是 Firestore Transaction：扣點和呼叫 Gemini API 包在同一個原子操作裡。不會有「扣了點但沒生成」或「生成失敗但點數沒退回」的邊緣情況。每一筆異動都寫入 creditHistory，用戶可以查閱完整紀錄。

變現整合了三條線：
- **AdMob Rewarded Ad** — 看廣告換點數
- **In-App Purchase** — 購買點數包、Pro 自訂功能（NT$49 一次性解鎖）
- **收據驗證** — 全部走 Cloud Functions server-side 驗證，不在 App 端處理

### Pro 自訂模式的路由矩陣

Pro 用戶可以輸入任意風格描述（「賽博龐克霓虹」）和情緒描述（「被截止日期追殺的崩潰感」），生成完全客製化的貼圖。

這看起來只是「多一個輸入框」，但背後是 4 種生成路由的排列組合 — 有沒有自訂風格 × 有沒有自訂情緒 — 每種組合的 prompt 結構、頁面跳轉、點數消耗邏輯都不同。

### CI/CD：我沒有 Mac，所以 CI 幫我 build iOS

這是整個專案裡我最有成就感的部分。

我沒有 macOS 設備，但 iOS App 必須在 Mac 上 build 和簽名。解法是把整個 iOS build 流程搬到 GitHub Actions：

- **`main_build.yml`** — push 到 main 觸發：Dart 分析、Android AAB + 上傳 Firebase App Distribution、iOS IPA + 上傳 TestFlight、Cloud Functions 與 Firestore Rules deploy
- **`pr_check.yml`** — 每個 PR：version guard（版本沒遞增就擋）、Dart analyze、Flutter test、TypeScript 編譯
- **`deploy_hosting.yml`** — 靜態網頁變更時獨立部署 Firebase Hosting
- **`functions_deploy.yml`** — Cloud Functions 獨立部署
- **`generate_previews.yml`** — 自動生成貼圖預覽圖

Apple Developer Certificate、Provisioning Profile、App Store Connect API Key — 全部存在 GitHub Secrets，CI runner 在 build 時動態注入。整個流程不需要我打開 Xcode，甚至不需要我有一台 Mac。

---

## 踩過的坑

做一個真實產品和做 side project 的差別，就是你會踩到那些「理論上不該花這麼多時間」的坑。

### LLM 的錨定偏差

Cloud Function 的 prompt 裡用了一個範例（「打招呼」情緒），結果所有貼圖的情緒都往「打招呼」靠攏 — 即使你指定「擔心」，生成出來的角色還是在笑著揮手。

解法是兩層防禦：改 prompt 給 3 個差異化範例（greeting / worried / angry）降低偏差，再加一個 `normalizeSpecs()` server-side 函數，強制校正 Gemini 回傳的 categoryId。讓 LLM 的幻覺不會影響最終結果。

### Apple 退審三連殺

第一次送審被退回，理由有三個：

1. **Guideline 4.8** — 必須支援 Sign in with Apple（因為已有 Google Sign-In）
2. **Guideline 5.1.1(v)** — 必須提供帳號刪除功能
3. **Guideline 2.1(b)** — IAP 商品必須在 App Store Connect 建立

第一項意味著要實作完整的 Apple 登入流（nonce + SHA256 + OAuthCredential），加上 Cloud Function 端的帳號刪除（含子集合清理）。光是 Sign in with Apple 的 CI 簽名問題（entitlements 注入、Provisioning Profile 配置），就產生了超過 10 個 commits 來回除錯。

這種問題不是 AI 能替你避開的 — 你得自己讀 Apple 的審核指南、理解規則、決定怎麼滿足。但 AI 可以幫你在幾個小時內把所有相關程式碼改完，而不是幾天。

### Android Gradle DSL 的位置陷阱

`ndk { debugSymbolLevel 'FULL' }` 必須放在 `buildTypes.release {}` 裡面。放在 `android {}` 頂層會報「Could not find method ndk()」— 但錯誤訊息完全不提示你該放哪裡。這種框架陷阱是 Claude 特別擅長解決的：它見過夠多案例，能直接告訴你正確位置。

---

## 這個過程讓我理解的事

### 從「知道」到「懂」

用 AI 開發和找工程師協作最大的差異，不是速度，是 **決策的所有權**。

找外包或工程師，你說需求，他們交付。你知道系統裡有 Riverpod、有 Cloud Functions、有 CI pipeline，但你不需要真的理解它們怎麼互動。

用 Claude Code 開發，每一步都要你做決定。「Firestore 的 credits 要用 Transaction 還是 batch write？」「App Check 的 enforcement 要開在哪些 endpoint？」「CI 的 iOS build 要不要跟 Android 分開跑？」— 這些不是 Claude 能替你決定的。

這讓我的技術理解從「我知道這個東西存在」升級到「我知道這個東西在我的系統裡是怎麼運作的」。

對一個 PM 來說，這個差距比想像中大。

### AI 是 co-pilot，不是 autopilot

這 30 天裡我最怕的不是技術問題，是方向錯誤。

Claude 可以在 10 分鐘內幫你實作一個功能，但它不會告訴你「這個功能根本不該做」。它可以幫你修好一個 bug，但它不會告訴你「這個 bug 的根因是架構設計有問題」。

**所有的「做什麼」和「為什麼做」的決策，始終在人這邊。**

AI 補上的是「怎麼做」的執行力。而對一個有技術背景的 PM 來說，「做什麼」和「為什麼」本來就是你的核心能力 — 差的只是那最後一哩路的執行。

### 一人產品團隊的時代

這個專案讓我意識到一件事：**PM 不再需要等工程師才能驗證想法。**

不是說工程師不重要 — 複雜系統、大規模服務、極致效能，這些永遠需要專業工程團隊。但如果你想驗證一個產品概念、做一個 MVP、甚至做到上架 — AI 已經可以讓一個有技術素養的 PM 獨立完成。

這不是未來式，這是現在式。我用一支 iPhone 和碎片時間就做到了。

---

## 數字總結

- **30 天**，從零到 Google Play + App Store 雙平台上架
- **862 個 commits**，平均每天近 29 個
- **~18,000 行** Dart 程式碼 + **1,745 行** Cloud Functions TypeScript
- **5 個** GitHub Actions workflows，完整 CI/CD
- **沒有 Mac**，沒打開過 Xcode，iOS 全靠 CI
- 利用碎片時間：通勤、小孩午睡、下班後
- 主要開發工具：**Claude Code iOS App + 一支 iPhone**

---

*Magic Sticker 已上架：[Google Play](https://play.google.com/store/apps/details?id=com.magicsticker.magic_sticker) ｜ [App Store](https://apps.apple.com/app/id6761015408)*

---

## Resume 摘要（英文）

> Built *Magic Sticker*, an AI-powered LINE sticker generator (Flutter, Android + iOS), solo in 30 days using Claude Code on an iPhone during fragmented time — commuting, after work, and while parenting. Delivered ~18,000 lines of Dart code, 1,745 lines of Cloud Functions TypeScript, and 5 GitHub Actions CI/CD workflows including automated iOS builds and App Store submissions, without a Mac or dedicated engineering resources. 862 commits. Shipped to both Google Play and App Store.

---

---

# 社群平台版本

以下內容從上方 Blog 文章萃取，針對各平台特性調整。

---

## X / Threads — Thread 格式

**1/ (Hook)**

PM 最常被嘲笑的就是「只會出一張嘴」。

上個月，我真的用嘴做出了一個產品。

一支 iPhone + Claude Code，30 天，862 個 commits，一款 App 同時上架 Google Play 和 App Store。

沒有 Mac，沒打開過 Xcode。🧵👇

**2/**

我的背景是工程師轉 PM。看得懂 code、能跟工程師溝通，但從沒獨立交付過一個完整 App。

Claude Code 改變了這件事 — 它是對話式開發。你描述問題，AI 讀你的 codebase、修改、你確認。整個介面就是自然語言。

真的是「說」出來的。

**3/**

30 天的成果：
- 18,000 行 Dart + 1,745 行 Cloud Functions
- 5 個 GitHub Actions CI/CD workflows
- iOS build 全靠 CI（我連 Mac 都沒有）
- Firebase App Check + Auth 雙重驗證
- Firestore Transaction 原子性點數系統
- In-App Purchase + AdMob 變現

全在通勤、帶小孩、下班後的碎片時間完成。

**4/**

最大的收穫不是「開發速度快」。

是決策的所有權。每一個技術決定 — 架構、狀態管理、CI 設計、安全策略 — 我都得理解、選擇、負責。

AI 補上的是執行力。「做什麼」和「為什麼」始終是人的工作。

**5/**

PM 不再需要等工程師才能驗證想法。

不是說工程師不重要，但如果你想做 MVP、驗證概念、甚至上架 — AI 已經可以讓有技術素養的人獨立完成。

這不是未來式，這是我用一支 iPhone 和碎片時間做到的現在式。

Magic Sticker 👉 [Google Play] [App Store]

完整文章 👉 [Blog 連結]

---

## LinkedIn

**用一支 iPhone 和 AI，我在 30 天內獨立交付了一款雙平台上架的 App。**

我是工程師轉 PM。有技術底子，但從沒有獨立完成過完整的生產級產品。

上個月，我用 Claude Code 的 iOS App，在通勤、帶小孩、下班後的碎片時間裡，從零打造了 Magic Sticker — 一款 AI LINE 貼圖生成器，現已上架 Google Play 和 App Store。

30 天的數字：
→ 862 個 Git commits
→ ~18,000 行 Dart + 1,745 行 Cloud Functions
→ 5 個 CI/CD workflows（iOS 全靠 GitHub Actions，我沒有 Mac）
→ 完整變現系統：IAP + AdMob + server-side 收據驗證

這個過程最大的啟發：AI 不是替代工程師，是補上了 PM 的執行缺口。

每一個技術決策 — 架構選型、安全策略、CI 設計 — 我都必須理解和負責。Claude Code 是 co-pilot，不是 autopilot。「做什麼」和「為什麼做」始終是人的工作，AI 補上的是「怎麼做」。

對有技術背景的 PM 來說，這可能是職涯裡最大的槓桿：不再需要等工程師才能驗證想法。

完整技術 Case Study 👉 [Blog 連結]

#ProductManagement #AI #Flutter #ClaudeCode #IndieHacker #BuildInPublic

---

## Facebook

30 天前我跟自己打了一個賭。

身為一個工程師轉 PM 的人，我一直有個心結：明明看得懂 code，也能跟工程師講一樣的語言，但自己一個人就是做不出東西。

然後我看到 Claude Code 出了 iOS App。

我想：如果我只用手機，利用通勤和帶小孩的碎片時間，能不能真的做出一個 App？

結果 30 天後，Magic Sticker 上架了。Google Play 和 App Store 都有。

862 個 commits。18,000 行程式碼。完整的 CI/CD pipeline。我甚至不需要一台 Mac — iOS 的 build 全部用 GitHub Actions 在雲端跑。

過程中被 Apple 退審（三個理由一次退回 🙃），踩了 LLM 會把所有情緒都生成「打招呼」的神奇 bug，在 Gradle 的 DSL 位置問題上浪費了不少時間。

但最後它活下來了，而且是一個真實的產品 — 有付費系統、有廣告變現、有安全架構，不是 demo。

如果你是 PM、設計師、或任何「懂一點技術但不是工程師」的人 — 現在真的是一個值得試試看的時代。

AI 不會替你做決定，但它會替你執行。而「做決定」本來就是你的本行。

👉 Magic Sticker: [Google Play](https://play.google.com/store/apps/details?id=com.magicsticker.magic_sticker) ｜ [App Store](https://apps.apple.com/app/id6761015408)
