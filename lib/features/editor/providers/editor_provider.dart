import 'dart:io';
import 'dart:ui' show Offset;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/sticker_shape.dart';
import '../../../core/models/sticker_spec.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/sticker_generation_service.dart';
import '../../../core/utils/image_processor.dart';
import '../../billing/providers/credit_provider.dart';
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

  /// 縮圖快取（避免每次生成都重新 resize）
  Uint8List? _cachedResized;

  @override
  EditorState build(String arg) => EditorState(originalImagePath: arg);

  /// 初始化：取得 Spec（免費，不扣點）
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

    try {
      final imageFile = File(state.originalImagePath);
      _cachedResized = await ImageProcessor.resizeForNative(imageFile);
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

    final specs = await GeminiService().generateStickerSpecs(
      _cachedResized!,
      categoryIds: state.selectedCategoryIds,
    );
    _specs = specs;
    final count = specs.length;
    final texts = specs.map((s) => s.text).toList();
    state = state.copyWith(
      stickerTexts: texts,
      categoryIds: specs.map((s) => s.categoryId).toList(),
      generatedImages: List.filled(count, _kNotGeneratedSentinel),
      imageErrors: List.filled(count, null),
      colorSchemeIndices: List.generate(count, (i) => i % 8),
      imageScales: List.filled(count, 1.0),
      imageOffsets: List.filled(count, Offset.zero),
      fontIndices: List.filled(count, 0),
      styleIndices: List.filled(count, state.styleIndices.isNotEmpty ? state.styleIndices[0] : 0),
      fontSizeScales: List.filled(count, 1.0),
      textXAligns: List.filled(count, 0.0),
      textYAligns: List.filled(count, 0.85),
      textAngles: List.filled(count, 0.0),
      imageAngles: List.filled(count, 0.0),
      status: EditorStatus.ready,
    );
  }

  /// 重新讓 AI 依目前選中的情感類別生成全新規格（免費，不扣點）
  Future<void> regenerateTexts() async {
    final count = state.selectedCategoryIds.length;
    state = state.copyWith(
      status: EditorStatus.generatingTexts,
      generatedImages: List.filled(count, _kNotGeneratedSentinel),
      imageErrors: List.filled(count, null),
    );
    try {
      final resized = _cachedResized ??
          await ImageProcessor.resizeForNative(File(state.originalImagePath));
      _cachedResized = resized;
      final specs = await GeminiService().generateStickerSpecs(
        resized,
        categoryIds: state.selectedCategoryIds,
      );
      _specs = specs;
      final newCount = specs.length;
      final texts = specs.map((s) => s.text).toList();
      state = state.copyWith(
        stickerTexts: texts,
        categoryIds: specs.map((s) => s.categoryId).toList(),
        generatedImages: List.filled(newCount, _kNotGeneratedSentinel),
        imageErrors: List.filled(newCount, null),
        colorSchemeIndices: List.generate(newCount, (i) => i % 8),
        imageScales: List.filled(newCount, 1.0),
        imageOffsets: List.filled(newCount, Offset.zero),
        fontIndices: List.filled(newCount, 0),
        styleIndices: List.filled(newCount, state.styleIndices.isNotEmpty ? state.styleIndices[0] : 0),
        fontSizeScales: List.filled(newCount, 1.0),
        textXAligns: List.filled(newCount, 0.0),
        textYAligns: List.filled(newCount, 0.85),
        textAngles: List.filled(newCount, 0.0),
        imageAngles: List.filled(newCount, 0.0),
        status: EditorStatus.ready,
      );
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_regen_failed');
      state = state.copyWith(status: EditorStatus.ready);
    }
  }

  /// 使用者選擇新的情感類別組合，重新生成規格（免費，不扣點）
  Future<void> updateSelectedCategories(List<String> ids) async {
    if (ids.length < 4 || ids.length > 12) return;
    final count = ids.length;
    state = state.copyWith(
      selectedCategoryIds: ids,
      status: EditorStatus.generatingTexts,
      stickerTexts: List.filled(count, ''),
      categoryIds: List.filled(count, ''),
      generatedImages: List.filled(count, _kNotGeneratedSentinel),
      imageErrors: List.filled(count, null),
      colorSchemeIndices: List.generate(count, (i) => i % 8),
      imageScales: List.filled(count, 1.0),
      imageOffsets: List.filled(count, Offset.zero),
      fontIndices: List.filled(count, 0),
      styleIndices: List.filled(count, state.styleIndices.isNotEmpty ? state.styleIndices[0] : 0),
      fontSizeScales: List.filled(count, 1.0),
      textXAligns: List.filled(count, 0.0),
      textYAligns: List.filled(count, 0.85),
      textAngles: List.filled(count, 0.0),
      imageAngles: List.filled(count, 0.0),
    );
    try {
      final resized = _cachedResized ??
          await ImageProcessor.resizeForNative(File(state.originalImagePath));
      _cachedResized = resized;
      final specs = await GeminiService().generateStickerSpecs(resized, categoryIds: ids);
      _specs = specs;
      final newCount = specs.length;
      final texts = specs.map((s) => s.text).toList();
      state = state.copyWith(
        stickerTexts: texts,
        categoryIds: specs.map((s) => s.categoryId).toList(),
        generatedImages: List.filled(newCount, _kNotGeneratedSentinel),
        imageErrors: List.filled(newCount, null),
        colorSchemeIndices: List.generate(newCount, (i) => i % 8),
        imageScales: List.filled(newCount, 1.0),
        imageOffsets: List.filled(newCount, Offset.zero),
        fontIndices: List.filled(newCount, 0),
        styleIndices: List.filled(newCount, 0),
        fontSizeScales: List.filled(newCount, 1.0),
        textXAligns: List.filled(newCount, 0.0),
        textYAligns: List.filled(newCount, 0.85),
        textAngles: List.filled(newCount, 0.0),
        imageAngles: List.filled(newCount, 0.0),
        status: EditorStatus.ready,
      );
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack, reason: 'editor_update_categories_failed');
      state = state.copyWith(status: EditorStatus.ready);
    }
  }

  /// 使用者主動觸發第 [index] 張貼圖的圖片生成（扣 1 點）
  ///
  /// 回傳值：
  ///   'ok'              — 成功
  ///   'insufficient'    — 點數不足（呼叫方應彈出 paywall）
  ///   'error'           — 其他錯誤
  Future<String> generateSingleImage(int index) async {
    if (_specs == null || index >= _specs!.length) return 'error';

    // 設定 loading 狀態
    final loading = List<Uint8List?>.from(state.generatedImages);
    final clearErrors = List<String?>.from(state.imageErrors);
    loading[index] = null;
    clearErrors[index] = null;
    state = state.copyWith(generatedImages: loading, imageErrors: clearErrors);

    final styleIdx = state.styleIndices[index];

    try {
      final resized = _cachedResized ??
          await ImageProcessor.resizeForNative(File(state.originalImagePath));
      _cachedResized = resized;

      final result = await StickerGenerationService().generateSingle(
        resized,
        _specs![index],
        index: index,
        styleIndex: styleIdx,
        shape: state.stickerShape,
      );

      // 更新 credit（Cloud Function 回傳剩餘點數）
      if (result.remainingCredits >= 0) {
        ref.read(creditProvider.notifier).updateCredits(result.remainingCredits);
      }

      final updated = List<Uint8List?>.from(state.generatedImages);
      final errors = List<String?>.from(state.imageErrors);
      updated[index] = result.bytes ?? Uint8List(0);
      if (result.bytes == null) errors[index] = 'API 未回傳圖片';
      state = state.copyWith(generatedImages: updated, imageErrors: errors);
      return result.bytes != null ? 'ok' : 'error';
    } on FirebaseFunctionsException catch (e, stack) {
      if (e.code == 'resource-exhausted' &&
          e.message?.contains('Insufficient') == true) {
        // 點數不足，還原 loading 狀態（sentinel = Uint8List(0) 表示「未生成/待生成」）
        // 注意：此時點數未扣，不需退還
        final reset = List<Uint8List?>.from(state.generatedImages);
        // 重設為特殊 sentinel：空 Uint8List(1) 表示「未選擇生成」
        reset[index] = _kNotGeneratedSentinel;
        state = state.copyWith(generatedImages: reset);
        return 'insufficient';
      }
      await FirebaseService.recordError(e, stack,
          reason: 'generate_single_image_fn_failed_index$index');
      final failed = List<Uint8List?>.from(state.generatedImages);
      failed[index] = Uint8List(0);
      final errors = List<String?>.from(state.imageErrors);
      errors[index] = kDebugMode ? e.toString() : _classifyError(e);
      state = state.copyWith(generatedImages: failed, imageErrors: errors);
      return 'error';
    } catch (e, stack) {
      await FirebaseService.recordError(e, stack,
          reason: 'generate_single_image_failed_index$index');
      final failed = List<Uint8List?>.from(state.generatedImages);
      failed[index] = Uint8List(0);
      final errors = List<String?>.from(state.imageErrors);
      errors[index] = kDebugMode ? e.toString() : _classifyError(e);
      state = state.copyWith(generatedImages: failed, imageErrors: errors);
      return 'error';
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
  /// 風格直接影響 Gemini prompt，選完後立即重新生成該張圖片（扣 1 點）。
  Future<void> updateStyleIndex(int stickerIdx, int styleIdx) async {
    final updated = List<int>.from(state.styleIndices);
    updated[stickerIdx] = styleIdx;
    state = state.copyWith(styleIndices: updated);
    await generateSingleImage(stickerIdx);
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

  /// 重新生成指定索引的 AI 貼圖（單張重試，扣 1 點）
  Future<void> retryImageGeneration(int index) async {
    await generateSingleImage(index);
  }

  // ─── private ────────────────────────────────────────────

  /// 將例外轉換為使用者看得懂的中文訊息
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

/// 尚未選擇生成的 sentinel：length = 1 的空 Uint8List
///
/// sentinel 規則（generatedImages[i]）：
///   null                — 生成中（loading）
///   _kNotGeneratedSentinel (length=1) — 尚未選擇生成
///   Uint8List(0) (length=0)           — 生成失敗
///   Uint8List(>1) (length>1)          — 成功
final _kNotGeneratedSentinel = Uint8List(1);

/// 判斷是否為「尚未生成」sentinel
bool isNotGeneratedSentinel(Uint8List? bytes) =>
    bytes != null && bytes.length == 1;
