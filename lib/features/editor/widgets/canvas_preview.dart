import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 合成畫布：背景層 → 主體層 → 文字層
class CanvasPreview extends StatelessWidget {
  final String originalImagePath;
  final Uint8List? subjectBytes;
  final String caption;
  final double fontSize;

  const CanvasPreview({
    super.key,
    required this.originalImagePath,
    required this.subjectBytes,
    required this.caption,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景層：模糊化的原圖
          ClipRect(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Image.file(
                File(originalImagePath),
                fit: BoxFit.cover,
              ),
            ),
          ),

          // 主體層：去背後的 PNG
          if (subjectBytes != null)
            Center(
              child: Image.memory(
                subjectBytes!,
                fit: BoxFit.contain,
              ),
            ),

          // 文字層：早安文案
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(blurRadius: 4, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
