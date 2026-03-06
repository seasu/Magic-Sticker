# Animation Recipes — Flutter Tinder-Style UI

Copy-paste animation patterns for common Tinder-style interactions.

## Table of Contents
1. [Card Swipe Spring Physics](#card-swipe-spring-physics)
2. [Match Celebration Sequence](#match-celebration-sequence)
3. [Button Press Scale](#button-press-scale)
4. [Heart Pulse](#heart-pulse)
5. [Staggered List Entry](#staggered-list-entry)
6. [Typing Indicator Dots](#typing-indicator-dots)
7. [Page Transition (Slide Up)](#page-transition-slide-up)
8. [Gradient Shimmer Text](#gradient-shimmer-text)
9. [Confetti Burst](#confetti-burst)
10. [Notification Badge Pop](#notification-badge-pop)

---

## Card Swipe Spring Physics

Natural spring-back when the user releases a card below the swipe threshold.

```dart
import 'package:flutter/physics.dart';

// Inside your StatefulWidget with SingleTickerProviderStateMixin:

void _springBack() {
  final spring = SpringDescription(
    mass: 1.0,
    stiffness: 500.0,  // Higher = snappier return
    damping: 25.0,     // Higher = less oscillation
  );

  // For X axis
  _xSimulation = SpringSimulation(spring, _dragOffset.dx, 0, _velocity.dx);
  // For Y axis
  _ySimulation = SpringSimulation(spring, _dragOffset.dy, 0, _velocity.dy);

  _controller.animateWith(_xSimulation!);
}

// In a Ticker callback or AnimationController listener:
void _onTick(Duration elapsed) {
  if (_xSimulation != null) {
    final t = elapsed.inMilliseconds / 1000.0;
    setState(() {
      _dragOffset = Offset(
        _xSimulation!.x(t),
        _ySimulation!.x(t),
      );
    });
    if (_xSimulation!.isDone(t) && _ySimulation!.isDone(t)) {
      _dragOffset = Offset.zero;
    }
  }
}
```

### Swipe-Away Animation

When the card should fly off screen:

```dart
void _animateSwipeAway(SwipeDirection direction) {
  final screenWidth = MediaQuery.of(context).size.width;
  final screenHeight = MediaQuery.of(context).size.height;

  final Offset target = switch (direction) {
    SwipeDirection.right => Offset(screenWidth * 1.5, _dragOffset.dy * 0.5),
    SwipeDirection.left => Offset(-screenWidth * 1.5, _dragOffset.dy * 0.5),
    SwipeDirection.up => Offset(_dragOffset.dx * 0.3, -screenHeight * 1.2),
  };

  _animation = Tween<Offset>(
    begin: _dragOffset,
    end: target,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInQuad, // Accelerate out — feels like a flick
  ));

  _controller.duration = const Duration(milliseconds: 250);
  _controller.forward(from: 0).then((_) {
    // Notify parent, remove card from stack
    widget.onSwiped(direction);
    _resetCard();
  });
}
```

---

## Match Celebration Sequence

Multi-phase animation: blur in → title scale → avatars slide → buttons fade.

```dart
class MatchAnimationController {
  late AnimationController mainController;
  late Animation<double> backdropOpacity;
  late Animation<double> titleScale;
  late Animation<Offset> leftAvatarPosition;
  late Animation<Offset> rightAvatarPosition;
  late Animation<double> buttonsFadeIn;

  void init(TickerProvider vsync) {
    mainController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1400),
    );

    backdropOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: mainController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );

    titleScale = Tween(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: mainController,
        curve: const Interval(0.15, 0.5, curve: Curves.easeOutBack),
      ),
    );

    leftAvatarPosition = Tween(
      begin: const Offset(-100, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: mainController,
      curve: const Interval(0.3, 0.65, curve: Curves.easeOutCubic),
    ));

    rightAvatarPosition = Tween(
      begin: const Offset(100, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: mainController,
      curve: const Interval(0.3, 0.65, curve: Curves.easeOutCubic),
    ));

    buttonsFadeIn = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: mainController,
        curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
      ),
    );
  }

  void play() => mainController.forward();
  void dispose() => mainController.dispose();
}
```

---

## Button Press Scale

Satisfying tap feedback with scale + haptics.

```dart
/// Mixin for any tappable widget that needs press animation
mixin PressAnimationMixin<T extends StatefulWidget> on State<T>,
    SingleTickerProviderStateMixin<T> {
  late AnimationController pressController;
  late Animation<double> pressScale;

  void initPressAnimation({double scaleDown = 0.92}) {
    pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    pressScale = Tween(begin: 1.0, end: scaleDown).animate(
      CurvedAnimation(parent: pressController, curve: Curves.easeInOut),
    );
  }

  void onPressDown() => pressController.forward();
  void onPressUp() {
    pressController.reverse();
    HapticFeedback.selectionClick();
  }
  void onPressCancel() => pressController.reverse();

  @override
  void dispose() {
    pressController.dispose();
    super.dispose();
  }
}

// Usage:
// Wrap your widget content in:
// ScaleTransition(scale: pressScale, child: ...)
```

---

## Heart Pulse

Looping pulse animation for match indicators or like buttons.

```dart
class PulsingHeart extends StatefulWidget {
  final double size;
  final Color color;

  const PulsingHeart({
    super.key,
    this.size = 48,
    this.color = const Color(0xFFFF5864),
  });

  @override
  State<PulsingHeart> createState() => _PulsingHeartState();
}

class _PulsingHeartState extends State<PulsingHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scale = Tween(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacity = Tween(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Icon(
            Icons.favorite,
            size: widget.size,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}
```

---

## Staggered List Entry

Items slide up and fade in with staggered delays — used for match lists, chat lists.

```dart
class StaggeredListItem extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration totalDuration;
  final Duration itemDelay;

  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
    this.totalDuration = const Duration(milliseconds: 600),
    this.itemDelay = const Duration(milliseconds: 80),
  });

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.totalDuration,
    );

    final delayRatio = (widget.index * widget.itemDelay.inMilliseconds) /
        (widget.totalDuration.inMilliseconds + widget.index * widget.itemDelay.inMilliseconds);
    final interval = Interval(
      delayRatio.clamp(0.0, 0.7),
      1.0,
      curve: Curves.easeOutCubic,
    );

    _opacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: interval),
    );
    _slide = Tween(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: interval),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

// Usage in a ListView:
// ListView.builder(
//   itemBuilder: (context, index) => StaggeredListItem(
//     index: index,
//     child: MatchTile(match: matches[index]),
//   ),
// )
```

---

## Typing Indicator Dots

Three bouncing dots with staggered timing for chat typing state.

```dart
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      Future.delayed(Duration(milliseconds: i * 180), () {
        if (mounted) controller.repeat(reverse: true);
      });
      return controller;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _controllers[i],
            builder: (_, __) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                child: Transform.translate(
                  offset: Offset(0, -4 * _controllers[i].value),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withOpacity(
                        0.4 + 0.4 * _controllers[i].value,
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
```

---

## Page Transition (Slide Up)

Custom route transition for navigating to profile detail.

```dart
class SlideUpRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SlideUpRoute({required this.page})
      : super(
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            return SlideTransition(
              position: Tween(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: FadeTransition(
                opacity: Tween(begin: 0.5, end: 1.0).animate(curvedAnimation),
                child: child,
              ),
            );
          },
        );
}

// Usage:
// Navigator.push(context, SlideUpRoute(page: ProfileDetailScreen()));
```

---

## Gradient Shimmer Text

Animated gradient sweep across text — used for "It's a Match!" or premium badges.

```dart
class GradientShimmerText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const GradientShimmerText({
    super.key,
    required this.text,
    required this.style,
  });

  @override
  State<GradientShimmerText> createState() => _GradientShimmerTextState();
}

class _GradientShimmerTextState extends State<GradientShimmerText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1 + 3 * _controller.value, 0),
              end: Alignment(3 * _controller.value, 0),
              colors: const [
                Color(0xFFFD297B),
                Color(0xFFFF5864),
                Color(0xFFFFD700),
                Color(0xFFFF5864),
                Color(0xFFFD297B),
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
            ).createShader(bounds);
          },
          child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
        );
      },
    );
  }
}
```

---

## Notification Badge Pop

Badge that pops in when count changes — for unread messages.

```dart
class BadgePop extends StatefulWidget {
  final int count;
  final Widget child;

  const BadgePop({super.key, required this.count, required this.child});

  @override
  State<BadgePop> createState() => _BadgePopState();
}

class _BadgePopState extends State<BadgePop>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scale = TweenSequence([
      TweenSequenceItem(Tween(begin: 0.0, end: 1.3), 60),
      TweenSequenceItem(Tween(begin: 1.3, end: 0.9), 20),
      TweenSequenceItem(Tween(begin: 0.9, end: 1.0), 20),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant BadgePop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != oldWidget.count && widget.count > 0) {
      _controller.forward(from: 0);
      HapticFeedback.selectionClick();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (widget.count > 0)
          Positioned(
            right: -6,
            top: -6,
            child: ScaleTransition(
              scale: _scale,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: AppColors.nope,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  '${widget.count}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```
