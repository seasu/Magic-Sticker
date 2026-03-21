class StickerRecord {
  final String id;
  final String filePath;
  final DateTime createdAt;
  final String stickerText;
  final int styleIndex;
  final String shapeStr; // 'circle' or 'square'
  final String? originalThumbnailPath; // 原圖縮圖路徑（新紀錄才有，舊紀錄為 null）

  const StickerRecord({
    required this.id,
    required this.filePath,
    required this.createdAt,
    required this.stickerText,
    required this.styleIndex,
    required this.shapeStr,
    this.originalThumbnailPath,
  });

  factory StickerRecord.fromJson(Map<String, dynamic> json) => StickerRecord(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        stickerText: json['stickerText'] as String,
        styleIndex: json['styleIndex'] as int,
        shapeStr: json['shapeStr'] as String,
        originalThumbnailPath: json['originalThumbnailPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'stickerText': stickerText,
        'styleIndex': styleIndex,
        'shapeStr': shapeStr,
        if (originalThumbnailPath != null)
          'originalThumbnailPath': originalThumbnailPath,
      };
}
