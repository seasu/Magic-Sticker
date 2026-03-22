import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── 互動狀態機 ───────────────────────────────────────────────────────────────
enum _CatState { idle, chasing, playing }

/// 全畫面 Loading 動畫。
///
/// 使用者可點擊畫面任意位置「丟球」，貓咪會跑過去玩，
/// 讓等待 AI 生成的時間更有趣。
///
/// 用法（全螢幕）：
/// ```dart
/// Expanded(child: CatLoadingWidget(title: 'AI 分析中', subtitle: '約 5~10 秒'))
/// ```
///
/// 用法（疊加遮罩，取代舊的 AbsorbPointer 包裹）：
/// ```dart
/// CatLoadingWidget(title: 'AI 生成中', subtitle: '約 20~30 秒')
/// ```
class CatLoadingWidget extends StatefulWidget {
  final String? title;
  final String? subtitle;

  const CatLoadingWidget({super.key, this.title, this.subtitle});

  @override
  State<CatLoadingWidget> createState() => _CatLoadingWidgetState();
}

class _CatLoadingWidgetState extends State<CatLoadingWidget>
    with TickerProviderStateMixin {
  // ── 動畫控制器 ────────────────────────────────────────────────────────────
  late final AnimationController _runCtrl;  // 640ms 跑步循環
  late final AnimationController _moveCtrl; // 800ms 移動到球
  late final AnimationController _playCtrl; // 600ms 開心 + 拍球
  late final AnimationController _ballCtrl; // 球出現(300ms)/消失(500ms)

  // ── 狀態機 ───────────────────────────────────────────────────────────────
  _CatState _catState = _CatState.idle;
  Offset? _catPos;              // 貓咪中心（首次 build 後初始化）
  Offset _catMoveStart = Offset.zero;
  Offset _catTarget   = Offset.zero;
  Offset _ballPos     = Offset.zero;
  bool _facingLeft    = false;
  bool _hasInteracted = false;
  Size _stackSize     = Size.zero;
  int  _generation    = 0; // 取消過期的 Future 回呼

  @override
  void initState() {
    super.initState();
    _runCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..repeat();

    _moveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _playCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _ballCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _runCtrl.dispose();
    _moveCtrl.dispose();
    _playCtrl.dispose();
    _ballCtrl.dispose();
    super.dispose();
  }

  // ── 貓咪目前渲染位置 ──────────────────────────────────────────────────────
  Offset get _currentCatPos {
    if (_catPos == null) return Offset.zero;
    if (_catState == _CatState.idle) return _catPos!;
    if (_catState == _CatState.chasing) {
      final t = Curves.easeInOut.transform(_moveCtrl.value);
      return Offset.lerp(_catMoveStart, _catTarget, t)!;
    }
    return _catTarget; // playing：停在球旁
  }

  // ── 使用者點擊「丟球」──────────────────────────────────────────────────────
  void _throwBall(Offset tapPos) {
    if (!mounted || _catPos == null) return;
    HapticFeedback.lightImpact();

    // 夾住目標位置（避免蓋住標題與底部）
    final clampedTarget = Offset(
      tapPos.dx.clamp(60.0, _stackSize.width  - 60.0),
      tapPos.dy.clamp(160.0, _stackSize.height - 80.0),
    );

    // 停止正在進行的動畫
    _moveCtrl.stop();
    _playCtrl.stop();

    final fromPos   = _currentCatPos;
    final thisGen   = ++_generation;

    setState(() {
      _hasInteracted = true;
      _catMoveStart  = fromPos;
      _catTarget     = clampedTarget;
      _ballPos       = clampedTarget;
      _facingLeft    = clampedTarget.dx < fromPos.dx;
      _catState      = _CatState.chasing;
    });

    // 球出現（彈跳進場）
    _ballCtrl.forward(from: 0);

    // 貓移動
    _moveCtrl.forward(from: 0).then((_) {
      if (!mounted || _generation != thisGen) return;
      setState(() {
        _catPos   = _catTarget;
        _catState = _CatState.playing;
      });
      _playCtrl.forward(from: 0);

      // 2 秒後回到 idle
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (!mounted || _generation != thisGen) return;
        _ballCtrl.reverse(); // 球淡出
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted || _generation != thisGen) return;
          setState(() => _catState = _CatState.idle);
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
        // 首次：初始化貓咪位置在畫面中央偏下
        _catPos ??= Offset(
          constraints.maxWidth  / 2,
          constraints.maxHeight * 0.58,
        );

        return GestureDetector(
          onTapDown: (d) => _throwBall(d.localPosition),
          behavior: HitTestBehavior.opaque, // 吸收所有觸控，取代外層 AbsorbPointer
          child: ColoredBox(
            color: CatColorScheme.pink.bg,
            child: AnimatedBuilder(
              animation: Listenable.merge(
                  [_runCtrl, _moveCtrl, _playCtrl, _ballCtrl]),
              builder: (context, _) {
                final currentPos  = _currentCatPos;
                final isHappy     = _catState == _CatState.playing &&
                    _playCtrl.value > 0.2;
                final exciteLevel = _catState == _CatState.playing
                    ? _playCtrl.value
                    : 0.0;
                final hintAlpha   = (sin(_runCtrl.value * 2 * pi) * 0.15 + 0.60)
                    .clamp(0.45, 0.75);

                return Stack(
                  children: [

                    // ── 標題 / 副標（固定頂部）────────────────────────────
                    Positioned(
                      top: 52,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.title != null)
                            Text(
                              widget.title!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF21262E),
                              ),
                            ),
                          if (widget.title != null && widget.subtitle != null)
                            const SizedBox(height: 6),
                          if (widget.subtitle != null)
                            Text(
                              widget.subtitle!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 13,
                                color: const Color(0xFFFF5864),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ── 球（點擊位置出現）────────────────────────────────
                    if (_ballCtrl.value > 0)
                      Positioned(
                        left: _ballPos.dx - 14,
                        top:  _ballPos.dy - 14,
                        child: Transform.scale(
                          scale: _ballCtrl.status == AnimationStatus.forward
                              ? Curves.elasticOut.transform(
                                  _ballCtrl.value.clamp(0.0, 1.0))
                              : 1.0,
                          child: Opacity(
                            opacity: _ballCtrl.value,
                            child: CustomPaint(
                              size: const Size(28, 28),
                              painter:
                                  _BallPainter(color: CatColorScheme.pink.ball),
                            ),
                          ),
                        ),
                      ),

                    // ── 貓咪（可在畫面上移動）────────────────────────────
                    Positioned(
                      left: currentPos.dx - 110,
                      top:  currentPos.dy - 80,
                      child: CustomPaint(
                        size: const Size(220, 160),
                        painter: RunningCatPainter(
                          t:           _runCtrl.value,
                          colors:      CatColorScheme.pink,
                          isHappy:     isHappy,
                          facingLeft:  _facingLeft,
                          exciteLevel: exciteLevel,
                        ),
                      ),
                    ),

                    // ── 跳動三點（固定底部偏上）──────────────────────────
                    Positioned(
                      bottom: _hasInteracted ? 48 : 68,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: BouncingDots(t: _runCtrl.value),
                      ),
                    ),

                    // ── 引導提示（首次顯示，互動後隱藏）─────────────────
                    if (!_hasInteracted)
                      Positioned(
                        bottom: 28,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Opacity(
                            opacity: hintAlpha,
                            child: Text(
                              '點畫面丟球，陪貓咪玩 🐾',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 12,
                                color: const Color(0xFFFD297B),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ─── 跳動三點 ─────────────────────────────────────────────────────────────────

class BouncingDots extends StatelessWidget {
  final double t;
  final CatColorScheme colors;
  const BouncingDots({required this.t, this.colors = CatColorScheme.pink});

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
                color: colors.body
                    .withValues(alpha: 0.6 + 0.4 * sin(phase * pi)),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── 球 CustomPainter ─────────────────────────────────────────────────────────

class _BallPainter extends CustomPainter {
  final Color color;
  const _BallPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r      = size.width / 2;

    // 球體（徑向漸層，左上偏亮）
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          Color.lerp(color, Colors.white, 0.35)!,
          color,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, paint);

    // 光澤高光（右上角小白圓）
    canvas.drawCircle(
      Offset(center.dx + r * 0.27, center.dy - r * 0.32),
      r * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.70),
    );
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.color != color;
}

// ─── 奔跑貓咪 CustomPainter ────────────────────────────────────────────────────

class RunningCatPainter extends CustomPainter {
  final double t;          // 0.0 → 1.0，動畫進度
  final CatColorScheme colors;
  final bool isHappy;      // 開心表情（彎月眼）
  final bool facingLeft;   // 翻轉水平方向
  final double exciteLevel; // 0.0~1.0，尾巴激動程度

  const RunningCatPainter({
    required this.t,
    this.colors      = CatColorScheme.pink,
    this.isHappy     = false,
    this.facingLeft  = false,
    this.exciteLevel = 0.0,
  });

  // ── 畫筆 ──────────────────────────────────────────────────────────────────

  Paint get _fill => Paint()
    ..color = colors.body
    ..style = PaintingStyle.fill;

  Paint get _light => Paint()
    ..color = colors.light
    ..style = PaintingStyle.fill;

  Paint get _stroke => Paint()
    ..color = colors.body
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..strokeCap = StrokeCap.round;

  // ── 動畫數值計算 ──────────────────────────────────────────────────────────

  double _cycle(double offset) => sin((t + offset) * 2 * pi);

  @override
  void paint(Canvas canvas, Size size) {
    final cx          = size.width * 0.48;
    final cy          = size.height * 0.52;
    final bodyBounce  = _cycle(0) * 3.5;

    canvas.save();
    canvas.translate(cx, cy + bodyBounce);
    // 翻轉方向（往左跑）
    if (facingLeft) canvas.scale(-1.0, 1.0);

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
      ..color = colors.body.withValues(alpha: 0.12)
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
    // exciteLevel 增大時尾巴搖擺幅度加大（18° → 30°）
    final amplitude = 18.0 + exciteLevel * 12.0;
    final wag       = _cycle(0.25) * amplitude * (pi / 180);

    canvas.save();
    canvas.translate(-38.0, -4.0);
    canvas.rotate(wag);

    final path = Path()
      ..moveTo(0, 0)
      ..cubicTo(-8, -18, -4, -36, 6, -44);

    canvas.drawPath(path, _stroke..strokeWidth = 4.5);
    canvas.drawCircle(const Offset(6, -44), 5.5, _fill);

    canvas.restore();
  }

  // ── 四條腿 ────────────────────────────────────────────────────────────────

  void _drawLegs(Canvas canvas) {
    final frontSwing = _cycle(0)   * 22 * (pi / 180);
    final backSwing  = _cycle(0.5) * 22 * (pi / 180);

    _drawLeg(canvas, x:  18.0, y: 14.0, angle:  frontSwing, len: 24.0);
    _drawLeg(canvas, x: -22.0, y: 14.0, angle:  backSwing,  len: 24.0);
    _drawLeg(canvas, x:  10.0, y: 14.0, angle: -frontSwing, len: 24.0,
        alpha: 0.55);
    _drawLeg(canvas, x: -14.0, y: 14.0, angle: -backSwing,  len: 24.0,
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
      ..color = colors.body.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);

    final thigh = RRect.fromRectAndRadius(
      Rect.fromLTWH(-3.5, 0, 7, 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(thigh, paint);

    canvas.save();
    canvas.translate(0, 12);
    canvas.rotate(-angle * 0.6);
    final shin = RRect.fromRectAndRadius(
      Rect.fromLTWH(-3, 0, 6, len - 12),
      const Radius.circular(3),
    );
    canvas.drawRRect(shin, paint);
    canvas.drawOval(Rect.fromLTWH(-5, len - 14, 10, 5), paint);
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
    canvas.drawOval(
      const Rect.fromLTWH(-20, -8, 36, 20),
      _light..color = colors.light.withValues(alpha: 0.30),
    );
  }

  // ── 頭部 + 耳朵 + 臉 ──────────────────────────────────────────────────────

  void _drawHead(Canvas canvas) {
    const hx = 38.0;
    const hy = -24.0;

    _drawEar(canvas, hx - 13, hy - 18, flip: false);
    _drawEar(canvas, hx + 13, hy - 18, flip: true);

    canvas.drawCircle(Offset(hx, hy), 22, _fill);

    // ── 眼睛（普通 or 開心彎月）──
    if (!isHappy) {
      // 眼白
      final eyePaint = Paint()..color = colors.bg..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(hx + 7,  hy - 4), 5.5, eyePaint);
      canvas.drawCircle(Offset(hx - 3,  hy - 4), 5.5, eyePaint);

      // 瞳孔（眨眼：最後 8% 閉眼）
      if (t % 1.0 > 0.92) {
        canvas.drawLine(Offset(hx + 3,  hy - 4), Offset(hx + 11, hy - 4),
            _stroke..strokeWidth = 2.5);
        canvas.drawLine(Offset(hx - 7,  hy - 4), Offset(hx + 1,  hy - 4),
            _stroke..strokeWidth = 2.5);
      } else {
        canvas.drawCircle(Offset(hx + 8,  hy - 4), 3.0, _fill);
        canvas.drawCircle(Offset(hx - 2,  hy - 4), 3.0, _fill);
      }
    } else {
      // 開心彎月眼（^ 弧形）
      final arcPaint = Paint()
        ..color = colors.bg
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(center: Offset(hx + 7, hy - 2), width: 14, height: 9),
        pi, -pi, false, arcPaint,
      );
      canvas.drawArc(
        Rect.fromCenter(center: Offset(hx - 3, hy - 2), width: 14, height: 9),
        pi, -pi, false, arcPaint,
      );
    }

    // ── 鼻子 ──
    final nosePath = Path()
      ..moveTo(hx + 4,  hy + 4)
      ..lineTo(hx + 7,  hy + 8)
      ..lineTo(hx + 1,  hy + 8)
      ..close();
    canvas.drawPath(nosePath, Paint()..color = colors.accent);

    // ── 嘴巴 ──
    final mouthPath = Path()
      ..moveTo(hx + 4,  hy + 8)
      ..quadraticBezierTo(hx + 2,  hy + 12, hx - 1, hy + 11)
      ..moveTo(hx + 4,  hy + 8)
      ..quadraticBezierTo(hx + 6,  hy + 12, hx + 9, hy + 11);
    canvas.drawPath(mouthPath, _stroke..strokeWidth = 1.8);

    _drawWhiskers(canvas, hx, hy);
  }

  void _drawEar(Canvas canvas, double x, double y, {required bool flip}) {
    final dir = flip ? 1.0 : -1.0;

    final ear = Path()
      ..moveTo(x,             y + 12)
      ..lineTo(x + dir * 10,  y - 6)
      ..lineTo(x + dir * 20,  y + 12)
      ..close();
    canvas.drawPath(ear, _fill);

    final inner = Path()
      ..moveTo(x + dir * 4,   y + 10)
      ..lineTo(x + dir * 10,  y - 1)
      ..lineTo(x + dir * 16,  y + 10)
      ..close();
    canvas.drawPath(inner, _light);
  }

  void _drawWhiskers(Canvas canvas, double hx, double hy) {
    final wPaint = Paint()
      ..color = colors.light
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(hx - 5, hy + 6), Offset(hx - 22, hy + 4),  wPaint);
    canvas.drawLine(Offset(hx - 5, hy + 8), Offset(hx - 22, hy + 10), wPaint);
    canvas.drawLine(Offset(hx + 8, hy + 6), Offset(hx + 22, hy + 4),  wPaint);
    canvas.drawLine(Offset(hx + 8, hy + 8), Offset(hx + 22, hy + 10), wPaint);
  }

  @override
  bool shouldRepaint(RunningCatPainter old) =>
      old.t != t ||
      old.colors != colors ||
      old.isHappy != isHappy ||
      old.facingLeft != facingLeft ||
      old.exciteLevel != exciteLevel;
}

// ─── 貓咪配色方案 ──────────────────────────────────────────────────────────────

@immutable
class CatColorScheme {
  final Color body;   // 貓身、腿、尾巴主色
  final Color light;  // 耳內、肚子亮部
  final Color bg;     // 眼白色（與背景協調）
  final Color accent; // 鼻子點睛色
  final Color ball;   // 丟出去的球的顏色

  const CatColorScheme({
    required this.body,
    required this.light,
    required this.bg,
    Color? accent,
    Color? ball,
  })  : accent = accent ?? light,
        ball   = ball   ?? const Color(0xFFFF9800);

  /// 標準粉紅品牌色（CatLoadingWidget 預設）
  static const pink = CatColorScheme(
    body:   Color(0xFFFD297B), // 品牌珊瑚粉
    light:  Color(0xFFFFB3C6), // 淡粉紅
    bg:     Color(0xFFFFF0F3), // 極淡玫瑰白
    ball:   Color(0xFFFF9800), // 橙色球（對比粉紅貓 + 淡玫瑰背景）
  );

  /// Pro 香檳金（ProCustomLoadingWidget 使用）
  static const proChampagne = CatColorScheme(
    body:   Color(0xFFB8860D), // 深古銅金
    light:  Color(0xFFDEBC70), // 香檳色亮部
    bg:     Color(0xFFFAFAF8), // 近白
    accent: Color(0xFFFD297B), // 品牌珊瑚粉鼻子
    ball:   Color(0xFFFD297B), // 珊瑚粉球（對比金色貓 + 米白背景）
  );
}
