import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import 'log_service.dart';

class FirebaseService {
  static FirebaseCrashlytics get crashlytics => FirebaseCrashlytics.instance;

  static void log(String message) {
    crashlytics.log(message);
    LogService.instance.info(message, tag: 'Crashlytics');
  }

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    await crashlytics.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
    final msg = reason != null ? '$reason — $error' : '$error';
    if (fatal) {
      LogService.instance.error('[FATAL] $msg', tag: 'Crashlytics');
    } else {
      LogService.instance.warning(msg, tag: 'Crashlytics');
    }
  }
}
