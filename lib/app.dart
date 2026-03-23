import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/models/sticker_shape.dart';
import 'core/theme/app_theme.dart';
import 'features/billing/screens/credit_history_screen.dart';
import 'features/dev_log/screens/log_viewer_screen.dart';
import 'features/editor/screens/editor_screen.dart';
import 'features/editor/screens/emotion_selection_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/home/screens/style_selection_screen.dart';
import 'features/editor/models/sticker_compare_args.dart';
import 'features/editor/screens/sticker_compare_screen.dart';
import 'features/sticker_history/models/sticker_record.dart';
import 'features/sticker_history/screens/sticker_history_screen.dart';
import 'features/sticker_history/screens/sticker_replay_screen.dart';

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
  final List<String>? categoryIds;    // 由 EmotionSelectionScreen 傳入
  final String? customStyleDesc;      // Pro 自訂風格描述（≤15字）
  final String? customEmotionDesc;    // Pro 自訂情緒描述（≤15字）

  const EditorArgs({
    required this.imagePath,
    required this.styleIndex,
    this.stickerShape = StickerShape.circle,
    this.categoryIds,
    this.customStyleDesc,
    this.customEmotionDesc,
  });
}

final _router = GoRouter(
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
        );
      },
    ),
  ],
);

class MagicStickerApp extends StatelessWidget {
  const MagicStickerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Magic Sticker',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
