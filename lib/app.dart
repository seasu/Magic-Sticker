import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/models/sticker_shape.dart';
import 'core/theme/app_theme.dart';
import 'features/dev_log/screens/log_viewer_screen.dart';
import 'features/editor/screens/editor_screen.dart';
import 'features/home/screens/home_screen.dart';

/// 跳轉至 /editor 時攜帶的參數
class EditorArgs {
  final String imagePath;
  final int styleIndex;
  final StickerShape stickerShape;

  const EditorArgs({
    required this.imagePath,
    required this.styleIndex,
    this.stickerShape = StickerShape.circle,
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
      path: '/editor',
      builder: (_, state) {
        final args = state.extra as EditorArgs;
        return EditorScreen(
          imagePath: args.imagePath,
          styleIndex: args.styleIndex,
          stickerShape: args.stickerShape,
        );
      },
    ),
    GoRoute(
      path: '/dev-log',
      builder: (_, __) => const LogViewerScreen(),
    ),
  ],
);

class MagicMorningApp extends StatelessWidget {
  const MagicMorningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MagicMorning',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
