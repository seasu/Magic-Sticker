import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/ads_service.dart';
import 'core/services/log_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // 全域 Flutter 錯誤攔截 → Crashlytics + LogService
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      LogService.instance.error(
        details.exceptionAsString(),
        tag: 'FlutterError',
      );
    };

    // 非同步/平台錯誤攔截 → Crashlytics + LogService
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      LogService.instance.error('$error', tag: 'PlatformDispatcher');
      return true;
    };
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') {
      // Firebase 尚未設定（佔位憑證）—— app 仍正常啟動，僅略過崩潰監控
      LogService.instance.warning('Firebase initializeApp failed: $e', tag: 'Firebase');
    }
  } catch (e) {
    LogService.instance.warning('Firebase initializeApp failed: $e', tag: 'Firebase');
  }

  // AdMob 初始化（含預載 Rewarded Ad）
  await AdsService.instance.initialize();

  runApp(const ProviderScope(child: MagicMorningApp()));
}
