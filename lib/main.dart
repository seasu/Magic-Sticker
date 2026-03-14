import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/ads_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/log_service.dart';
import 'features/billing/services/iap_service.dart';

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

  // Firebase App Check（防止非官方 App 呼叫 Cloud Functions）
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
    );
  } catch (e) {
    LogService.instance.warning('App Check activate failed: $e', tag: 'AppCheck');
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

  // IAP 初始化（監聽購買流 + 載入商品）
  await IAPService.instance.initialize();

  // 匿名登入（訪客模式）：確保每個用戶都有 Firebase UID
  await AuthService.signInAnonymouslyIfNeeded();

  // 強制刷新 ID token — Auth session 可能從上次 app launch 持久化，
  // 但 ID token 1 小時過期。不刷新的話第一次 Cloud Function 呼叫就會 UNAUTHENTICATED。
  await AuthService.ensureValidToken();

  runApp(const ProviderScope(child: MagicStickerApp()));
}
