import 'dart:typed_data';

enum EditorStatus {
  idle,
  removingBackground,
  generatingTexts,
  ready, // 文字已就緒；AI 圖片可能仍在後台生成
  exporting,
}

const _kFallbackTexts = ['好棒！', '讚喔', '超可愛✨'];

class EditorState {
  final String originalImagePath;
  final Uint8List? subjectBytes;       // 去背結果 PNG
  final List<String> stickerTexts;     // 3 組 AI 短文字
  final List<Uint8List?> generatedImages; // 3 張 Gemini 生成插圖（null = 仍在生成）
  final EditorStatus status;
  final String? errorMessage;

  EditorState({
    required this.originalImagePath,
    this.subjectBytes,
    List<String>? stickerTexts,
    List<Uint8List?>? generatedImages,
    this.status = EditorStatus.idle,
    this.errorMessage,
  })  : stickerTexts = stickerTexts ?? List.from(_kFallbackTexts),
        generatedImages = generatedImages ?? [null, null, null];

  EditorState copyWith({
    Uint8List? subjectBytes,
    List<String>? stickerTexts,
    List<Uint8List?>? generatedImages,
    EditorStatus? status,
    String? errorMessage,
  }) {
    return EditorState(
      originalImagePath: originalImagePath,
      subjectBytes: subjectBytes ?? this.subjectBytes,
      stickerTexts: stickerTexts ?? this.stickerTexts,
      generatedImages: generatedImages ?? this.generatedImages,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }
}
