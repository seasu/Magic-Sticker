import 'package:flutter/material.dart';
import '../models/frame_style.dart';

/// CustomPainter that draws a decorative frame around the canvas.
///
/// For [filled] styles (polaroid, filmStrip) it paints a solid fill;
/// for all others it paints a stroke outline.
class FramePainter extends CustomPainter {
  final FrameStyle style;

  const FramePainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height).deflate(style.strokeWidth / 2 + 2);
    final path = buildFramePath(style.shape, bounds);

    if (style.filled) {
      // Paint solid fill (e.g. white polaroid frame background)
      final fillPaint = Paint()
        ..color = style.color
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);

      // Thin accent stroke on top
      final strokePaint = Paint()
        ..color = style.color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, strokePaint);
    } else {
      // Shadow / glow behind stroke
      final shadowPaint = Paint()
        ..color = style.color.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth + 6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawPath(path, shadowPaint);

      // Main stroke
      final strokePaint = Paint()
        ..color = style.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, strokePaint);

      // White inner highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth * 0.35
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(path, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(FramePainter old) => old.style != style;
}

/// Widget wrapper — sizes itself to fill its parent and draws the frame on top.
class FrameOverlay extends StatelessWidget {
  final FrameStyle style;
  final Widget child;

  const FrameOverlay({super.key, required this.style, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        CustomPaint(painter: FramePainter(style: style)),
      ],
    );
  }
}

/// Small thumbnail for the frame picker strip.
class FrameThumbnail extends StatelessWidget {
  final FrameStyle style;
  final bool selected;
  final VoidCallback onTap;

  const FrameThumbnail({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        width: 60,
        height: 60,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: const Color(0xFFFD297B), width: 2.5)
              : Border.all(color: Colors.grey.shade200, width: 1.5),
          boxShadow: selected
              ? [BoxShadow(color: const Color(0xFFFD297B).withValues(alpha: 0.3), blurRadius: 8)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)],
        ),
        child: Stack(
          children: [
            // Mini preview of frame shape
            Padding(
              padding: const EdgeInsets.all(6),
              child: CustomPaint(
                painter: FramePainter(style: FrameStyle(
                  shape: style.shape,
                  label: style.label,
                  color: style.color,
                  strokeWidth: 5,
                  filled: style.filled,
                )),
                child: const SizedBox.expand(),
              ),
            ),
            // Label
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                ),
                child: Text(
                  style.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: style.color == Colors.white ? const Color(0xFF999999) : style.color,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
