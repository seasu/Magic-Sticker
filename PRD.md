📝 產品需求文件 (PRD) - MagicMorning App
| 屬性 | 描述 |
|---|---|
| 專案名稱 | MagicMorning (自動去背早安貼圖產生器) |
| 版本號規範 | SemVer (Major.Minor.Patch+Build) |
| 開發平台 | Flutter (Android & iOS) |
| 監控系統 | Firebase Crashlytics & Analytics |
| 核心技術 | ML Kit (Android) / Vision Framework (iOS) |
1. 產品願景
讓使用者只需「選取照片」，即可透過 AI 自動提取主體、移除背景，並智慧生成應景的早安文字與排版，一鍵分享正能量。
2. 核心功能模組 (Feature Matrix)
2.1 影像處理 (去背核心)
 * Android (Phase 1): * 整合 com.google.mlkit:subject-segmentation。
   * 支援人像、寵物、物件的多主體偵測。
 * iOS (Phase 2): * 整合 Apple Vision Framework 中的 VNGenerateForegroundInstanceMaskRequest (iOS 17+ 推薦)。
   * 利用 Apple 晶片的神經網路引擎 (Neural Engine) 進行毫米級邊緣處理。
 * 共通規範: * 原生端處理完畢後，需回傳 Uint8List (PNG 格式) 給 Flutter 層。
   * 傳入原生層前，Flutter 需先進行 Image Resize (建議寬高不超過 1080px) 以防止記憶體溢出 (OOM)。
2.2 AI 文案與編輯器
 * 情境分析: 串接 google_generative_ai (Gemini API)，傳入原圖 Base64，獲取 10-20 字的早安短文。
 * 畫布合成: * 使用 Stack 疊加：背景層 -> 主體層 -> 文字層。
   * 支援 Google Fonts 字體動態載入。
 * 匯出: 透過 RepaintBoundary 將 Widget 轉換為 Image Byte，儲存至相簿。
3. 開發規範 (Strict Engineering Standards)
3.1 嚴格版本號管理 (Versioning)
 * 規則: 每次修改代碼（不論大小），必須更新 pubspec.yaml 的版本。
 * CI 檢查: GitHub Action 會比對 pubspec.yaml 版本與 Git Tag，若版本未增加則拒絕 Build。
 * Commit 範例: [fix] v1.0.5+6: 修正 iOS 17 下去背邊緣鋸齒問題。
3.2 錯誤回報 (Firebase Crashlytics)
 * 全域攔截: 必須實作 FlutterError.onError 與 PlatformDispatcher.instance.onError。
 * 原生追蹤: * Android 使用 FirebaseCrashlytics.getInstance().recordException()。
   * iOS 使用 Crashlytics.crashlytics().record(error:)。
 * 日誌埋點: 在 MethodChannel 呼叫開始與結束時，手動調用 Crashlytics.log() 記錄執行參數。
4. GitHub Actions 自動化 Build 規範
專案必須包含 .github/workflows/main_build.yml，定義以下流程：
 * Android Build: * 環境: ubuntu-latest。
   * 產物: app-release.apk, app-release.aab。
   * 混淆: 自動上傳 mapping.txt 至 Firebase 以還原當機堆疊。
 * iOS Build: * 環境: macos-latest。
   * 產物: .ipa (需配置 GitHub Secrets 中的 P12 證書與 Provisioning Profile)。
   * 符號: 自動上傳 dSYMs 至 Firebase。
5. 專案目錄結構建議
lib/
├── core/
│   ├── services/
│   │   ├── firebase_service.dart   # Crashlytics 初始化
│   │   └── gemini_service.dart     # AI 文案生成
│   └── utils/
│       └── image_processor.dart    # 圖片 Resize 邏輯
├── native/
│   └── method_channel.dart         # 定義 removeBackground 介面
├── ui/
│   ├── home/                       # 照片選取介面
│   └── editor/                     # 合成與文字編輯
android/                            # Kotlin ML Kit 實作
ios/                                # Swift Vision Framework 實作

6. 驗收標準 (Acceptance Criteria)
 * 效能: 去背處理時間在 Android/iOS 高階手機應小於 2 秒。
 * 穩定性: Firebase Crashlytics 的 Crash-free users 需高於 99%。
 * 相容性: Android 8.0+ / iOS 15.0+ (iOS 17+ 享用進階去背)。
