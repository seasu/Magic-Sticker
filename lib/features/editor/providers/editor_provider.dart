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
  ///
  /// Step 1 (generatingTexts)：Gemini 文字模型分析照片，
  ///   自由決定 8 張貼圖的【情感主題、中文標語、背景色】
  ///   → 立即顯示文字標籤在卡片上（fallback canvas）
  ///
  /// Step 2 (ready, 後台)：Gemini 圖片模型依 AI 規格並行生成圓形貼圖
  ///   → 每張完成後即時更新對應卡片
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

    // Step 1：讓 AI 自由決定 8 組貼圖規格（文字 + 情感 + 顏色）
    _specs = await GeminiService().generateStickerSpecs(resized);
    final texts = _specs!.map((s) => s.text).toList();
    state = state.copyWith(stickerTexts: texts, status: EditorStatus.ready);

    // Step 2：後台並行生成 8 張圓形貼圖圖片
    _generateImagesInBackground(resized, _specs!);
  }

  /// 重新讓 AI 自由發揮，生成全新 8 組規格 + 圖片
  Future<void> regenerateTexts() async {
    state = state.copyWith(
      status: EditorStatus.generatingTexts,
      generatedImages: List.filled(8, null),
    );
    try {
      final resized = await ImageProcessor.resizeForNative(
        File(state.originalImagePath),
      );
      _specs = await GeminiService().generateStickerSpecs(resized);
      final texts = _specs!.map((s) => s.text).toList();
      state = state.copyWith(stickerTexts: texts, status: EditorStatus.ready);
      _generateImagesInBackground(resized, _specs!);
    } catch (e, stack) {
      await FirebaseService.recordError(
        e, stack, reason: 'editor_regen_failed',
      );
      state = state.copyWith(status: EditorStatus.ready);
    }
  }

  /// 使用者手動修改第 [index] 張貼圖的文字（fallback 模式用）
  void updateStickerText(int index, String text) {
    final updated = List<String>.from(state.stickerTexts);
    updated[index] = text;
    state = state.copyWith(stickerTexts: updated);
  }

  /// 使用者切換第 [stickerIndex] 張貼圖的邊框樣式
  void updateFrameIndex(int stickerIndex, int frameIndex) {
    final updated = List<int>.from(state.frameIndices);
    updated[stickerIndex] = frameIndex;
    state = state.copyWith(frameIndices: updated);
  }

  // ─── private ────────────────────────────────────────────

  /// 後台並行生成 8 張 AI 圓形貼圖；每張完成後立即更新對應卡片（非阻塞）
  ///
  /// sentinel 規則（Uint8List?）：
  ///   null          → 生成中（顯示 "Gemini 貼圖生成中…" badge）
  ///   Uint8List(0)  → 生成完但 API 失敗/無圖（顯示 fallback 文字貼圖）
  ///   Uint8List(>0) → 成功，顯示 AI 圓形貼圖
  void _generateImagesInBackground(Uint8List photoBytes, List<StickerSpec> specs) {
    for (int i = 0; i < specs.length; i++) {
      final index = i;
      final spec = specs[i];
      StickerGenerationService().generateOne(photoBytes, spec, index).then((img) {
        try {
          final updated = List<Uint8List?>.from(state.generatedImages);
          updated[index] = img ?? Uint8List(0);
          state = state.copyWith(generatedImages: updated);
        } catch (_) {
          // provider 已 dispose，忽略
        }
      });
    }
  }
}
