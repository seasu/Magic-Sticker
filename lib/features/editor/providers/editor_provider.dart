import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/sticker_spec.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/sticker_generation_service.dart';
import '../../../core/utils/image_processor.dart';
import '../models/editor_state.dart';

/// 以 imagePath 為 key 的 provider
final editorStateProvider =
    NotifierProvider.autoDispose.family<_EditorFamilyNotifier, EditorState, String>(
  _EditorFamilyNotifier.new,
);

class _EditorFamilyNotifier
    extends AutoDisposeFamilyNotifier<EditorState, String> {
  /// AI 自由規格暫存（不放進 state 以免觸發多餘 rebuild）
  List<StickerSpec>? _specs;

  @override
  EditorState build(String arg) => EditorState(originalImagePath: arg);

  /// 初始化：兩步流程
  Future<void> initialize() async {
    state = state.copyWith(status: EditorStatus.generatingTexts);

    Uint8List resized;
    try {
      final imageFile = File(state.originalImagePath);
      resized = await ImageProcessor.resizeForNative(imageFile);
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_resize_failed',
      );
      state = state.copyWith(
        status: EditorStatus.idle,
        errorMessage: '圖片處理失敗，請重試',
      );
      return;
    }

    _specs = await GeminiService().generateStickerSpecs(resized);
    final texts = _specs!.map((s) => s.text).toList();
    state = state.copyWith(stickerTexts: texts, status: EditorStatus.ready);
    unawaited(_generateImagesInBackground(resized, _specs!));
  }

  /// 重新讓 AI 自由發揮，生成全新 8 組規格 + 圖片
  Future<void> regenerateTexts() async {
    state = state.copyWith(
      status: EditorStatus.generatingTexts,
      generatedImages: List.filled(8, null),
      imageErrors: List.filled(8, null),
    );
    try {
      final resized = await ImageProcessor.resizeForNative(
        File(state.originalImagePath),
      );
      _specs = await GeminiService().generateStickerSpecs(resized);
      final texts = _specs!.map((s) => s.text).toList();
      state = state.copyWith(stickerTexts: texts, status: EditorStatus.ready);
      unawaited(_generateImagesInBackground(resized, _specs!));
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_regen_failed');
      state = state.copyWith(status: EditorStatus.ready);
    }
  }

  /// 使用者手動修改第 [index] 張貼圖的文字（fallback 模式用）
  void updateStickerText(int index, String text) {
    final updated = List<String>.from(state.stickerTexts);
    updated[index] = text;
    state = state.copyWith(stickerTexts: updated);
  }

  /// 重新生成指定索引的 AI 貼圖（單張重試）
  Future<void> retryImageGeneration(int index) async {
    if (_specs == null || index >= _specs!.length) return;

    // 重設為 null + 清除錯誤（loading 狀態）
    final reset = List<Uint8List?>.from(state.generatedImages);
    reset[index] = null;
    final clearErrors = List<String?>.from(state.imageErrors);
    clearErrors[index] = null;
    state = state.copyWith(generatedImages: reset, imageErrors: clearErrors);

    try {
      final resized = await ImageProcessor.resizeForNative(File(state.originalImagePath));
      final img = await StickerGenerationService().generateOne(resized, _specs![index], index);
      final updated = List<Uint8List?>.from(state.generatedImages);
      updated[index] = img ?? Uint8List(0);
      final updatedErrors = List<String?>.from(state.imageErrors);
      if (img == null) updatedErrors[index] = 'API 未回傳圖片';
      state = state.copyWith(generatedImages: updated, imageErrors: updatedErrors);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'retry_image_generation_failed');
      final failed = List<Uint8List?>.from(state.generatedImages);
      failed[index] = Uint8List(0);
      final errors = List<String?>.from(state.imageErrors);
      errors[index] = _classifyError(e);
      state = state.copyWith(generatedImages: failed, imageErrors: errors);
    }
  }

  // ─── private ────────────────────────────────────────────

  /// 後台並行生成 8 張 AI 圓形貼圖；每張完成後即時更新對應卡片（非阻塞）
  ///
  /// sentinel 規則（Uint8List?）：
  ///   null          → 生成中
  ///   Uint8List(0)  → 失敗（imageErrors[i] 有原因）
  ///   Uint8List(>0) → 成功
  ///
  /// 每批最多 3 張並發，完成後再送下一批，避免打爆 rate limit。
  Future<void> _generateImagesInBackground(
      Uint8List photoBytes, List<StickerSpec> specs) async {
    const batchSize = 3;
    for (int start = 0; start < specs.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, specs.length);
      final batch = List.generate(end - start, (i) => start + i);

      await Future.wait(batch.map((index) async {
        try {
          final img = await StickerGenerationService()
              .generateOne(photoBytes, specs[index], index);
          final updated = List<Uint8List?>.from(state.generatedImages);
          updated[index] = img ?? Uint8List(0);
          final errors = List<String?>.from(state.imageErrors);
          if (img == null) errors[index] = 'API 未回傳圖片';
          state = state.copyWith(generatedImages: updated, imageErrors: errors);
        } catch (e, stack) {
          try {
            await FirebaseService.recordError(
                e, stack, reason: 'background_image_gen_failed');
            final failed = List<Uint8List?>.from(state.generatedImages);
            failed[index] = Uint8List(0);
            final errors = List<String?>.from(state.imageErrors);
            errors[index] = _classifyError(e);
            state = state.copyWith(generatedImages: failed, imageErrors: errors);
          } catch (_) {}
        }
      }));
    }
  }

  /// 將例外轉換為使用者看得懂的中文訊息
  /// Crashlytics 另外記錄完整 stack trace，此處只給 UI 用
  static String _classifyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (e is SocketException || msg.contains('network') || msg.contains('socket')) {
      return '網路連線失敗';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return '請求逾時';
    }
    if (msg.contains('quota') || msg.contains('rate') || msg.contains('429')) {
      return 'API 配額已用盡';
    }
    if (msg.contains('401') || msg.contains('403') || msg.contains('unauthorized')) {
      return 'API 金鑰無效';
    }
    if (msg.contains('500') || msg.contains('503') || msg.contains('server')) {
      return 'Gemini 服務異常';
    }
    return '生成失敗';
  }
}
