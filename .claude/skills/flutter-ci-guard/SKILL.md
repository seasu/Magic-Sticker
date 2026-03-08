---
name: flutter-ci-guard
description: >
  Flutter 環境初始化與提交前品質把關 Skill。當環境中沒有 Flutter/Dart SDK、
  需要執行 dart analyze、修正第三方套件 API 錯誤、或設定 .gitignore 時觸發。
---

# Flutter CI Guard Skill

這個 Skill 記錄了在「無 Flutter SDK 的 Claude Code 環境」中開發 Flutter 專案的正確流程，
以及從實際踩坑中學到的教訓。

---

## 1. 環境初始化（每個 Session 開始前確認）

### 確認 Flutter SDK 是否存在

```bash
/opt/flutter/bin/flutter --version
```

### 若不存在，安裝 Flutter SDK

```bash
# 下載（約 730MB，需要等待）
wget -qO /tmp/flutter.tar.xz \
  https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.29.1-stable.tar.xz

# 解壓縮
tar -xf /tmp/flutter.tar.xz -C /opt/

# 修正 git 安全目錄警告
git config --global --add safe.directory /opt/flutter

# 確認安裝成功
/opt/flutter/bin/flutter --version
```

### 安裝後必做

```bash
# 在專案目錄執行，解析所有依賴
/opt/flutter/bin/flutter pub get
```

---

## 2. 提交前必跑 dart analyze

**每次修改程式碼後、git commit 前，必須執行：**

```bash
/opt/flutter/bin/dart analyze --fatal-infos
```

- `--fatal-infos`：連 info 等級（棄用警告等）都視為錯誤，與 GitHub Actions CI 行為一致
- 若有任何問題，先修正再 commit，避免讓使用者在手機上等 CI 回報

### Pre-commit Hook 設定

```bash
# .git/hooks/pre-commit
#!/bin/sh
DART=/opt/flutter/bin/dart
if ! command -v "$DART" > /dev/null 2>&1; then
  echo "⚠️  dart not found, skipping analyze"
  exit 0
fi
echo "▶ dart analyze --fatal-infos ..."
"$DART" analyze --fatal-infos
if [ $? -ne 0 ]; then
  echo "❌ dart analyze 發現問題，請修正後再 commit。"
  exit 1
fi
echo "✅ dart analyze 通過"
```

```bash
chmod +x .git/hooks/pre-commit
```

> **注意：** 不要用 `git commit --no-verify` 跳過 hook。

---

## 3. 修改第三方套件 API 前的正確流程

過去曾因為沒確認版本就直接查最新 API，導致來回修錯三次。正確流程：

### Step 1：先看 pubspec.yaml 的版本約束

```bash
grep <套件名> pubspec.yaml
# 例：gal: ^1.1.0 → 代表使用 1.x，不是最新的 2.x
```

### Step 2：查該版本的 API，而非最新版

- 去 pub.dev 查該版本的 changelog 或 API 文件
- 確認欄位名稱、型別（特別注意 nullable `?`）

### Step 3：修改前先理解型別

常見陷阱：
- 欄位是 `Object?` 而非 `PlatformException` → 需要 `as PlatformException?` 轉型
- 不同版本欄位名稱不同（例：gal 1.x 用 `error`，2.x 用 `platformException`）

---

## 4. 新專案必備的 .gitignore

`flutter pub get` 會產生大量暫存檔，新專案必須在第一次 commit 前建立 `.gitignore`：

```gitignore
# Flutter/Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
build/
*.g.dart
*.freezed.dart

# Android
android/local.properties
android/app/src/main/java/
android/.gradle/
android/key.properties
*.jks
*.keystore

# iOS
ios/.symlinks/
ios/Pods/
ios/Flutter/flutter_export_environment.sh

# IDE
.idea/
.vscode/
*.iml

# macOS
.DS_Store

# Secrets
.env
google-services.json
GoogleService-Info.plist
```

### pubspec.lock 要追蹤

- App 專案（非套件）應該 commit `pubspec.lock`，確保所有環境依賴版本一致
- 套件（publish to pub.dev）則不追蹤

---

## 5. 棄用 API 修正：withOpacity → withValues

Flutter 3.x 起 `withOpacity()` 已棄用，`--fatal-infos` 會報 error：

```dart
// 舊（棄用）
color.withOpacity(0.5)

// 新
color.withValues(alpha: 0.5)
```

批次修正：

```bash
# 找出所有使用位置
/opt/flutter/bin/dart analyze --fatal-infos 2>&1 | grep withOpacity
```

---

## 6. 本環境限制備忘

| 項目 | 狀態 |
|---|---|
| Docker daemon | ❌ 無法使用（socket 不存在） |
| apt 安裝 dart | ❌ 找不到套件 |
| 直接下載 Flutter SDK | ✅ 可行（安裝至 `/opt/flutter`） |
| 使用者操作介面 | 手機，無法在本機跑 CI |
| CI 工具 | GitHub Actions（已有 `dart analyze --fatal-infos`） |
