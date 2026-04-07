import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/models/sticker_shape.dart';
import 'core/theme/app_theme.dart';
import 'features/billing/screens/credit_history_screen.dart';
import 'features/challenge/screens/challenge_preview_screen.dart';
import 'features/dev_log/screens/log_viewer_screen.dart';
import 'features/editor/screens/editor_screen.dart';
import 'features/editor/screens/emotion_selection_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/home/screens/style_selection_screen.dart';
import 'features/editor/models/sticker_compare_args.dart';
import 'features/editor/screens/sticker_compare_screen.dart';
import 'features/sticker_history/models/sticker_record.dart';
import 'features/billing/providers/credit_provider.dart';
import 'features/sticker_history/screens/sticker_history_screen.dart';
import 'features/sticker_history/screens/sticker_replay_screen.dart';

// SharedPreferences key：存放從 deep link / Install Referrer 帶入的待處理挑戰碼
const kPendingChallengeCodeKey = 'pending_challenge_code';

/// 跳轉至 /style-select 時攜帶的參數（步驟 2：選擇風格）
class StyleSelectArgs {
  final String imagePath;

  const StyleSelectArgs({required this.imagePath});
}

/// 跳轉至 /emotion-select 時攜帶的參數（步驟 3：選擇情緒）
class EmotionSelectArgs {
  final String imagePath;
  final int styleIndex;
  final StickerShape stickerShape;
  final String? customStyleDesc; // Pro 自訂風格描述（≤15字）

  const EmotionSelectArgs({
    required this.imagePath,
    required this.styleIndex,
    this.stickerShape = StickerShape.circle,
    this.customStyleDesc,
  });
}

/// 跳轉至 /editor 時攜帶的參數
class EditorArgs {
  final String imagePath;
  final int styleIndex;
  final StickerShape stickerShape;
  final List<String>? categoryIds;       // 由 EmotionSelectionScreen 傳入
  final String? customStyleDesc;         // Pro 自訂風格描述（≤15字）
  final String? customEmotionDesc;       // Pro 自訂情緒描述（≤15字）
  final bool enhancePersonFeatures;      // Pro 人物特徵強化

  const EditorArgs({
    required this.imagePath,
    required this.styleIndex,
    this.stickerShape = StickerShape.circle,
    this.categoryIds,
    this.customStyleDesc,
    this.customEmotionDesc,
    this.enhancePersonFeatures = false,
  });
}


final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/style-select',
      builder: (_, state) {
        final args = state.extra as StyleSelectArgs;
        return StyleSelectionScreen(imagePath: args.imagePath);
      },
    ),
    GoRoute(
      path: '/emotion-select',
      builder: (_, state) {
        final args = state.extra as EmotionSelectArgs;
        return EmotionSelectionScreen(
          imagePath: args.imagePath,
          styleIndex: args.styleIndex,
          stickerShape: args.stickerShape,
          customStyleDesc: args.customStyleDesc,
        );
      },
    ),
    GoRoute(
      path: '/editor',
      builder: (_, state) {
        final args = state.extra as EditorArgs;
        return EditorScreen(
          imagePath: args.imagePath,
          styleIndex: args.styleIndex,
          stickerShape: args.stickerShape,
          categoryIds: args.categoryIds,
          customStyleDesc: args.customStyleDesc,
          customEmotionDesc: args.customEmotionDesc,
          enhancePersonFeatures: args.enhancePersonFeatures,
        );
      },
    ),
    GoRoute(
      path: '/credit-history',
      builder: (_, __) => const CreditHistoryScreen(),
    ),
    GoRoute(
      path: '/sticker-history',
      builder: (_, __) => const StickerHistoryScreen(),
    ),
    GoRoute(
      path: '/sticker-replay',
      builder: (_, state) {
        final record = state.extra as StickerRecord;
        return StickerReplayScreen(record: record);
      },
    ),
    GoRoute(
      path: '/dev-log',
      builder: (_, __) => const LogViewerScreen(),
    ),
    GoRoute(
      path: '/sticker-compare',
      builder: (_, state) {
        final args = state.extra as StickerCompareArgs;
        return StickerCompareScreen(
          originalImagePath: args.originalImagePath,
          stickerBytes: args.stickerBytes,
          stickerShape: args.stickerShape,
          from: args.from,
          styleIndex: args.styleIndex,
          categoryIds: args.categoryIds,
          customStyleDesc: args.customStyleDesc,
          customEmotionDesc: args.customEmotionDesc,
        );
      },
    ),
    // ── Viral Share Link：朋友點擊 deep link 後進入的挑戰預覽頁 ──────────────
    GoRoute(
      path: '/challenge/:code',
      builder: (_, state) {
        final code = state.pathParameters['code']!;
        return ChallengePreviewScreen(code: code);
      },
    ),
  ],
);

class MagicStickerApp extends ConsumerStatefulWidget {
  const MagicStickerApp({super.key});

  @override
  ConsumerState<MagicStickerApp> createState() => _MagicStickerAppState();
}

class _MagicStickerAppState extends ConsumerState<MagicStickerApp>
    with WidgetsBindingObserver {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  // App 從背景喚醒時，重新拉取 Firestore 點數，確保多設備共用同一帳號時數值同步
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(creditProvider.notifier).reload();
    }
  }

  Future<void> _initDeepLinks() async {
    // ── Cold start：App 從連結啟動（已安裝，直接開啟）──────────────────────
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleDeepLink(initialUri);
    } catch (_) {}

    // ── Hot link：App 已在前景，收到連結 ──────────────────────────────────
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (_) {},
    );
  }

  void _handleDeepLink(Uri uri) {
    // 支援格式：
    //   https://magic-sticker-8eaf4.web.app/c/{CODE}
    //   magicsticker://challenge/{CODE}
    String? code;

    final segments = uri.pathSegments;
    if (uri.scheme == 'https' &&
        segments.length == 2 &&
        segments[0] == 'c') {
      code = segments[1];
    } else if (uri.scheme == 'magicsticker' &&
        uri.host == 'challenge' &&
        segments.isNotEmpty) {
      code = segments[0];
    }

    if (code == null || code.isEmpty) return;

    // 若尚未登入，先存入 SharedPreferences，登入後由 HomeScreen 讀取並導航
    _navigateToChallengeOrStore(code);
  }

  void _navigateToChallengeOrStore(String code) {
    // 嘗試直接導航；若使用者未登入，ChallengePreviewScreen 會顯示提示
    // SharedPreferences 暫存由 HomeScreen 的 initState 讀取（登入後回流）
    _savePendingCode(code);
    router.push('/challenge/$code');
  }

  Future<void> _savePendingCode(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPendingChallengeCodeKey, code);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Magic Sticker',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
