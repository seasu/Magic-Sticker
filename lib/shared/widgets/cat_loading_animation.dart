import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// 純向量貓咪 Loading 動畫（取代 MP4 影片）
///
/// 包含：尾巴左右搖擺、身體呼吸起伏、眨眼、四顆閃爍星星。
class CatLoadingAnimation extends StatefulWidget {
  const CatLoadingAnimation({super.key, this.size = 260});

  final double size;

  @override
  State<CatLoadingAnimation> createState() => _CatLoadingAnimationState();
}

class _CatLoadingAnimationState extends State<CatLoadingAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _tailCtrl;
  late final AnimationController _breathCtrl;
  late final AnimationController _sparkleCtrl;
  Timer? _blinkTimer;
  bool _eyeOpen = true;

  @override
  void initState() {
    super.initState();

    _tailCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _sparkleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(
      Duration(milliseconds: 1800 + Random().nextInt(2200)),
      () {
        if (!mounted) return;
        setState(() => _eyeOpen = false);
        Timer(const Duration(milliseconds: 130), () {
          if (!mounted) return;
          setState(() => _eyeOpen = true);
          _scheduleBlink();
        });
      },
    );
  }

  @override
  void dispose() {
    _tailCtrl.dispose();
    _breathCtrl.dispose();
    _sparkleCtrl.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_tailCtrl, _breathCtrl, _sparkleCtrl]),
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _CatPainter(
            tailT: _tailCtrl.value,
            breathT: _breathCtrl.value,
            sparkleT: _sparkleCtrl.value,
            eyeOpen: _eyeOpen,
          ),
        );
      },
    );
  }
}

class _CatPainter extends CustomPainter {
  final double tailT;
  final double breathT;
  final double sparkleT;
  final bool eyeOpen;

  const _CatPainter({
    required this.tailT,
    required this.breathT,
    required this.sparkleT,
    required this.eyeOpen,
  });

  // ── 顏色 ──────────────────────────────────────────────────────────────────

  static const _bodyColor    = Color(0xFFFFCC88);
  static const _bodyDark     = Color(0xFFE8A855);
  static const _bellyColor   = Color(0xFFFFF0D0);
  static const _earInner     = Color(0xFFFF9EB5);
  static const _cheek        = Color(0xFFFFB5C0);
  static const _eyeColor     = Color(0xFF2A1A0A);
  static const _noseColor    = Color(0xFFFF8EA0);
  static const _lineColor    = Color(0xFF3A2010);
  static const _whiskerColor = Color(0xFF9A8070);

  @override
  void paint(Canvas canvas, Size size) {
    // 在 200×200 虛擬畫布上繪製，然後縮放至實際大小
    final scale = size.width / 200;
    canvas.scale(scale, scale);

    _drawSparkles(canvas);
    _drawCat(canvas);
  }

  void _drawCat(Canvas canvas) {
    final breathY = -breathT * 2.5; // 身體上下起伏 0~2.5px

    canvas.save();
    canvas.translate(0, breathY);

    _drawTail(canvas);
    _drawBody(canvas);
    _drawHead(canvas);
    _drawEars(canvas);
    _drawStripes(canvas);
    _drawFace(canvas);

    canvas.restore();
  }

  // ── 尾巴 ───────────────────────────────────────────────────────────────────

  void _drawTail(Canvas canvas) {
    final swing = sin(tailT * pi); // 0 → 1 → 0（repeat+reverse 已做，再過 sin 讓曲線更自然）
    final sway = -18 + swing * 36; // -18 ~ +18 px 左右搖

    final tailPaint = Paint()
      ..color = _bodyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final tipPaint = Paint()
      ..color = _bodyDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;

    // 尾巴起點（身體右側）
    const sx = 136.0;
    const sy = 162.0;
    // 控制點
    final cx = sx + 30 + sway * 0.4;
    const cy = sy + 12.0;
    // 尾尖
    final ex = sx + 44 + sway;
    final ey = sy - 22.0;

    final path = Path()
      ..moveTo(sx, sy)
      ..quadraticBezierTo(cx, cy, ex, ey);

    canvas.drawPath(path, tailPaint);

    // 尾尖顏色較深的小段
    final tipPath = Path()
      ..moveTo(ex - (ex - cx) * 0.25, ey - (ey - cy) * 0.25)
      ..quadraticBezierTo(
        ex - (ex - cx) * 0.1,
        ey - (ey - cy) * 0.1,
        ex,
        ey,
      );
    canvas.drawPath(tipPath, tipPaint);
  }

  // ── 身體 ───────────────────────────────────────────────────────────────────

  void _drawBody(Canvas canvas) {
    final bodyPaint = Paint()..color = _bodyColor;
    final bellyPaint = Paint()..color = _bellyColor;

    // 身體
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(60, 128, 80, 58),
        const Radius.circular(22),
      ),
      bodyPaint,
    );

    // 肚子
    canvas.drawOval(
      const Rect.fromLTWH(72, 137, 56, 40),
      bellyPaint,
    );

    // 前爪（兩顆小橢圓）
    canvas.drawOval(
      const Rect.fromLTWH(68, 178, 26, 14),
      bodyPaint,
    );
    canvas.drawOval(
      const Rect.fromLTWH(106, 178, 26, 14),
      bodyPaint,
    );

    // 爪縫線
    final clawPaint = Paint()
      ..color = _lineColor.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (final xOffset in [-6.0, 0.0, 6.0]) {
      canvas.drawLine(
        Offset(81 + xOffset, 183),
        Offset(81 + xOffset, 190),
        clawPaint,
      );
      canvas.drawLine(
        Offset(119 + xOffset, 183),
        Offset(119 + xOffset, 190),
        clawPaint,
      );
    }
  }

  // ── 頭部 ───────────────────────────────────────────────────────────────────

  void _drawHead(Canvas canvas) {
    final headPaint = Paint()..color = _bodyColor;
    canvas.drawCircle(const Offset(100, 82), 52, headPaint);
  }

  // ── 耳朵 ───────────────────────────────────────────────────────────────────

  void _drawEars(Canvas canvas) {
    final earPaint = Paint()..color = _bodyColor;
    final innerPaint = Paint()..color = _earInner;

    // 左耳
    _drawTriangle(canvas, earPaint,
        const Offset(56, 58), const Offset(68, 24), const Offset(88, 52));
    _drawTriangle(canvas, innerPaint,
        const Offset(62, 55), const Offset(70, 31), const Offset(82, 50));

    // 右耳
    _drawTriangle(canvas, earPaint,
        const Offset(144, 58), const Offset(132, 24), const Offset(112, 52));
    _drawTriangle(canvas, innerPaint,
        const Offset(138, 55), const Offset(130, 31), const Offset(118, 50));
  }

  void _drawTriangle(Canvas canvas, Paint paint, Offset a, Offset b, Offset c) {
    canvas.drawPath(Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..close(), paint);
  }

  // ── 條紋 ───────────────────────────────────────────────────────────────────

  void _drawStripes(Canvas canvas) {
    final stripePaint = Paint()
      ..color = _bodyDark.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // 額頭三條橫紋
    for (int i = 0; i < 3; i++) {
      final y = 56.0 + i * 8;
      final halfW = 14.0 - i * 2;
      canvas.drawLine(
        Offset(100 - halfW, y),
        Offset(100 + halfW, y),
        stripePaint,
      );
    }
  }

  // ── 臉部 ───────────────────────────────────────────────────────────────────

  void _drawFace(Canvas canvas) {
    // 腮紅
    final blushPaint = Paint()..color = _cheek.withOpacity(0.55);
    canvas.drawOval(const Rect.fromLTWH(60, 88, 24, 13), blushPaint);
    canvas.drawOval(const Rect.fromLTWH(116, 88, 24, 13), blushPaint);

    // 眼睛
    if (eyeOpen) {
      // 眼球
      final eyePaint = Paint()..color = _eyeColor;
      canvas.drawCircle(const Offset(84, 80), 8, eyePaint);
      canvas.drawCircle(const Offset(116, 80), 8, eyePaint);

      // 瞳孔高光
      final shinePaint = Paint()..color = Colors.white;
      canvas.drawCircle(const Offset(87, 77), 3, shinePaint);
      canvas.drawCircle(const Offset(119, 77), 3, shinePaint);

      // 眼白底層（讓眼神更Q版）
      final eyeWhitePaint = Paint()
        ..color = const Color(0xFF5C8A3C) // 橄欖綠虹膜
        ..style = PaintingStyle.fill;
      canvas.drawCircle(const Offset(84, 80), 5.5, eyeWhitePaint);
      canvas.drawCircle(const Offset(116, 80), 5.5, eyeWhitePaint);

      // 重畫瞳孔（在虹膜上）
      final pupilPaint = Paint()..color = _eyeColor;
      canvas.drawCircle(const Offset(84, 80), 4, pupilPaint);
      canvas.drawCircle(const Offset(116, 80), 4, pupilPaint);

      final shine2 = Paint()..color = Colors.white;
      canvas.drawCircle(const Offset(86, 78), 1.8, shine2);
      canvas.drawCircle(const Offset(118, 78), 1.8, shine2);
    } else {
      // 閉眼（弧線）
      final closedPaint = Paint()
        ..color = _eyeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;

      final leftEye = Path()
        ..moveTo(77, 80)
        ..quadraticBezierTo(84, 74, 91, 80);
      canvas.drawPath(leftEye, closedPaint);

      final rightEye = Path()
        ..moveTo(109, 80)
        ..quadraticBezierTo(116, 74, 123, 80);
      canvas.drawPath(rightEye, closedPaint);
    }

    // 鼻子（粉紅小三角）
    _drawTriangle(
      canvas,
      Paint()..color = _noseColor,
      const Offset(100, 92),
      const Offset(94, 99),
      const Offset(106, 99),
    );

    // 嘴巴
    final mouthPaint = Paint()
      ..color = _lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final mouth = Path()
      ..moveTo(93, 102)
      ..quadraticBezierTo(100, 109, 107, 102);
    canvas.drawPath(mouth, mouthPaint);

    // 鬍鬚
    final whiskerPaint = Paint()
      ..color = _whiskerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // 左三根
    canvas.drawLine(const Offset(50, 90), const Offset(87, 96), whiskerPaint);
    canvas.drawLine(const Offset(48, 99), const Offset(86, 100), whiskerPaint);
    canvas.drawLine(const Offset(50, 108), const Offset(87, 104), whiskerPaint);
    // 右三根
    canvas.drawLine(const Offset(150, 90), const Offset(113, 96), whiskerPaint);
    canvas.drawLine(const Offset(152, 99), const Offset(114, 100), whiskerPaint);
    canvas.drawLine(const Offset(150, 108), const Offset(113, 104), whiskerPaint);
  }

  // ── 閃爍星星 ───────────────────────────────────────────────────────────────

  static const _sparklePositions = [
    Offset(22, 44),
    Offset(174, 32),
    Offset(16, 148),
    Offset(178, 152),
  ];

  static const _sparkleColors = [
    Color(0xFFFFD700),
    Color(0xFFFF6BAE),
    Color(0xFF74C0FC),
    Color(0xFF63E6BE),
  ];

  void _drawSparkles(Canvas canvas) {
    for (int i = 0; i < _sparklePositions.length; i++) {
      final phase = sparkleT * 2 * pi + i * (pi / 2);
      final scale = 0.55 + sin(phase) * 0.45;
      final opacity = (0.3 + sin(phase) * 0.5).clamp(0.0, 1.0);
      _drawFourPointStar(
        canvas,
        _sparklePositions[i],
        outerR: 11 * scale,
        innerR: 4.5 * scale,
        color: _sparkleColors[i].withOpacity(opacity),
        rotation: phase * 0.5,
      );
    }
  }

  void _drawFourPointStar(
    Canvas canvas,
    Offset center, {
    required double outerR,
    required double innerR,
    required Color color,
    double rotation = 0,
  }) {
    final paint = Paint()..color = color;
    final path = Path();
    const points = 4;
    for (int i = 0; i < points * 2; i++) {
      final angle = rotation + i * pi / points;
      final r = i.isEven ? outerR : innerR;
      final x = center.dx + r * cos(angle - pi / 2);
      final y = center.dy + r * sin(angle - pi / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CatPainter old) =>
      old.tailT != tailT ||
      old.breathT != breathT ||
      old.sparkleT != sparkleT ||
      old.eyeOpen != eyeOpen;
}
