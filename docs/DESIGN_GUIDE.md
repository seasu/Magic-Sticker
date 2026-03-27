# Magic Sticker Design Guide

> 本文件為整個專案（Flutter App + Firebase Hosting 靜態頁面）的設計規範唯一來源。
> 所有新頁面、新元件在實作前請先對照此規範。

---

## 1. 品牌色彩 (Brand Colors)

### 主色盤

| Token | Hex | CSS var（Web） | Flutter |
|---|---|---|---|
| Brand Start | `#FD297B` | `var(--brand-start)` | `Color(0xFFFD297B)` |
| Brand Mid | `#FF5864` | `var(--brand-mid)` | `Color(0xFFFF5864)` |
| Brand End | `#FF655B` | `var(--brand-end)` | `Color(0xFFFF655B)` |
| Text Primary | `#21262E` | — | `AppColors.textPrimary` |
| Text Secondary | `#71768A` | — | `AppColors.textSecondary` |
| Background | `#FFFFFF` | — | `AppColors.background` |
| Surface | `#F2F2F7` | — | `const Color(0xFFF2F2F7)` |
| Divider | `#E8E8E8` | — | `AppColors.divider` |

### 語義色

| Token | Hex | 用途 | Flutter |
|---|---|---|---|
| Like (Green) | `#4CD964` | 正向操作、獲得點數 | `AppColors.like` |
| Nope (Red) | `#FF3B30` | 負向操作、消耗點數 | `AppColors.nope` |
| Warning (Orange) | `#FF9500` | 退款、警告 | `Color(0xFFFF9500)` |

### Pro 香檳金色系

| Token | Hex | 用途 |
|---|---|---|
| Pro Body | `#B8860D` | 金色貓咪主色、Pro 標題 |
| Pro Light | `#DEBC70` | 香檳亮部 |
| Pro Accent | `#FD297B` | 鼻子點睛、Pro 球色 |
| Pro Card BG | `#C9A84C` + 20% alpha | 描述卡背景 |
| Pro Subtitle | `#A07828` | Pro Loading 副標 |

---

## 2. 漸層規格 (Gradient)

### 品牌主漸層（所有 CTA、Hero 背景統一使用）

```css
/* Web */
background: linear-gradient(135deg, #FD297B 0%, #FF655B 100%);
/* CSS var */
background: var(--brand-gradient);
```

```dart
// Flutter
AppColors.gradient
// 定義：LinearGradient(colors: [Color(0xFFFD297B), Color(0xFFFF5864), Color(0xFFFF655B)],
//                      begin: Alignment.topLeft, end: Alignment.bottomRight)
```

### Pro Loading 漸層（香檳金，僅 Loading 畫面使用）

```dart
LinearGradient(
  colors: [Color(0xFFFAFAF5), Color(0xFFF5EDD8)],
  begin: Alignment.topCenter,
  end:   Alignment.bottomCenter,
)
```

---

## 3. 字型 (Typography)

### 字型家族

| 端 | 字型 |
|---|---|
| **Flutter** | `OpenHuninn`（全域 ThemeData 已設定，不需個別指定） |
| **Web** | `-apple-system, BlinkMacSystemFont, 'Segoe UI', 'Noto Sans TC', 'PingFang TC', 'Microsoft JhengHei', sans-serif` |

### 文字層級（Flutter）

| 層級 | fontSize | fontWeight | 用途 |
|---|---|---|---|
| Hero Title | 38px | w900 | 首頁大標 |
| Page Title (AppBar) | 18px | w800 | 所有頁面 AppBar 標題 |
| Section Title | 22px | w800 | 區塊主標題 |
| Card Title | 14–16px | w700 | 卡片標題、清單項目 |
| Body | 13–14px | w600 | 正文 |
| Caption / Hint | 11–12px | w500–w600 | 次要說明、提示 |

### 文字層級（Web）

| 層級 | font-size | font-weight | 用途 |
|---|---|---|---|
| Hero h1 | 24px | 800 | 全頁漸層卡片主標 |
| Section h2 | 1.1rem | 700 | 隱私政策各節標題 |
| Body p | 0.95rem | 400 | 一般正文 |
| Caption | 0.82–0.88rem | 400 | 表格、頁尾 |

---

## 4. 間距與圓角 (Spacing & Radius)

### 圓角

| 元件 | Web | Flutter |
|---|---|---|
| 主卡片 | `16px`（CSS var `--radius-card`）| `BorderRadius.circular(16)` |
| 全頁 Glass 卡片 | `24px`（CSS var `--radius-glass`）| `BorderRadius.circular(24)` |
| 按鈕 | `14px`（CSS var `--radius-btn`）| `BorderRadius.circular(14)` |
| Pill Badge | `99px`（CSS var `--radius-pill`）| `BorderRadius.circular(99)` |
| Input Field | `12px` | `BorderRadius.circular(12)` |
| 小標籤 Tag | `99px` | — |

### 陰影（Flutter Card 標準）

```dart
BoxShadow(
  color: Colors.black.withValues(alpha: 0.06),
  blurRadius: 8,
  offset: Offset(0, 2),
)
```

### 間距慣例

| 場景 | 值 |
|---|---|
| 頁面水平 padding | `16px` |
| 卡片間距 | `8–12px` |
| 卡片內 padding | `14–16px` |
| 元件內部小間距 | `4–8px` |

---

## 5. 元件規範 (Components)

### 主要按鈕 (Primary Button)

**Flutter**
```dart
// 品牌漸層按鈕（CTA 用）
ShaderMask(
  shaderCallback: (bounds) => AppColors.gradient.createShader(bounds),
  child: ElevatedButton(...),
)
// 或直接用 BoxDecoration gradient 包 InkWell
```

**Web**
```css
.btn {
  background: #fff;
  color: var(--brand-start);
  border-radius: var(--radius-btn);
  padding: 16px;
  font-size: 16px;
  font-weight: 700;
}
```

### 次要按鈕 (Secondary Button)

**Web（在深色漸層背景上）**
```css
.btn-secondary {
  background: transparent;
  color: #fff;
  border: 2px solid rgba(255,255,255,0.6);
}
```

### 卡片 (Card)

**Flutter（列表頁，如點數紀錄、生成紀錄）**
```dart
DecoratedBox(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8, offset: Offset(0, 2))],
  ),
)
```

**Web（隱私政策文件頁）**
```css
.card {
  background: #fff;
  border-radius: var(--radius-card);
  padding: 32px;
  box-shadow: 0 2px 12px rgba(0,0,0,.06);
}
```

### Pill Badge

**Flutter**
```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(20),
  ),
  child: Text(..., style: TextStyle(color: color, fontWeight: FontWeight.w900)),
)
```

**Web（.tag 標籤）**
```css
.tag {
  background: rgba(253,41,123,0.10);
  color: #C4005A;
  border-radius: 99px;
  padding: 2px 10px;
  font-size: 0.78rem;
  font-weight: 600;
}
```

### Highlight / 提示框

**Web**
```css
.highlight {
  background: rgba(253,41,123,0.07);
  border-left: 4px solid var(--brand-start);
  padding: 14px 18px;
  border-radius: 0 8px 8px 0;
  color: #7B1237;
}
```

---

## 6. 頁面版型 (Page Layouts)

### 全頁漸層版型（Web：`/download`、`/c/{code}`）

- `body`：`background: var(--brand-gradient)`, flex center
- `.card`：Glassmorphism，`background: rgba(255,255,255,0.15)`, `backdrop-filter: blur(16px)`
- 主按鈕：白底 + 品牌粉字
- 次要按鈕：透明 + 白框白字
- 來源：`/public/css/brand.css`

### 文件版型（Web：`/privacy`）

- `body`：白色 `#f8f9fa` 背景
- `header`：品牌漸層橫幅
- `main`：max-width 760px，白卡 + 陰影分節
- 色彩：全部使用 CSS var，來源同 `brand.css`

### 卡片列表版型（Flutter）

- 背景：`Color(0xFFF2F2F7)`（iOS 系統淺灰）
- AppBar：同背景色，`scrolledUnderElevation: 0`
- 列表：`ListView` + 白卡（radius 14 + shadow）
- 代表頁面：生成紀錄、點數紀錄

### Loading 版型（Flutter）

- 標準：`CatColorScheme.pink`，`ColoredBox(color: pink.bg)`
- Pro：`CatColorScheme.proChampagne`，香檳金漸層背景
- 共用元件：`CatLoadingWidget`（透過參數切換配色）

---

## 7. Do / Don't

| ✅ Do | ❌ Don't |
|---|---|
| 所有 CTA 按鈕使用品牌漸層或白底品牌粉字 | 用紫色（`#6c63ff`）或橘色（`#FF9F43`）當主色 |
| 新 Web 頁面引入 `/css/brand.css` | 在 HTML 中重複撰寫與 brand.css 相同的 CSS |
| Flutter 使用 `AppColors` 常數 | 在 widget 中硬寫 hex 色碼 |
| 卡片圓角 ≥ 14px | 使用 0 圓角或純直角 |
| AppBar 標題 18px / w800 | AppBar 標題使用其他 size 或 weight |
| 背景頁面色用 `#F2F2F7`（列表頁） | 列表頁使用純白背景（缺乏層次感） |
| Pro 功能使用香檳金配色 | Pro 功能沿用粉紅配色（混淆免費/付費層級） |
