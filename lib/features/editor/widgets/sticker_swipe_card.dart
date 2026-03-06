import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 外部控制器，可程式化觸發右滑（保留）或左滑（跳過）
class StickerSwipeCardController {
  _StickerSwipeCardState? _state;

  void accept() => _state?.triggerAccept();
  void reject() => _state?.triggerReject();
}

/// Tinder 風格滑動卡片
///
/// - 右滑 / 點擊保留按鈕 → [onAccepted]（保留 ❤️）
/// - 左滑 / 點擊跳過按鈕 → [onRejected]（跳過 ✕）
/// - 未達閾值 → 彈回中央
class StickerSwipeCard extends StatefulWidget {
  final Widget child;
  final StickerSwipeCardController? controller;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;

  const StickerSwipeCard({
    super.key,
    required this.child,
    this.controller,
    required this.onAccepted,
    required this.onRejected,
  });

  @override
  State<StickerSwipeCard> createState() => _StickerSwipeCardState();
}

class _StickerSwipeCardState extends State<StickerSwipeCard>
    with SingleTickerProviderStateMixin {
  Offset _offset = Offset.zero;
  late final AnimationController _ctrl;
  late Animation<Offset> _anim;

  /// 觸發判定閾值（px）
  static const _kThreshold = 100.0;

  /// 飛出距離
  static const _kFlyDist = 700.0;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _anim = AlwaysStoppedAnimation(Offset.zero);
    _ctrl.addListener(() => setState(() => _offset = _anim.value));
  }

  @override
  void didUpdateWidget(StickerSwipeCard old) {
    super.didUpdateWidget(old);
    old.controller?._state = null;
    widget.controller?._state = this;
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _ctrl.dispose();
    super.dispose();
  }

  // ─── Gesture callbacks ────────────────────────────────────────────

  void _onDragUpdate(DragUpdateDetails d) {
    if (_ctrl.isAnimating) return;
    setState(() => _offset += Offset(d.delta.dx, 0));
  }

  void _onDragEnd(DragEndDetails d) {
    if (_offset.dx >= _kThreshold) {
      _flyOff(rightward: true, onDone: widget.onAccepted);
    } else if (_offset.dx <= -_kThreshold) {
      _flyOff(rightward: false, onDone: widget.onRejected);
    } else {
      _snapBack();
    }
  }

  // ─── Animations ───────────────────────────────────────────────────

  void _flyOff({required bool rightward, required VoidCallback onDone}) {
    HapticFeedback.mediumImpact();
    final target = Offset(
      rightward ? _kFlyDist : -_kFlyDist,
      _offset.dy + 80,
    );
    _anim = Tween(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _ctrl.reset();
    _ctrl.forward().then((_) {
      if (mounted) {
        setState(() => _offset = Offset.zero);
        onDone();
      }
    });
  }

  void _snapBack() {
    _anim = Tween(begin: _offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut),
    );
    _ctrl.reset();
    _ctrl.forward();
  }

  /// 外部觸發（按鈕點擊）
  void triggerAccept() => _flyOff(rightward: true, onDone: widget.onAccepted);
  void triggerReject() =>
      _flyOff(rightward: false, onDone: widget.onRejected);

  double get _swipeProgress =>
      (_offset.dx / _kThreshold).clamp(-1.0, 1.0);

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final progress = _swipeProgress;
    final angle = _offset.dx * 0.0012; // 微幅傾斜

    // 用 SizedBox.expand 讓手勢區域填滿父層（Expanded）的全部空間
    return SizedBox.expand(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // 空白處也觸發
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Center(
          child: Transform(
            transform: Matrix4.identity()
              ..translate(_offset.dx, _offset.dy)
              ..rotateZ(angle),
            alignment: FractionalOffset.bottomCenter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                widget.child,
                // 右滑：保留徽章
                if (progress > 0.15)
                  _SwipeBadge(
                    label: '保留',
                    icon: Icons.favorite_rounded,
                    color: Colors.green.shade400,
                    opacity: progress,
                    isLeft: true,
                  ),
                // 左滑：跳過徽章
                if (progress < -0.15)
                  _SwipeBadge(
                    label: '跳過',
                    icon: Icons.close_rounded,
                    color: Colors.red.shade400,
                    opacity: -progress,
                    isLeft: false,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 徽章 ─────────────────────────────────────────────────────────────────

class _SwipeBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double opacity;
  final bool isLeft;

  const _SwipeBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.opacity,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      left: isLeft ? 20 : null,
      right: isLeft ? null : 20,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: isLeft ? -0.25 : 0.25,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 3),
              color: color.withOpacity(0.12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
