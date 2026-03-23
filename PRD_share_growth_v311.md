# 📝 PRD — 分享擴散與使用率提升（v3.11 精簡版）

| 屬性 | 描述 |
|---|---|
| 專案名稱 | Magic Sticker（AI 一鍵產 LINE 貼圖） |
| 文件版本 | v3.11.0 |
| 文件日期 | 2026-03-23 |
| 目標平台 | Android（現行主力） |
| 主要目標 | **最小必要病毒成長迴圈**：讓使用者分享的每一張圖帶動新用戶下載試用 |

---

## 1. 背景與目標

### 1.1 核心問題

App 已具備「儲存後進入原圖 vs 貼圖比對頁」與「分享比對圖」能力，但：
1. 分享的圖片沒有品牌標識 → 朋友看到不知道哪個 App 做的
2. 朋友即使想試，找到 App 再進入同款模板摩擦過高
3. 無法量測從「朋友看到」到「朋友試用」的轉換路徑

### 1.2 病毒成長迴圈（目標狀態）

```
使用者生成貼圖
  → 分享帶品牌浮水印的比對圖（+ 內嵌連結）
    → 朋友看到 → 點連結 → App 打開，同款模板預選
      → 60 秒出第一張貼圖 → 再次分享
```

### 1.3 成長目標（4 週）

| 指標 | 目標 |
|---|---|
| 北極星：share_compare_tapped / sticker_generated | ≥ 20% |
| challenge_link_opened → 生成完成 轉換率 | ≥ 30% |
| K-factor（每位分享用戶帶來的新 link 開啟次數） | ≥ 0.3 |

---

## 2. 範圍（Scope）

### 2.1 本次 In Scope（v3.11，2 個 Sprint）

| # | 功能 | 病毒成長貢獻 |
|---|---|---|
| A | **比對頁品牌化 + CTA 優化** | 每次分享 = 有品牌廣告 |
| B | **Viral Share Link（自動生成 deep link + 手動 code）** | 朋友點連結即零摩擦進入同款模板 |
| C | **分享獎勵（點擊觸發，每日 1 點）** | 增加首次分享動機 |
| D | **最小漏斗埋點（5 個關鍵事件）** | 量測病毒迴圈是否在運作 |

### 2.2 明確移至 v3.12（本次不做）

| 功能 | 移除理由 |
|---|---|
| Challenge Hub（我建立的/我加入的清單） | 留存工具，非獲客工具；增加開發複雜度 |
| Pro Entitlement for Challenges | 非核心用戶路徑，edge case |
| 成就系統（Achievement System） | 純留存工具，與病毒獲客無關 |
| 每日 4 點跨路徑 cap 機制 | 成就系統移走後，分享只有 1 條獎勵路徑，不需要複雜 cap |
| Storage & Cost Guardrail（獨立章節）| TTL `expiresAt` 已內嵌資料模型；定期清理 CF 為 v3.12 運維任務 |
| 社群後台管理、複雜分潤結算 | Out of scope |

---

## 3. 使用情境（User Stories）

**US-01：分享者**
作為使用者，我儲存貼圖後分享比對圖，朋友看到帶品牌的圖和連結，下載試用同款。我首次分享可獲得 +1 點。

**US-02：被分享者**
作為收到分享連結的人，點連結後 App 直接開啟對應模板（或導向 Play Store 安裝後自動還原），無需手動找模板。

**US-03：營運**
作為營運，我可看到從「比對頁曝光」到「分享」到「link 被點擊」到「新用戶生成」的完整漏斗，判斷哪個環節要優化。

---

## 4. 功能需求

### 4.A 比對頁品牌化（FR-Compare UX）

#### 目標
讓每一張分享出去的比對圖本身成為品牌廣告，參考 Retrica / FaceApp 的被動浮水印策略。

#### 調整項

**1. 分享圖品牌 Footer**
- 比對圖底部加上品牌 footer 區塊（高度約 48dp）
- 內容：Magic Sticker Logo + App 名稱 + 下載提示文字（「試試同款 ↓」）
- 顏色：品牌主色背景，白色文字，不遮蓋主圖

**2. 分享文案預填**
- 預填文案（可修改）：`我用 Magic Sticker 做了這個！試試同款 👇\n{deep_link}`
- 若 deep link 生成失敗，僅保留圖片 + 純文字（不含連結）

**3. 分享按鈕文案 A/B**
- A（control）：`分享比對圖`
- B（test）：`分享我的貼圖成果`
- 以 `compare_screen_ab_variant`（值：A/B）參數記錄，在 `share_compare_tapped` 事件帶出

**4. 分享狀態容錯**
- 分享取消或失敗：顯示 Snackbar 輕提示，不打斷流程
- 修復 `_isSharing` 離開頁面後殘留 loading 狀態的問題
- 分享成功後若當日已領獎：顯示「今日獎勵已領，可繼續分享」

#### 驗收
- 分享出去的圖片底部有品牌 footer，含 Logo + 文字。
- 無論分享成功/取消/失敗，比對頁狀態可恢復可操作。
- A/B variant 可在 DebugView 確認被正確記錄。

---

### 4.B Viral Share Link（FR-Viral Share Link）

> 整合原 4.3 挑戰碼、4.6 自動生成、4.9 Deep Link 為單一最小實作。

#### 目標
使用者分享時自動附上可點擊的深層連結，朋友點擊後直接進入 App 的同款模板預覽頁，零額外步驟。

#### 4.B.1 分享時自動生成連結

**規則**
1. 使用者點「分享比對圖」時，先呼叫 Cloud Function `ensureShareCode`。
2. 若同一 ownerUid + templateType 在最近 24 小時內已有有效 code，直接重用（不重複建立）。
3. 分享文案自動附上：
   - `deep link`：`https://magicsticker.app/c/{CODE}`
   - `code`（供手動輸入）：同一組 CODE
4. 若 code 建立失敗：靜默降級為純圖片分享，主流程不中斷，記錄 `share_link_attach_failed` 事件。

**Code 格式**
- 大寫英數字，6 碼
- 排除混淆字元：`0, O, I, L, 1`（字元集：`A-Z` 去除 O/I/L + `2-9`）
- 例：`M7BX4R`

#### 4.B.2 資料模型（Firestore）

**`challenges/{code}`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `code` | string | 同 document ID |
| `ownerUid` | string | 建立者 UID |
| `templateType` | `"preset"` \| `"pro_custom"` | 模板類型 |
| `presetStyleIndex` | int? | preset 模板索引 |
| `presetCategoryIds` | string[]? | preset 情緒類別 |
| `createdAt` | Timestamp | 建立時間 |
| `expiresAt` | Timestamp | 建立時間 + 30 天（TTL） |
| `isActive` | bool | 預設 true，過期或手動停用後為 false |

**`challengeParticipants/{code_uid}`**

| 欄位 | 型別 | 說明 |
|---|---|---|
| `uid` | string | 參與者 UID |
| `code` | string | 挑戰碼 |
| `joinedAt` | Timestamp | 點連結時間 |
| `completedFirstSticker` | bool | 是否完成首張生成 |

> **不存**：原始照片、自訂 prompt 完整內容、編輯歷史。

#### 4.B.3 Deep Link 路由

**Link 格式**
- 主格式：`https://magicsticker.app/c/{CODE}`
- 技術實作：**Android App Links**（`/.well-known/assetlinks.json` 部署於 Firebase Hosting）
- ~~Firebase Dynamic Links~~：已於 2025/08 終止，不使用。

**已安裝 App 行為**
1. OS 直接開啟 App
2. 進入「挑戰預覽頁」：顯示模板摘要（風格/情緒）
3. 使用者點「用這款生成」→ 帶入 editor 流程

**未安裝 App 行為**
1. Firebase Hosting landing page（`magicsticker.app/c/{CODE}`）
2. 偵測 User-Agent → Android 導向 Play Store（帶 `utm_source=challenge&referrer={CODE}`）
3. 安裝後首次開啟 → Play Install Referrer API 解析 CODE → 還原「挑戰預覽頁」

**Pending Code 暫存**
- 安裝後首次啟動尚未登入時，CODE 暫存 `SharedPreferences`
- 登入/初始化完成後讀取並解析

**無效/過期 code**
- 顯示明確錯誤訊息，提示「連結已過期」，導回 Home

#### 4.B.4 Cloud Function：`ensureShareCode`

| 項目 | 規格 |
|---|---|
| Trigger | HTTPS Callable |
| Auth | 必須登入（`context.auth` 驗證） |
| Input | `{ templateType, presetStyleIndex?, presetCategoryIds? }` |
| Output | `{ code, deepLink, reused: bool }` |
| 冪等性 | 同 ownerUid + templateType 在 24h 內重用現有 code |
| 失敗行為 | 回傳 HTTP 5xx，client 靜默降級 |
| Timeout | 10 秒 |
| Memory | 256 MB |

#### 驗收
- 分享文案含有效 deep link，可點擊開啟 App（或 Play Store）。
- 已安裝：點 link → 1 次跳轉內到挑戰預覽頁。
- 未安裝：安裝後首次開啟 → 自動還原挑戰預覽頁。
- code 生成失敗 → 分享按鈕仍可用，僅缺少 link。
- 6 碼 code 不含混淆字元，可手動輸入。

---

### 4.C 分享獎勵（FR-Reward）

#### 規則
- 每個帳號每天首次點擊分享按鈕（且同 session 內曾看過比對頁）可領 **+1 點**。
- 當日再次分享不再發點，但允許正常分享。
- 獎勵入帳必須走 Cloud Function（避免 client 端偽造）。

> **為什麼改為「點擊觸發」而非「成功觸發」：**
> Android OS 的 Intent Chooser 不回傳分享結果，`share_plus` 的回傳值只代表「呼叫了 share sheet」，無法可靠判斷「真的發出去了」。iOS 可精確判斷但不一致性太高。降級為點擊觸發 + session 內有 compare_screen_viewed 作為雙條件防濫用，是最務實策略。

#### 防濫用
- 雙條件觸發：`share_compare_tapped` + 同 session 內有 `compare_screen_viewed`
- 同一 uid 每日只可成功入帳 1 次（server 端冪等，`users/{uid}/dailyRewardSummary/{yyyymmdd}`）
- 異常高頻：寫風控 log，不給點，不擋主流程

#### Cloud Function：`shareRewardGrant`

| 項目 | 規格 |
|---|---|
| Trigger | HTTPS Callable |
| Auth | 必須登入 |
| Input | `{ sessionHadCompareView: bool }` |
| Output | `{ granted: bool, reason: string, newBalance: int }` |
| 冪等性 | `users/{uid}/dailyRewardSummary/{yyyymmdd}.shareGranted: bool` |
| Timeout | 10 秒 |
| Memory | 256 MB |

#### 驗收
- 首次點擊分享（且 session 有 compare_screen_viewed）：creditHistory 新增 +1 筆。
- 同日第二次：不加點，回傳 `granted: false, reason: already_claimed_today`。
- client 可顯示「+1 點」或「今日已領」對應提示。

---

### 4.D 最小漏斗埋點（FR-Analytics）

#### 5 個關鍵事件

| 事件名稱 | 關鍵 params | 用途 |
|---|---|---|
| `compare_screen_viewed` | `from`（editor/replay）, `shape`, `ab_variant`（A/B） | 漏斗頂端曝光 |
| `share_compare_tapped` | `from`, `shape`, `ab_variant`, `has_link`（bool） | 點擊率計算 |
| `share_compare_dismissed` | `reason`（cancelled/failed） | 流失追蹤 |
| `share_reward_granted` | `credits=1` | 獎勵是否在工作 |
| `challenge_link_opened` | `code`, `installed`（bool）, `resolved`（bool） | 回流漏斗量測 |

> 所有事件命名統一 snake_case，可在 Firebase DebugView 即時確認。

#### 明確移除的事件（v3.12）
- `achievement_unlocked`, `achievement_reward_granted`, `cat_play_milestone_reached`（隨成就系統一起）
- `challenge_code_created`（Hub 功能移走後暫不需要）

---

## 5. Firestore Security Rules（新增）

> 上線前必須補齊，否則為安全漏洞。

```
// challenges（挑戰碼）
match /challenges/{code} {
  // 任何已登入用戶可讀（用於驗證 code）
  allow read: if request.auth != null;
  // 只有 Cloud Function（Admin SDK）可寫入
  allow write: if false;
}

// challengeParticipants
match /challengeParticipants/{docId} {
  // 本人可讀自己的參與記錄
  allow read: if request.auth != null
    && resource.data.uid == request.auth.uid;
  // 只有 Cloud Function 可寫入
  allow write: if false;
}
```

---

## 6. Sprint 規劃

### Sprint 1（3–4 天）
**目標：讓分享的圖有品牌識別 + 開始量測**

| 任務 | 負責 |
|---|---|
| 比對頁底部品牌 footer（Flutter UI） | Flutter |
| 分享文案預填（含 placeholder for link） | Flutter |
| 分享按鈕文案 A/B（`ab_variant` 參數） | Flutter |
| `_isSharing` 狀態容錯修復 | Flutter |
| 5 個關鍵漏斗事件埋點 | Flutter |
| Firestore Security Rules 補齊 | Firebase |

### Sprint 2（5–6 天）
**目標：Viral Share Link 端到端可用**

| 任務 | 負責 |
|---|---|
| Cloud Function `ensureShareCode`（建立/重用 code，Firestore 寫入） | Functions |
| Cloud Function `shareRewardGrant`（冪等 +1 點） | Functions |
| Firebase Hosting landing page（`/c/{code}`，UA 偵測 → Play Store） | Hosting |
| `/.well-known/assetlinks.json` 部署（Android App Links） | Hosting |
| App 端 App Links intent-filter 設定（AndroidManifest.xml） | Android |
| 挑戰預覽頁（Flutter UI：顯示模板摘要 + 一鍵生成 CTA） | Flutter |
| Pending code SharedPreferences 暫存與登入後解析 | Flutter |
| Play Install Referrer API 首裝後 code 還原 | Android/Flutter |

---

## 7. 關鍵技術風險與對策

| 風險 | 對策 |
|---|---|
| Firebase Dynamic Links 已停服 | 改用 Android App Links + Firebase Hosting redirect（已在規格中） |
| Android share signal 不可靠 | 降級為「點擊觸發」+ session 雙條件（已在 4.C 中說明） |
| Pending code 安裝後丟失 | Play Install Referrer API（Android）+ SharedPreferences 暫存 |
| Code 碰撞（6 碼 32 字元）| 生成池 ≈ 32^6 ≈ 10 億，實際並發量極低，碰撞可安全忽略；如需擴展改 8 碼 |
