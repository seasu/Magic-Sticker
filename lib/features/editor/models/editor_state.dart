import 'dart:typed_data';
import 'dart:ui' show Offset;

enum EditorStatus {
  idle,
  removingBackground,
  generatingTexts,
  ready, // AI 圖片可能仍在後台生成
  exporting,
}

const _kFallbackTexts = [
  '哈囉！', '太棒了！', '真的嗎？', '尷尬了...',
  '哼！', '開心！', '我想想...', '再見囉！',
];

class EditorState {
  final String originalImagePath;
  final Uint8List? subjectBytes;          // 去背結果 PNG（保留作 fallback）
  final List<String> stickerTexts;        // 8 組情感標語
  final List<Uint8List?> generatedImages; // 8 張 Gemini 生成圓形貼圖（null = 仍在生成）
  final List<String?> imageErrors;        // 對應每張的失敗原因（null = 無錯誤）
  final EditorStatus status;
  final String? errorMessage;
  final List<int> colorSchemeIndices;     // 每張貼圖使用哪組配色 (0-7)
  final List<double> imageScales;         // 每張貼圖的縮放值
  final List<Offset> imageOffsets;        // 每張貼圖的位移量
  final List<int> fontIndices;            // 每張貼圖的字型索引 (0-4)
  final List<int> styleIndices;           // 每張貼圖的產圖風格索引 (0-4)
  final List<double> fontSizeScales;      // 每張貼圖的字體大小倍率 (0.3–3.0)
  final List<double> textXAligns;         // 文字水平對齊 (-1.5=左, 0=中, 1.5=右)
  final List<double> textYAligns;         // 文字垂直對齊 (-1.5=上, 0.85=近底部)
  final List<double> textAngles;          // 文字旋轉角度（弧度，0=不旋轉）
  final List<double> imageAngles;         // 圖片旋轉角度（弧度，0=不旋轉）

  EditorState({
    required this.originalImagePath,
    this.subjectBytes,
    List<String>? stickerTexts,
    List<Uint8List?>? generatedImages,
    List<String?>? imageErrors,
    this.status = EditorStatus.idle,
    this.errorMessage,
    List<int>? colorSchemeIndices,
    List<double>? imageScales,
    List<Offset>? imageOffsets,
    List<int>? fontIndices,
    List<int>? styleIndices,
    List<double>? fontSizeScales,
    List<double>? textXAligns,
    List<double>? textYAligns,
    List<double>? textAngles,
    List<double>? imageAngles,
  })  : stickerTexts = stickerTexts ?? List.from(_kFallbackTexts),
        generatedImages = generatedImages ?? List.filled(8, null),
        imageErrors = imageErrors ?? List.filled(8, null),
        colorSchemeIndices = colorSchemeIndices ?? List.generate(8, (i) => i),
        imageScales = imageScales ?? List.filled(8, 1.0),
        imageOffsets = imageOffsets ?? List.filled(8, Offset.zero),
        fontIndices = fontIndices ?? List.filled(8, 0),
        styleIndices = styleIndices ?? List.filled(8, 0),
        fontSizeScales = fontSizeScales ?? List.filled(8, 1.0),
        textXAligns = textXAligns ?? List.filled(8, 0.0),
        textYAligns = textYAligns ?? List.filled(8, 0.85),
        textAngles = textAngles ?? List.filled(8, 0.0),
        imageAngles = imageAngles ?? List.filled(8, 0.0);

  EditorState copyWith({
    Uint8List? subjectBytes,
    List<String>? stickerTexts,
    List<Uint8List?>? generatedImages,
    List<String?>? imageErrors,
    EditorStatus? status,
    String? errorMessage,
    List<int>? colorSchemeIndices,
    List<double>? imageScales,
    List<Offset>? imageOffsets,
    List<int>? fontIndices,
    List<int>? styleIndices,
    List<double>? fontSizeScales,
    List<double>? textXAligns,
    List<double>? textYAligns,
    List<double>? textAngles,
    List<double>? imageAngles,
  }) {
    return EditorState(
      originalImagePath: originalImagePath,
      subjectBytes: subjectBytes ?? this.subjectBytes,
      stickerTexts: stickerTexts ?? this.stickerTexts,
      generatedImages: generatedImages ?? this.generatedImages,
      imageErrors: imageErrors ?? this.imageErrors,
      status: status ?? this.status,
      errorMessage: errorMessage,
      colorSchemeIndices: colorSchemeIndices ?? this.colorSchemeIndices,
      imageScales: imageScales ?? this.imageScales,
      imageOffsets: imageOffsets ?? this.imageOffsets,
      fontIndices: fontIndices ?? this.fontIndices,
      styleIndices: styleIndices ?? this.styleIndices,
      fontSizeScales: fontSizeScales ?? this.fontSizeScales,
      textXAligns: textXAligns ?? this.textXAligns,
      textYAligns: textYAligns ?? this.textYAligns,
      textAngles: textAngles ?? this.textAngles,
      imageAngles: imageAngles ?? this.imageAngles,
    );
  }
}
