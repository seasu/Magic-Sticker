import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/firebase_service.dart';
import '../widgets/pick_image_button.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _pickImage(BuildContext context, ImageSource source) async {
    FirebaseService.log('HomeScreen._pickImage: source=${source.name}');
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 95);
    if (picked == null || !context.mounted) return;
    context.push('/editor', extra: picked.path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              _Header(),
              const Spacer(),
              _PreviewPlaceholder(),
              const Spacer(),
              PickImageButton(
                icon: Icons.photo_library_outlined,
                label: '從相簿選取',
                onTap: () => _pickImage(context, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
              PickImageButton(
                icon: Icons.camera_alt_outlined,
                label: '立即拍照',
                onTap: () => _pickImage(context, ImageSource.camera),
                outlined: true,
              ),
              const SizedBox(height: 32),
              // ── 僅 debug 模式顯示 Crashlytics 測試按鈕 ──────────────────
              if (kDebugMode) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => FirebaseCrashlytics.instance.crash(),
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('[DEBUG] 測試 Crashlytics 強制崩潰'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          '☀️ MagicMorning',
          style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '選一張照片，一鍵生成早安貼圖',
          style: textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          Icons.image_outlined,
          size: 80,
          color: colorScheme.onSurfaceVariant.withOpacity(0.4),
        ),
      ),
    );
  }
}
