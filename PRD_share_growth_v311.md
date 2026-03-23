# 📝 PRD — 分享擴散與使用率提升（v3.11 規劃）

| 屬性 | 描述 |
|---|---|
| 專案名稱 | Magic Sticker（AI 一鍵產 LINE 貼圖） |
| 文件版本 | v3.11.0-draft7 |
| 文件日期 | 2026-03-22 |
| 目標平台 | Android（現行主力） |
| 主要目標 | 提升分享率、次日回訪（D1）、7 日留存（D7） |

---

## 1. 背景與目標

目前 App 已具備「儲存後進入原圖 vs 貼圖比對頁」與「分享比對圖」能力；本 PRD 目標是把既有分享能力轉成可量測、可回流、可擴散的成長迴圈。

### 1.1 成長目標（4 週）
- 分享按鈕點擊率（Share CTR）提升至 **≥ 35%**（有進入比對頁者）
- 分享成功率（Share Success Rate）提升至 **≥ 20%**（有點擊分享者）
- D1 留存提升 **+5%**
- D7 留存提升 **+2%**

### 1.2 北極星指標（North Star）
- `每 100 次 sticker_generated 產生的 share_success 次數`

---

## 2. 範圍（Scope）

### 2.1 In Scope（本次必做）
1. **分享漏斗事件埋點補齊**
2. **分享獎勵（每日首次分享 +1 點）**
3. **挑戰碼（Challenge Code）最小版本**
4. **一般使用者挑戰入口（由挑戰碼帶入預設）**
5. **一般使用者可建立挑戰（App 內自助）**
6. **分享當下自動產生 challenge code**
7. **Deep Link 一鍵導流到對應模板**
8. **成就系統（產圖成就 + 陪貓互動成就）**
9. **比對分享頁 CTA 文案優化與分享 fallback 提示**

### 2.2 Out of Scope（本次不做）
- 社群後台管理系統（Web Console）
- 複雜分潤結算
- 深度連結跨平台歸因（先以 code + 本機事件為主）

---

## 3. 目標使用情境（User Stories）

### US-01：一般使用者
- 作為使用者，我儲存貼圖後可一鍵分享比對圖；若分享成功可獲得 +1 點（每日一次），增加我再次使用動機。

### US-02：被邀請的朋友
- 作為收到分享的人，我輸入（或點擊）挑戰碼後，可直接套用同款風格/情緒模板並生成貼圖，降低跟做門檻。

### US-03：產品營運
- 作為營運，我可看到完整分享漏斗（曝光→點擊→成功→回流），判斷哪個版本最有效。

### US-04：挑戰發起者（一般使用者）
- 作為一般使用者，我可以在分享時決定是否發起挑戰，並在首頁進入「我的/已加入挑戰」查看清單與參與者資訊。

### US-05：探索型玩家
- 作為使用者，我希望在「生成貼圖」與「Loading 陪貓互動」中解鎖成就，拿到少量點數獎勵與勳章，增加回訪動機。

---

## 4. 功能需求（Functional Requirements）

## 4.1 分享事件漏斗（FR-Analytics）

### 需求
新增以下 Analytics 事件（最低欄位）：

1. `compare_screen_viewed`
   - params: `from`（editor/replay）, `shape`（circle/square）
2. `share_compare_tapped`
   - params: `from`, `shape`
3. `share_compare_success`
   - params: `from`, `shape`, `channel`（unknown / line / instagram / ...；若無法判斷則 unknown）
4. `share_compare_cancelled`
5. `share_reward_granted`
   - params: `credits=1`, `daily_count`
6. `share_reward_blocked`
   - params: `reason`（already_claimed_today / rate_limited / missing_signal）
7. `challenge_code_applied`
   - params: `code`, `source`（manual / deeplink）
8. `challenge_code_completed`
   - params: `code`, `generated_count`
9. `achievement_unlocked`
   - params: `achievement_id`, `source`（generation/cat_play）, `reward_credits`
10. `achievement_reward_granted`
   - params: `achievement_id`, `credits`, `daily_count`
11. `cat_play_milestone_reached`
   - params: `milestone_id`, `score_or_hits`

### 驗收
- 可在 DebugView 即時看到事件。
- 事件命名統一 snake_case。

---

## 4.2 分享獎勵（FR-Reward）

### 規則
- 每個帳號每天「首次分享成功」可領 **+1 點**。
- 當日再次分享不再發點，但允許正常分享。
- 獎勵入帳需走 Cloud Function（避免 client 端偽造）。

### 防濫用
- 需具備「分享成功訊號 + 近期 compare_screen_viewed 事件」雙條件才可觸發。
- 同一 uid 每日只可成功入帳 1 次（server 端冪等保護）。
- 異常高頻觸發寫入風控 log（不擋主流程，但不給點）。

### 驗收
- 首次成功分享：點數 +1 且寫入 creditHistory。
- 重複分享：不加點，回傳已領取狀態。

---

## 4.3 挑戰碼（FR-Challenge Code）

### 目標
提供「一般使用者邀請朋友接力」所需最小能力：朋友看到分享內容中的 code/連結後，可在 App 內快速套用同款模板。

### 資料模型（Firestore）
`challengeCodes/{code}`
- `code: string`（大寫，6–10 字元）
- `title: string`
- `presetStyleIndex: int?`
- `presetCategoryIds: string[]?`
- `customStyleDesc: string?`
- `customEmotionDesc: string?`
- `ownerUid: string`
- `isActive: bool`
- `templateType: "preset" | "pro_custom"`
- `requiresPro: bool`
- `createdAt, updatedAt: Timestamp`

`challengeRedemptions/{uid_code_yyyymmdd}`
- `uid`
- `code`
- `redeemedAt`

### UI/流程
1. Home 新增「輸入挑戰碼」入口（次要按鈕）
2. 驗證 code 成功後，顯示模板摘要（風格/情緒）
3. 使用者確認後直接帶入 style/emotion/editor 流程
4. 產生首張貼圖即記錄 `challenge_code_completed`

### 驗收
- 無效 code 顯示明確錯誤。
- 有效 code 可完整導流到生成流程。

---

## 4.4 一般使用者挑戰建立與首頁入口（FR-Challenge Authoring & Hub）

### 目標
不做 KOL 特權。任何使用者都可在分享時發起挑戰，並在首頁同一入口查看「我建立的挑戰」與「我加入的挑戰」。

### 建立流程（分享當下）
1. 使用者點「分享比對圖」
2. 顯示 toggle：`同時發起挑戰`（預設開啟，可手動關閉）
3. 開啟時，建立/重用 challenge code，並附在分享文案
4. 關閉時，僅分享圖片（不建立 challenge）

### 首頁入口（同一入口）
- Home 新增「挑戰」入口（單一入口）
- 進入後有兩個分頁：
  - `我建立的`
  - `我加入的`

### 清單與明細
- 清單項目：`title`, `code`, `createdAt`, `participantCount`, `lastActiveAt`
- 點進挑戰明細可查看參加者列表（僅顯示必要資訊）

### 參加者資料最小化
- 顯示：暱稱/匿名代號、加入時間、是否完成首張
- 不存：原始照片、完整貼圖二進位檔、完整編輯歷史

### 驗收
- 一般使用者可在 30 秒內完成「分享＋發起挑戰」。
- 首頁可進入同一入口查看「我建立/我加入」兩種清單。

---

## 4.5 挑戰碼與 Pro 付費能力授權規則（FR-Pro Entitlement）

> 重點：**挑戰碼可擴散內容，不可繞過付費授權**。

### 規則
1. 挑戰碼 metadata 新增：
   - `requiresPro: bool`
   - `templateType: preset | pro_custom`
2. 若 `templateType = preset`：任何使用者可直接套用。
3. 若 `templateType = pro_custom`：
   - **已解鎖 Pro**：可完整套用 `customStyleDesc` / `customEmotionDesc`。
   - **未解鎖 Pro**：可看到「同款預覽」，但按「開始生成」時必須先走 Pro 解鎖流程。
4. 未解鎖 Pro 的使用者不可透過 challenge code 直接拿到 `pro_custom` 的可生成權限。

### Server 端驗證（必要）
- 新增 Cloud Function：`resolveChallengeCode`（或整合既有 function）
  - 驗證 Auth + App Check
  - 讀取 code 後判斷呼叫者是否 `isProUnlocked`
  - 回傳「可用模板」：
    - Pro 用戶：回完整 payload
    - 非 Pro：回傳 `requiresPro=true` + 預覽資料（可不含完整 custom prompt）

### 客戶端 UX
- 非 Pro 套用 `pro_custom` code 時：
  - 顯示「此同款為 Pro 專屬模板」
  - 提供 CTA：`解鎖 Pro 後套用`
  - 可先生成非 Pro fallback（可選）：只帶預設 style/category，不帶 custom desc

### 驗收
- 非 Pro 使用者輸入 Pro 挑戰碼，不會直接取得 Pro 生成功能。
- Pro 使用者輸入同一碼，可完整套用且生成成功。
- 任意 client 偽造 `requiresPro=false` 請求，server 仍會擋下。

---

## 4.6 分享當下自動產生 Code（FR-Auto Challenge on Share）

### 目標
使用者在「分享比對圖」當下，系統自動產生（或重用）challenge code，降低擴散摩擦。

### 規則
1. 使用者點「分享比對圖」時，先呼叫 `ensureShareChallengeCode`。
2. 若使用者在最近 24h 內已有同模板 code，可直接重用；否則建立新 code。
3. 分享文案自動附上：
   - `challenge code`（可手動輸入）
   - `deep link`（可直接點擊導入 App）
4. 若 code 建立失敗：
   - 分享流程不可中斷（退回純圖片分享）
   - 事件記錄 `challenge_code_attach_failed`

### 驗收
- 多數分享（目標 ≥ 90%）都能帶 code 或 deep link。
- code 生成失敗時，分享按鈕仍可用，不阻塞主流程。

---

## 4.7 成就系統（FR-Achievement & Reward Loop）

### 目標
把既有「產圖」與「Loading 陪貓互動」轉為可發現、可收集、可回訪的遊戲化獎勵循環。

### 成就分類
1. **產圖成就（Generation Achievements）**
   - 例：首次生成、連續 3 天生成、單日生成 8 張、完成 1 次挑戰
2. **互動成就（Cat Play Achievements）**
   - 例：單次 loading 命中球 10 次、累積互動 50 次、首次觸發隱藏彩蛋

### 獎勵規則
- 成就解鎖可給點數（建議小額 1~2 點）或純徽章。
- 每日獎勵上限（建議 3 點）避免被刷。
- 同一成就僅可領取一次（或按賽季重置）。

### 與現有系統整合
- 點數入帳走 server function（與既有 creditHistory 一致）。
- 陪貓互動成就需附帶「本次確實在生成流程中」的 session 證明，避免離線刷分。

### 成就中心（可發現性）
- Home 加入「成就」入口（可與挑戰並列）
- 顯示：
  - 已解鎖勳章
  - 未解鎖成就（附 Hint）
  - 下一個可達成條件

### 驗收
- 使用者可看到成就清單 + Hint，且至少能在首日解鎖 1 個成就。
- 成就獎勵不影響既有點數經濟平衡（每日 cap 生效）。

---

## 4.8 比對頁 CTA/容錯優化（FR-Compare UX）

### 調整項
- 分享按鈕文案 A/B：
  - A: `分享比對圖`
  - B: `分享我的貼圖成果`
- 分享失敗或取消時顯示輕提示（不打斷流程）
- 分享成功後若當日已領獎，顯示「今日獎勵已領，可繼續分享」

### 驗收
- 無論分享成功/取消/失敗，頁面狀態可恢復可操作。
- `_isSharing` 卡住率為 0（離開頁面後也不殘留 loading）。

---

## 4.9 Deep Link 導流（FR-Deep Link Routing）

### 目標
讓朋友點擊分享內文連結後，可直接進入 App 對應模板（或落到輸入 code 頁）。

### Link 格式
- `https://magicsticker.app/c/{code}`（建議主格式）
- `magicsticker://challenge/{code}`（App scheme fallback）

### 行為規則
1. **已安裝 App**：直接開啟 App → 進入 challenge 預覽頁 → 一鍵套用。
2. **未安裝 App**：導向下載頁（Android Play），安裝後首次開啟帶入 pending code。
3. **無效/過期 code**：顯示錯誤並導回手動輸入頁。

### 技術建議
- Android 優先用 Firebase Dynamic Links（或 App Links + 自建 redirect）
- App 首次啟動保存 `pendingChallengeCode`，登入/初始化後再解析。

### 驗收
- 點擊 deep link 後 1 次跳轉內可到挑戰預覽頁。
- 首裝後回流可正確還原 pending code。

---

## 4.10 挑戰資料儲存策略與免費額度評估（FR-Storage & Cost Guardrail）

### 問題
挑戰功能若保存大量圖片/檔案會快速增加儲存與流量成本。

### 策略（建議採用）
1. **只存 metadata，不存大檔**
   - challenge / participant / status / counters / achievements
2. **不複製貼圖檔**
   - 挑戰系統只記錄「是否完成首張」與貼圖記錄 id（可選）
3. **保留期限（TTL）**
   - 挑戰資料預設保留 30 天（可配置），逾期自動封存或刪除
4. **排行榜/清單預聚合**
   - 以 counter 欄位顯示人數，避免每次掃全量 participants

### 建議資料模型（精簡）
- `challenges/{id}`：title/code/ownerUid/templateRef/participantCount/createdAt/expiresAt
- `challengeParticipants/{challengeId_uid}`：uid/joinedAt/completedFirstSticker(bool)
- `users/{uid}/joinedChallenges/{challengeId}`：只存索引
- `users/{uid}/achievements/{achievementId}`：unlockAt/rewardClaimed/source

### 免費用量評估方式（先用估算，不先擴容）
- 估算公式：
  - 每日寫入量 ≈ `new_challenges + joins + completions + counter_updates`
  - 儲存量 ≈ `avg_doc_size × doc_count`
- 先設定 3 檔警戒：
  - 50% 免費額度：觀察
  - 70% 免費額度：啟用更短 TTL
  - 90% 免費額度：暫停新挑戰建立（保留參加）

### 驗收
- 挑戰功能上線後 4 週內，儲存與讀寫均在免費額度警戒範圍內。
- 不因挑戰功能而新增圖片儲存成本。

---

## 5. 非功能需求（NFR）

1. **效能**：分享截圖耗時 P95 < 1.2s（中階 Android 裝置）。
2. **穩定性**：分享流程 crash-free > 99.9%。
3. **安全**：分享獎勵發放必須 server 端驗證 + 冪等。
4. **隱私**：分享內容僅含使用者主動產生與主動分享之圖片，不上傳額外個資。

---

## 6. 實作切分與排程（建議）

### Sprint 1（3–4 天）
- FR-Analytics
- FR-Compare UX（A/B 文案 + fallback 提示）

### Sprint 2（4–5 天）
- FR-Reward（Cloud Function + client call + creditHistory）

### Sprint 3（5–7 天）
- FR-Challenge Code（資料模型、輸入流程、導流）

---

## 7. 風險與對策

1. **無法精準判斷分享 channel**
   - 對策：先記錄 unknown；後續再做可選回填。
2. **獎勵被刷**
   - 對策：server daily idempotency + 行為門檻 + 風控記錄。
3. **挑戰資料量成長過快**
   - 對策：只存 metadata、啟用 TTL、超過警戒時限制新建挑戰。

---

## 8. 驗收清單（UAT）

- [ ] 儲存貼圖後可正常進入比對分享頁
- [ ] 分享成功可正確打點 `share_compare_success`
- [ ] 每日首次分享可 +1 點，重複分享不加點
- [ ] 輸入有效挑戰碼可成功套用模板並導流生成
- [ ] 無效碼顯示錯誤且不影響原流程
- [ ] 非 Pro 不可藉由 Pro 挑戰碼繞過付費授權
- [ ] 一般使用者可在分享時選擇是否發起挑戰，並在首頁查看我建立/我加入清單
- [ ] 分享時會自動帶入 code 或 deep link（失敗時不阻塞分享）
- [ ] deep link 可正確導到對應 challenge 預覽
- [ ] 成就中心可顯示已解鎖/未解鎖與 Hint
- [ ] 產圖成就與陪貓互動成就可解鎖且點數獎勵受每日上限保護
- [ ] Crashlytics 無新增高頻錯誤


---

## 9. 零廣告預算自然成長策略（Organic Discovery）

> 前提：不依賴買量，核心是讓「使用者產生內容 → 內容帶新用戶 → 新用戶再產生內容」。

### 9.1 主要流量來源（不花廣告費）
1. **分享比對圖自帶品牌曝光**
   - 既有 compare 分享圖保留品牌 footer 與清楚 CTA（搜尋 app 名稱）。
2. **LINE 群組自然擴散**
   - 分享素材以「原圖 vs 貼圖」強對比為主，降低理解成本。
3. **使用者挑戰碼接力**
   - 一般使用者發 code，朋友一鍵套用同款模板，形成接力挑戰。

### 9.2 可執行的低成本管道（不買廣告）
- **社群主題串合作**：找中小型創作者或社群活躍用戶（寵物、情侶、上班迷因）做「本週模板挑戰」。
- **社群貼文留言互動導流**：貼文只要放 1 張最強對比圖 + challenge code。
- **LINE 社群 / Discord 社群共創**：每週固定一個模板題目（如「週一崩潰」）。

### 9.3 產品內必備配套（讓自然流量真的留住）
1. 首次安裝 60 秒內完成第一張（降低流失）
2. 分享成功後即時回饋（徽章 / +1 點）
3. 進來的 challenge code 流量能快速落地（少一步表單、少一步選擇）
4. 成就 Hint 驅動探索（讓使用者自發挖彩蛋、提高回訪）

### 9.4 「奇怪管道」原則（可以做，但要可持續）
- 不建議短期灰色手法（洗群、機器留言、灌榜）。
- 可做的「非典型但健康」管道：
  - 小型垂直社群版主合作（交換模板、非付費）
  - 校園社團 / 寵物社群活動（貼圖主題週）
  - Discord 伺服器「每週模板」共創

### 9.5 Organic 成效 KPI（4 週）
- `organic_new_users / total_new_users` ≥ 70%
- `share_compare_success / sticker_generated` ≥ 0.20
- `challenge_code_applied -> challenge_code_completed` 轉換率 ≥ 25%
- K-factor（每位分享用戶帶來的新用戶）≥ 0.25
- `achievement_unlocked_users / DAU` ≥ 20%

### 9.6 驗收
- [ ] 不投放廣告下，連續 2 週仍有正成長新用戶
- [ ] 主要新用戶來源可追蹤到「分享」或「challenge code」
- [ ] 自然流量用戶 D7 留存不低於整體 D7 的 90%
