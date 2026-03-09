import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/sticker_shape.dart';
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

  /// 每次重新生成遞增，用來取消舊的背景任務
  int _generationId = 0;

  @override
  EditorState build(String arg) => EditorState(originalImagePath: arg);

  /// 初始化：兩步流程
  ///
  /// [defaultStyleIndex] 對應 [StickerStyle.values]，預設 0（Q版卡通）
  /// [stickerShape] 貼圖形狀，預設圓形
  Future<void> initialize({
    int defaultStyleIndex = 0,
    StickerShape stickerShape = StickerShape.circle,
  }) async {
    state = state.copyWith(
      status: EditorStatus.generatingTexts,
      styleIndices: List.filled(8, defaultStyleIndex),
      stickerShape: stickerShape,
    );

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
    final genId = ++_generationId;
    unawaited(_generateImagesInBackground(resized, _specs!, genId));
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
      final genId = ++_generationId;
      unawaited(_generateImagesInBackground(resized, _specs!, genId));
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_regen_failed');
      state = state.copyWith(status: EditorStatus.ready);
    }
  }

  /// 使用者手動修改第 [index] 張貼圖的文字
  void updateStickerText(int index, String text) {
    final updated = List<String>.from(state.stickerTexts);
    updated[index] = text;
    state = state.copyWith(stickerTexts: updated);
  }

  /// 使用者在編輯 popup 選擇不同配色
  void updateColorSchemeIndex(int stickerIdx, int schemeIdx) {
    final updated = List<int>.from(state.colorSchemeIndices);
    updated[stickerIdx] = schemeIdx;
    state = state.copyWith(colorSchemeIndices: updated);
  }

  /// 使用者在編輯 popup 選擇字型
  void updateFontIndex(int stickerIdx, int fontIdx) {
    final updated = List<int>.from(state.fontIndices);
    updated[stickerIdx] = fontIdx;
    state = state.copyWith(fontIndices: updated);
  }

  /// 使用者在編輯 popup 選擇產圖風格
  ///
  /// 風格直接影響 Gemini prompt，選完後立即重新生成該張圖片。
  Future<void> updateStyleIndex(int stickerIdx, int styleIdx) async {
    final updated = List<int>.from(state.styleIndices);
    updated[stickerIdx] = styleIdx;
    state = state.copyWith(styleIndices: updated);
    await retryImageGeneration(stickerIdx);
  }

  /// 使用者調整字體大小倍率
  void updateFontSizeScale(int stickerIdx, double scale) {
    final updated = List<double>.from(state.fontSizeScales);
    updated[stickerIdx] = scale;
    state = state.copyWith(fontSizeScales: updated);
  }

  /// 使用者透過手勢（拖拉/捏合/旋轉）調整文字的位置、大小、角度
  void updateTextTransform(
    int stickerIdx, {
    double? xAlign,
    double? yAlign,
    double? angle,
    double? sizeScale,
  }) {
    final xs = xAlign != null
        ? (List<double>.from(state.textXAligns)..[stickerIdx] = xAlign)
        : null;
    final ys = yAlign != null
        ? (List<double>.from(state.textYAligns)..[stickerIdx] = yAlign)
        : null;
    final as_ = angle != null
        ? (List<double>.from(state.textAngles)..[stickerIdx] = angle)
        : null;
    final ss = sizeScale != null
        ? (List<double>.from(state.fontSizeScales)..[stickerIdx] = sizeScale)
        : null;
    state = state.copyWith(
      textXAligns: xs,
      textYAligns: ys,
      textAngles: as_,
      fontSizeScales: ss,
    );
  }

  /// 使用者在編輯 popup 縮放 / 位移 / 旋轉圖片
  void updateImageTransform(
      int stickerIdx, double scale, Offset offset, double angle) {
    final scales = List<double>.from(state.imageScales);
    final offsets = List<Offset>.from(state.imageOffsets);
    final angles = List<double>.from(state.imageAngles);
    scales[stickerIdx] = scale;
    offsets[stickerIdx] = offset;
    angles[stickerIdx] = angle;
    state = state.copyWith(
        imageScales: scales, imageOffsets: offsets, imageAngles: angles);
  }

  /// 重新生成指定索引的 AI 貼圖（單張重試）
  Future<void> retryImageGeneration(int index) async {
    if (_specs == null || index >= _specs!.length) return;

    final reset = List<Uint8List?>.from(state.generatedImages);
    reset[index] = null;
    final clearErrors = List<String?>.from(state.imageErrors);
    clearErrors[index] = null;
    state = state.copyWith(generatedImages: reset, imageErrors: clearErrors);

    final styleIdx = state.styleIndices[index];

    try {
      final resized = await ImageProcessor.resizeForNative(
          File(state.originalImagePath));

      final bytes = await StickerGenerationService().generateSingle(
        resized,
        _specs![index],
        index: index,
        styleIndex: styleIdx,
        shape: state.stickerShape,
      );
      final updated = List<Uint8List?>.from(state.generatedImages);
      final errors = List<String?>.from(state.imageErrors);
      updated[index] = bytes ?? Uint8List(0);
      if (bytes == null) errors[index] = 'API 未回傳圖片';
      state = state.copyWith(generatedImages: updated, imageErrors: errors);
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack,
          reason: 'retry_image_generation_failed');
      final failed = List<Uint8List?>.from(state.generatedImages);
      failed[index] = Uint8List(0);
      final errors = List<String?>.from(state.imageErrors);
      errors[index] = _classifyError(e);
      state = state.copyWith(generatedImages: failed, imageErrors: errors);
    }
  }

  // ─── private ────────────────────────────────────────────

  /// 逐張生成 8 張貼圖，每完成一張立即更新 state（用戶可即時看到）
  ///
  /// sentinel 規則（Uint8List?）：
  ///   null          → 生成中（loading）
  ///   Uint8List(0)  → 失敗（imageErrors[i] 有原因）
  ///   Uint8List(>0) → 成功
  Future<void> _generateImagesInBackground(
      Uint8List photoBytes, List<StickerSpec> specs, int genId) async {
    final service = StickerGenerationService();
    for (int i = 0; i < specs.length; i++) {
      // 若已有新一輪重新生成，停止舊任務
      if (genId != _generationId) return;

      final styleIdx = state.styleIndices[i];

      try {
        final bytes = await service.generateSingle(
          photoBytes,
          specs[i],
          index: i,
          styleIndex: styleIdx,
          shape: state.stickerShape,
        );
        if (genId != _generationId) return;
        final updated = List<Uint8List?>.from(state.generatedImages);
        final errors = List<String?>.from(state.imageErrors);
        updated[i] = bytes ?? Uint8List(0);
        if (bytes == null) errors[i] = 'API 未回傳圖片';
        state = state.copyWith(generatedImages: updated, imageErrors: errors);
      } catch (e, stack) {
        if (genId != _generationId) return;
        await FirebaseService.recordError(e, stack,
            reason: 'background_image_gen_failed_index$i');
        final failed = List<Uint8List?>.from(state.generatedImages);
        failed[i] = Uint8List(0);
        final errors = List<String?>.from(state.imageErrors);
        errors[i] = kDebugMode ? e.toString() : _classifyError(e);
        state = state.copyWith(generatedImages: failed, imageErrors: errors);
      }
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
