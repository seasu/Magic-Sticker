import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/firebase_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/utils/image_processor.dart';
import '../../../native/method_channel.dart';
import '../models/editor_state.dart';

/// 以 imagePath 為 key 的 provider
final editorStateProvider =
    NotifierProvider.autoDispose.family<_EditorFamilyNotifier, EditorState, String>(
  _EditorFamilyNotifier.new,
);

class _EditorFamilyNotifier
    extends AutoDisposeFamilyNotifier<EditorState, String> {
  @override
  EditorState build(String arg) => EditorState(originalImagePath: arg);

  /// Step 1 去背 → Step 2 Gemini 生成 3 組短文字
  Future<void> initialize() async {
    state = state.copyWith(status: EditorStatus.removingBackground);

    Uint8List? resized;
    try {
      final imageFile = File(state.originalImagePath);
      resized = await ImageProcessor.resizeForNative(imageFile);
      final subjectBytes =
          await BackgroundRemovalChannel.removeBackground(resized);
      state = state.copyWith(
        subjectBytes: subjectBytes,
        status: EditorStatus.generatingTexts,
      );
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_remove_bg_failed',
      );
      state = state.copyWith(
        status: EditorStatus.idle,
        errorMessage: '去背失敗，請重試',
      );
      return;
    }

    await _fetchTexts(resized!);
  }

  /// 重新呼叫 Gemini 取得新的 3 組短文字
  Future<void> regenerateTexts() async {
    state = state.copyWith(status: EditorStatus.generatingTexts);
    try {
      final resized = await ImageProcessor.resizeForNative(
        File(state.originalImagePath),
      );
      await _fetchTexts(resized);
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_regen_texts_failed',
      );
      state = state.copyWith(status: EditorStatus.ready);
    }
  }

  /// 使用者手動修改第 [index] 張貼圖的文字
  void updateStickerText(int index, String text) {
    final updated = List<String>.from(state.stickerTexts);
    updated[index] = text;
    state = state.copyWith(stickerTexts: updated);
  }

  // ─── private ────────────────────────────────────────────
  Future<void> _fetchTexts(Uint8List imageBytes) async {
    // generateStickerTexts 內部已處理所有例外並回傳 Fallback，不會 throw
    final texts = await GeminiService().generateStickerTexts(imageBytes);
    state = state.copyWith(stickerTexts: texts, status: EditorStatus.ready);
  }
}
