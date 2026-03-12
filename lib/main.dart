import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/ads_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Android: google-services.json 已在 native 層自動初始化 Firebase，
    // 不帶 options 呼叫以取得既有 instance，避免 placeholder firebase_options 衝突。
    await Firebase.initializeApp();
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      // 已初始化（正常情況），直接繼續
    } else {
      LogService.instance.warning('Firebase initializeApp failed: $e', tag: 'Firebase');
    }
  } catch (e) {
    LogService.instance.warning('Firebase initializeApp failed: $e', tag: 'Firebase');
  }

  // 全域錯誤攔截（放在 try 外面確保一定執行）
  try {
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      LogService.instance.error(
        details.exceptionAsString(),
        tag: 'FlutterError',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      LogService.instance.error('$error', tag: 'PlatformDispatcher');
      return true;
    };
  } catch (_) {
    // Crashlytics 未設定時安全跳過
  }

  // AdMob 初始化（含預載 Rewarded Ad）
  await AdsService.instance.initialize();

  // 匿名登入（訪客模式）：確保每個用戶都有 Firebase UID
  // iOS：Keychain 保存，重裝後 UID 不變 ✅
  // Android：重裝後 UID 重置，訪客僅給 1 點（降低誘因）✅
  await AuthService.signInAnonymouslyIfNeeded();

  runApp(const ProviderScope(child: MagicStickerApp()));
}
