import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cat_loading_widget.dart';

// ─── Pro 香檳金色系常數 ─────────────────────────────────────────────────────────
const _kProTitle    = Color(0xFF7B5215);
const _kProCardBg   = Color(0xFFC9A84C);
const _kProCardText = Color(0xFF7B5215);
const _kProSubtitle = Color(0xFFA07828);

// ─── 互動狀態機 ───────────────────────────────────────────────────────────────
enum _ProCatState { idle, chasing, playing }

/// 全畫面 Loading 動畫：Pro 客製情緒 / 全客製模式專用
///
/// 香檳金漸層背景 + 奔跑金色貓咪，支援點擊畫面「丟球」互動。
class ProCustomLoadingWidget extends StatefulWidget {
  final String? emotionDesc;
  final String? styleDesc;

  const ProCustomLoadingWidget({
    super.key,
    this.emotionDesc,
    this.styleDesc,
  });

  @override
  State<ProCustomLoadingWidget> createState() => _ProCustomLoadingWidgetState();
}

class _ProCustomLoadingWidgetState extends State<ProCustomLoadingWidget>
    with TickerProviderStateMixin {
  // ── 動畫控制器 ────────────────────────────────────────────────────────────
  late final AnimationController _runCtrl;
  late final AnimationController _moveCtrl;
  late final AnimationController _playCtrl;
  late final AnimationController _ballCtrl;

  // ── 狀態機 ───────────────────────────────────────────────────────────────
  _ProCatState _catState = _ProCatState.idle;
  Offset? _catPos;
  Offset _catMoveStart = Offset.zero;
  Offset _catTarget    = Offset.zero;
  Offset _ballPos      = Offset.zero;
  bool _facingLeft     = false;
  bool _hasInteracted  = false;
  Size _stackSize      = Size.zero;
  int  _generation     = 0;

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
    if (_catState == _ProCatState.idle) return _catPos!;
    if (_catState == _ProCatState.chasing) {
      final t = Curves.easeInOut.transform(_moveCtrl.value);
      return Offset.lerp(_catMoveStart, _catTarget, t)!;
    }
    return _catTarget;
  }

  // ── 使用者點擊「丟球」──────────────────────────────────────────────────────
  void _throwBall(Offset tapPos) {
    if (!mounted || _catPos == null) return;
    HapticFeedback.lightImpact();

    final clampedTarget = Offset(
      tapPos.dx.clamp(60.0, _stackSize.width  - 60.0),
      tapPos.dy.clamp(140.0, _stackSize.height - 160.0),
    );

    _moveCtrl.stop();
    _playCtrl.stop();

    final fromPos  = _currentCatPos;
    final thisGen  = ++_generation;

    setState(() {
      _hasInteracted = true;
      _catMoveStart  = fromPos;
      _catTarget     = clampedTarget;
      _ballPos       = clampedTarget;
      _facingLeft    = clampedTarget.dx < fromPos.dx;
      _catState      = _ProCatState.chasing;
    });

    _ballCtrl.forward(from: 0);

    _moveCtrl.forward(from: 0).then((_) {
      if (!mounted || _generation != thisGen) return;
      setState(() {
        _catPos   = _catTarget;
        _catState = _ProCatState.playing;
      });
      _playCtrl.forward(from: 0);

      Future.delayed(const Duration(milliseconds: 2000), () {
        if (!mounted || _generation != thisGen) return;
        _ballCtrl.reverse();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted || _generation != thisGen) return;
          setState(() => _catState = _ProCatState.idle);
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final desc  = widget.emotionDesc ?? widget.styleDesc;
    final title = widget.emotionDesc != null
        ? 'AI 正在詮釋您的專屬情緒'
        : 'AI 正在生成您的專屬貼圖';

    return LayoutBuilder(
      builder: (context, constraints) {
        _stackSize = Size(constraints.maxWidth, constraints.maxHeight);
        _catPos ??= Offset(
          constraints.maxWidth  / 2,
          constraints.maxHeight * 0.48,
        );

        return GestureDetector(
          onTapDown: (d) => _throwBall(d.localPosition),
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFAFAF5), Color(0xFFF5EDD8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: AnimatedBuilder(
              animation: Listenable.merge(
                  [_runCtrl, _moveCtrl, _playCtrl, _ballCtrl]),
              builder: (context, _) {
                final currentPos  = _currentCatPos;
                final isHappy     = _catState == _ProCatState.playing &&
                    _playCtrl.value > 0.2;
                final exciteLevel = _catState == _ProCatState.playing
                    ? _playCtrl.value
                    : 0.0;
                final hintAlpha   = (sin(_runCtrl.value * 2 * pi) * 0.15 + 0.55)
                    .clamp(0.40, 0.70);

                return Stack(
                  children: [

                    // ── 貓咪（最底層，文字蓋在上面）────────────────────
                    Positioned(
                      left: currentPos.dx - 110,
                      top:  currentPos.dy - 80,
                      child: CustomPaint(
                        size: const Size(220, 160),
                        painter: RunningCatPainter(
                          t:           _runCtrl.value,
                          colors:      CatColorScheme.proChampagne,
                          isHappy:     isHappy,
                          facingLeft:  _facingLeft,
                          exciteLevel: exciteLevel,
                        ),
                      ),
                    ),

                    // ── 球（點擊位置）────────────────────────────────────
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
                              painter: _BallPainter(
                                  color: CatColorScheme.proChampagne.ball),
                            ),
                          ),
                        ),
                      ),

                    // ── 主標（固定頂部）──────────────────────────────────
                    Positioned(
                      top: 48,
                      left: 0,
                      right: 0,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _kProTitle,
                        ),
                      ),
                    ),

                    // ── 底部區域（跳動點 + 描述卡 + 小字 + 提示）────────
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 跳動三點
                          BouncingDots(
                            t: _runCtrl.value,
                            colors: CatColorScheme.proChampagne,
                          ),
                          const SizedBox(height: 16),

                          // 描述卡
                          if (desc != null)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 40),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: _kProCardBg.withValues(alpha: 0.20),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _kProCardBg,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                '「$desc」',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: _kProCardText,
                                ),
                              ),
                            ),
                          if (desc != null) const SizedBox(height: 12),

                          // 時間估算
                          Text(
                            '正在創作 · 約 15~25 秒',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              color: _kProSubtitle,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // 引導提示（首次顯示）
                          if (!_hasInteracted)
                            Opacity(
                              opacity: hintAlpha,
                              child: Text(
                                '點畫面丟球，陪貓咪玩 🐾',
                                style: GoogleFonts.notoSansTc(
                                  fontSize: 12,
                                  color: _kProTitle.withValues(alpha: 0.80),
                                ),
                              ),
                            ),
                          const SizedBox(height: 28),
                        ],
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

// ─── 球 CustomPainter（從 cat_loading_widget.dart 複用相同邏輯）──────────────────

class _BallPainter extends CustomPainter {
  final Color color;
  const _BallPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r      = size.width / 2;

    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          Color.lerp(color, Colors.white, 0.35)!,
          color,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, paint);

    canvas.drawCircle(
      Offset(center.dx + r * 0.27, center.dy - r * 0.32),
      r * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.70),
    );
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.color != color;
}
