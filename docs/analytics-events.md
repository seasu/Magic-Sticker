# Firebase Analytics 事件清單

> 更新時間：2026-04-02
> 所有事件命名遵循 Firebase snake_case 規範，參數值使用 `int` (0/1) 表示 bool，避免型別歧義。

---

## 一、點數漏斗（Credit Funnel）

| 事件名 | 觸發時機 | 參數 | 程式位置 |
|---|---|---|---|
| `paywall_shown` | 點數不足 → Paywall 對話框開啟 | `is_guest` (0/1) | `credit_paywall_dialog.dart` `initState` |
| `ad_watch_started` | 用戶點「看廣告」按鈕（ATT 正常、廣告流程啟動） | — | `credit_paywall_dialog.dart` `_watchAd()` |
| `ad_watch_completed` | 廣告完整看完，CF 入帳成功 | `credits_after` (int) | `credit_paywall_dialog.dart` `_watchAd()` CF 回傳後 |
| `credit_spent` | CF 扣點成功（生成一張貼圖） | `credits_before` (int) | `editor_provider.dart` `generateSingleImage()` |
| `credit_insufficient` | CF 回傳點數不足（server-side 驗證失敗） | — | `editor_provider.dart` `generateSingleImage()` catch |

### 漏斗分析建議

```
paywall_shown
  └─► ad_watch_started      → 轉換率 = 點擊看廣告的比例
        └─► ad_watch_completed → 廣告完播率（完播 / 開始）
              └─► credit_spent → 獲得點數後是否立即生成
credit_insufficient          → 理論上應 ≈ 0（client 側已先檢查），若偏高表示 client cache 不同步
```

---

## 二、病毒成長漏斗（Viral Growth Funnel）

| 事件名 | 觸發時機 | 參數 | 程式位置 |
|---|---|---|---|
| `compare_screen_viewed` | 進入「前後對比」頁面 | `from`, `shape`, `ab_variant` | `analytics_service.dart` |
| `share_compare_tapped` | 點擊「分享」按鈕 | `from`, `shape`, `ab_variant`, `has_link` (0/1) | `analytics_service.dart` |
| `share_compare_dismissed` | 取消或分享失敗 | `reason` ('cancelled'/'failed') | `analytics_service.dart` |
| `share_reward_granted` | 分享獎勵點數入帳 | `credits` (int) | `analytics_service.dart` |
| `challenge_link_opened` | 朋友點擊 deep link 開啟 App | `code`, `installed` (0/1), `resolved` (0/1) | `analytics_service.dart` |

---

## 三、AI 生成品質

| 事件名 | 觸發時機 | 參數 | 程式位置 |
|---|---|---|---|
| `ai_specs_generated` | Gemini 成功生成 Spec | — | `gemini_service.dart` |
| `ai_specs_fallback` | Gemini 失敗，使用 fallback spec | — | `gemini_service.dart` |
| `sticker_image_generated` | 單張貼圖圖片生成完成 | — | `sticker_generation_service.dart` |
| `sticker_generated` | 整組貼圖完成（Editor 確認） | — | `editor_screen.dart` |

---

## 四、IAP（自動追蹤）

Firebase Analytics 會自動記錄 `in_app_purchase` 事件（Google Play / App Store），**不需手動埋點**。
可在 Firebase Console → Events → `in_app_purchase` 查看購買金額、商品 ID 等。

---

## 五、DebugView 測試指令

```bash
# Android（adb 連接裝置後執行）
adb shell setprop debug.firebase.analytics.app com.magicsticker.magic_sticker

# iOS（Xcode Simulator 或 adb 替代工具）
# 在 Xcode Scheme 加入 launch argument：-FIRAnalyticsDebugEnabled
```

Firebase Console → Analytics → DebugView 即可看到實時事件流。
