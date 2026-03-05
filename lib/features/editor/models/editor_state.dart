import 'dart:typed_data';

enum EditorStatus {
  idle,
  removingBackground,
  generatingTexts,
  ready,
  exporting,
}

const _kFallbackTexts = ['好棒！', '讚喔', '超可愛✨'];

class EditorState {
  final String originalImagePath;
  final Uint8List? subjectBytes; // 去背結果 PNG（透明背景）
  final List<String> stickerTexts; // 3 組 AI 短文字
  final EditorStatus status;
  final String? errorMessage;

  EditorState({
    required this.originalImagePath,
    this.subjectBytes,
    List<String>? stickerTexts,
    this.status = EditorStatus.idle,
    this.errorMessage,
  }) : stickerTexts = stickerTexts ?? List.from(_kFallbackTexts);

  EditorState copyWith({
    Uint8List? subjectBytes,
    List<String>? stickerTexts,
    EditorStatus? status,
    String? errorMessage,
  }) {
    return EditorState(
      originalImagePath: originalImagePath,
      subjectBytes: subjectBytes ?? this.subjectBytes,
      stickerTexts: stickerTexts ?? this.stickerTexts,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }
}
