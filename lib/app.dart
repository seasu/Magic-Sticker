import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/dev_log/screens/log_viewer_screen.dart';
import 'features/editor/screens/editor_screen.dart';
import 'features/home/screens/home_screen.dart';

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
        final imagePath = state.extra as String;
        return EditorScreen(imagePath: imagePath);
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
