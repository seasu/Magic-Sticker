import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── 配色 ──────────────────────────────────────────────────────────────────────
// 粉紅品牌色系：珊瑚粉貓咪 × 極淡玫瑰底，與整體 App 色調一致
const _kCatBody  = Color(0xFFFD297B); // 貓身主色（品牌珊瑚粉）
const _kCatLight = Color(0xFFFFB3C6); // 耳朵內側、鼻子等亮部（淡粉紅）
const _kBg       = Color(0xFFFFF0F3); // 背景（極淡玫瑰白）

/// 全畫面或全幅 Loading 動畫。
/// 取代舊版兩個 GIF，統一為一個純 Flutter CustomPainter 貓咪跑步動畫。
///
/// 用法（全螢幕）：
/// ```dart
/// Expanded(child: CatLoadingWidget(title: 'AI 分析中', subtitle: '約 5~10 秒'))
/// ```
///
/// 用法（疊加遮罩）：
/// ```dart
/// AbsorbPointer(child: CatLoadingWidget(title: 'AI 生成中', subtitle: '約 20~30 秒'))
/// ```
class CatLoadingWidget extends StatefulWidget {
  final String? title;
  final String? subtitle;

  const CatLoadingWidget({super.key, this.title, this.subtitle});

  @override
  State<CatLoadingWidget> createState() => _CatLoadingWidgetState();
}

class _CatLoadingWidgetState extends State<CatLoadingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
      color: _kBg,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── 標題 ──────────────────────────────────────────────────
          if (widget.title != null) ...[
            Text(
              widget.title!,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF21262E),
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                color: const Color(0xFFFF5864),
              ),
            ),
            const SizedBox(height: 32),
          ],

          // ── 貓咪動畫 ──────────────────────────────────────────────
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => CustomPaint(
              size: const Size(220, 160),
              painter: _RunningCatPainter(t: _ctrl.value),
            ),
          ),

          const SizedBox(height: 28),

          // ── 跳動點 ─────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => _BouncingDots(t: _ctrl.value),
          ),
        ],
      ),
    ));
  }
}

// ─── 跳動三點 ─────────────────────────────────────────────────────────────────

class _BouncingDots extends StatelessWidget {
  final double t;
  const _BouncingDots({required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        // 每個點的相位錯開 1/3
        final phase = (t + i / 3.0) % 1.0;
        final dy = -sin(phase * pi) * 6.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _kCatBody.withValues(alpha: 0.6 + 0.4 * sin(phase * pi)),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── 奔跑貓咪 CustomPainter ────────────────────────────────────────────────────

class _RunningCatPainter extends CustomPainter {
  final double t; // 0.0 → 1.0, 動畫進度

  const _RunningCatPainter({required this.t});

  // ── 畫筆 ──────────────────────────────────────────────────────────────────

  Paint get _fill   => Paint()..color = _kCatBody..style = PaintingStyle.fill;
  Paint get _light  => Paint()..color = _kCatLight..style = PaintingStyle.fill;
  Paint get _stroke => Paint()
    ..color = _kCatBody
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;

  // ── 動畫數值計算 ──────────────────────────────────────────────────────────

  /// 跑步節奏（0→1→0 半週期）
  double _cycle(double offset) => sin((t + offset) * 2 * pi);

  @override
  void paint(Canvas canvas, Size size) {
    // 貓咪邏輯座標中心 → 畫布中心偏下
    final cx = size.width * 0.48;
    final cy = size.height * 0.52;

    // 身體上下彈跳
    final bodyBounce = _cycle(0) * 3.5;

    canvas.save();
    canvas.translate(cx, cy + bodyBounce);

    _drawMotionLines(canvas);
    _drawTail(canvas);
    _drawLegs(canvas);
    _drawBody(canvas);
    _drawHead(canvas);

    canvas.restore();
  }

  // ── 殘影速度線 ─────────────────────────────────────────────────────────────

  void _drawMotionLines(Canvas canvas) {
    final linePaint = Paint()
      ..color = _kCatBody.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    const lines = [
      (-58.0, -6.0, 14.0),
      (-62.0,  2.0, 10.0),
      (-55.0,  9.0, 18.0),
    ];
    for (final (x, y, len) in lines) {
      canvas.drawLine(Offset(x, y), Offset(x - len, y), linePaint);
    }
  }

  // ── 尾巴 ──────────────────────────────────────────────────────────────────

  void _drawTail(Canvas canvas) {
    // 尾巴從身體左後方往上擺
    final wag = _cycle(0.25) * 18 * (pi / 180); // ±18° 搖擺

    canvas.save();
    canvas.translate(-38.0, -4.0); // 尾巴根部
    canvas.rotate(wag);

    final path = Path();
    path.moveTo(0, 0);
    path.cubicTo(-8, -18, -4, -36, 6, -44);

    canvas.drawPath(path, _stroke..strokeWidth = 4.5);

    // 尾巴尖端圓球
    canvas.drawCircle(const Offset(6, -44), 5.5, _fill);

    canvas.restore();
  }

  // ── 四條腿 ────────────────────────────────────────────────────────────────

  void _drawLegs(Canvas canvas) {
    // 跑步週期：前腳與後腳交替
    final frontSwing  = _cycle(0)    * 22 * (pi / 180); // ±22°
    final backSwing   = _cycle(0.5)  * 22 * (pi / 180); // 反相

    // 前腳右（靠近頭側，較前方）
    _drawLeg(canvas, x: 18.0, y: 14.0, angle: frontSwing,  len: 24.0);
    // 後腳左（遠離頭側，較後方）
    _drawLeg(canvas, x:-22.0, y: 14.0, angle: backSwing,   len: 24.0);
    // 前腳左（在身後，稍透明）
    _drawLeg(canvas, x: 10.0, y: 14.0, angle: -frontSwing, len: 24.0,
        alpha: 0.55);
    // 後腳右（在身後）
    _drawLeg(canvas, x:-14.0, y: 14.0, angle: -backSwing,  len: 24.0,
        alpha: 0.55);
  }

  void _drawLeg(Canvas canvas, {
    required double x,
    required double y,
    required double angle,
    required double len,
    double alpha = 1.0,
  }) {
    final paint = Paint()
      ..color = _kCatBody.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);

    // 大腿段
    final thigh = RRect.fromRectAndRadius(
      Rect.fromLTWH(-3.5, 0, 7, 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(thigh, paint);

    // 小腿段（帶關節角度）
    canvas.save();
    canvas.translate(0, 12);
    canvas.rotate(-angle * 0.6); // 關節彎折
    final shin = RRect.fromRectAndRadius(
      Rect.fromLTWH(-3, 0, 6, len - 12),
      const Radius.circular(3),
    );
    canvas.drawRRect(shin, paint);

    // 小腳掌
    canvas.drawOval(
      Rect.fromLTWH(-5, len - 14, 10, 5),
      paint,
    );

    canvas.restore();
    canvas.restore();
  }

  // ── 身體 ──────────────────────────────────────────────────────────────────

  void _drawBody(Canvas canvas) {
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-42, -18, 80, 38),
      const Radius.circular(20),
    );
    canvas.drawRRect(body, _fill);

    // 肚子亮斑（橢圓形淺色）
    canvas.drawOval(
      const Rect.fromLTWH(-20, -8, 36, 20),
      _light..color = _kCatLight.withValues(alpha: 0.30),
    );
  }

  // ── 頭部 + 耳朵 + 臉 ──────────────────────────────────────────────────────

  void _drawHead(Canvas canvas) {
    const hx = 38.0; // 頭中心 X（相對身體中心）
    const hy = -24.0;

    // ── 耳朵 ──
    _drawEar(canvas, hx - 13, hy - 18, flip: false); // 左耳
    _drawEar(canvas, hx + 13, hy - 18, flip: true);  // 右耳

    // ── 頭圓 ──
    canvas.drawCircle(Offset(hx, hy), 22, _fill);

    // ── 眼睛 ──
    final eyePaint = Paint()..color = _kBg..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(hx + 7,  hy - 4), 5.5, eyePaint);
    canvas.drawCircle(Offset(hx - 3,  hy - 4), 5.5, eyePaint);

    // 瞳孔（眨眼：每2秒眨一次）
    final blink = (t % 1.0 > 0.92); // 動畫最後 8% 時間閉眼
    if (blink) {
      // 閉眼：畫橫線
      canvas.drawLine(
        Offset(hx + 3,  hy - 4),
        Offset(hx + 11, hy - 4),
        _stroke..strokeWidth = 2.5,
      );
      canvas.drawLine(
        Offset(hx - 7,  hy - 4),
        Offset(hx + 1,  hy - 4),
        _stroke..strokeWidth = 2.5,
      );
    } else {
      canvas.drawCircle(Offset(hx + 8,  hy - 4), 3.0, _fill);
      canvas.drawCircle(Offset(hx - 2,  hy - 4), 3.0, _fill);
    }

    // ── 鼻子 ──
    final nosePath = Path()
      ..moveTo(hx + 4,  hy + 4)
      ..lineTo(hx + 7,  hy + 8)
      ..lineTo(hx + 1,  hy + 8)
      ..close();
    canvas.drawPath(nosePath, Paint()..color = _kCatLight);

    // ── 嘴巴 ──
    final mouthPath = Path()
      ..moveTo(hx + 4,  hy + 8)
      ..quadraticBezierTo(hx + 2,  hy + 12, hx - 1, hy + 11)
      ..moveTo(hx + 4,  hy + 8)
      ..quadraticBezierTo(hx + 6,  hy + 12, hx + 9, hy + 11);
    canvas.drawPath(mouthPath, _stroke..strokeWidth = 1.8);

    // ── 鬍鬚 ──
    _drawWhiskers(canvas, hx, hy);
  }

  void _drawEar(Canvas canvas, double x, double y, {required bool flip}) {
    final dir = flip ? 1.0 : -1.0;

    // 外耳
    final ear = Path()
      ..moveTo(x,        y + 12)
      ..lineTo(x + dir * 10, y - 6)
      ..lineTo(x + dir * 20, y + 12)
      ..close();
    canvas.drawPath(ear, _fill);

    // 內耳（淺色三角）
    final inner = Path()
      ..moveTo(x + dir * 4,  y + 10)
      ..lineTo(x + dir * 10, y - 1)
      ..lineTo(x + dir * 16, y + 10)
      ..close();
    canvas.drawPath(inner, _light);
  }

  void _drawWhiskers(Canvas canvas, double hx, double hy) {
    final wPaint = Paint()
      ..color = _kCatLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // 左邊鬍鬚
    canvas.drawLine(Offset(hx - 5, hy + 6), Offset(hx - 22, hy + 4),  wPaint);
    canvas.drawLine(Offset(hx - 5, hy + 8), Offset(hx - 22, hy + 10), wPaint);

    // 右邊鬍鬚
    canvas.drawLine(Offset(hx + 8, hy + 6), Offset(hx + 22, hy + 4),  wPaint);
    canvas.drawLine(Offset(hx + 8, hy + 8), Offset(hx + 22, hy + 10), wPaint);
  }

  @override
  bool shouldRepaint(_RunningCatPainter old) => old.t != t;
}
