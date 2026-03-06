# Component Reference — Flutter Tinder-Style UI

This file contains production-ready component implementations. Copy and adapt for your project.

## Table of Contents
1. [Swipe Card Stack](#swipe-card-stack)
2. [Action Button Row](#action-button-row)
3. [Profile Card](#profile-card)
4. [Match Overlay](#match-overlay)
5. [Chat Bubble](#chat-bubble)
6. [Bottom Navigation](#bottom-navigation)
7. [Gradient Button](#gradient-button)
8. [Interest Chip](#interest-chip)
9. [Photo Carousel](#photo-carousel)
10. [Shimmer Loading Card](#shimmer-loading-card)

---

## Swipe Card Stack

The core interaction. Uses a Stack with Transform to create the card pile effect and gesture-driven swiping.

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeCardStack extends StatefulWidget {
  final List<ProfileData> profiles;
  final void Function(ProfileData profile, SwipeDirection direction) onSwiped;

  const SwipeCardStack({
    super.key,
    required this.profiles,
    required this.onSwiped,
  });

  @override
  State<SwipeCardStack> createState() => _SwipeCardStackState();
}

enum SwipeDirection { left, right, up }

class _SwipeCardStackState extends State<SwipeCardStack>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  late AnimationController _controller;
  late Animation<Offset> _animation;
  bool _isDragging = false;

  static const _swipeThreshold = 120.0;
  static const _rotationFactor = 0.0012;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        setState(() => _dragOffset = _animation.value);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    _isDragging = true;
    _controller.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _isDragging = false;
    final dx = _dragOffset.dx;
    final dy = _dragOffset.dy;

    if (dx.abs() > _swipeThreshold) {
      _animateOffScreen(dx > 0 ? SwipeDirection.right : SwipeDirection.left);
    } else if (dy < -_swipeThreshold) {
      _animateOffScreen(SwipeDirection.up);
    } else {
      _springBack();
    }
  }

  void _animateOffScreen(SwipeDirection direction) {
    HapticFeedback.mediumImpact();
    final target = switch (direction) {
      SwipeDirection.right => Offset(MediaQuery.of(context).size.width * 1.5, _dragOffset.dy),
      SwipeDirection.left => Offset(-MediaQuery.of(context).size.width * 1.5, _dragOffset.dy),
      SwipeDirection.up => Offset(_dragOffset.dx, -MediaQuery.of(context).size.height),
    };
    _animation = Tween<Offset>(begin: _dragOffset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward(from: 0).then((_) {
      widget.onSwiped(widget.profiles.first, direction);
      setState(() => _dragOffset = Offset.zero);
      _controller.reset();
    });
  }

  void _springBack() {
    _animation = Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = widget.profiles;
    if (profiles.isEmpty) return const _EmptyState();

    return Stack(
      alignment: Alignment.center,
      children: [
        // Background cards (show up to 2 behind)
        for (int i = (profiles.length - 1).clamp(0, 2); i > 0; i--)
          _buildBackCard(i),

        // Top card (draggable)
        GestureDetector(
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Transform(
            transform: Matrix4.identity()
              ..translate(_dragOffset.dx, _dragOffset.dy)
              ..rotateZ(_dragOffset.dx * _rotationFactor),
            alignment: Alignment.center,
            child: Stack(
              children: [
                ProfileCard(profile: profiles.first),
                // LIKE overlay
                Positioned.fill(
                  child: _SwipeOverlay(
                    label: 'LIKE',
                    color: AppColors.like,
                    opacity: (_dragOffset.dx / 150).clamp(0, 1),
                    alignment: Alignment.topLeft,
                  ),
                ),
                // NOPE overlay
                Positioned.fill(
                  child: _SwipeOverlay(
                    label: 'NOPE',
                    color: AppColors.nope,
                    opacity: (-_dragOffset.dx / 150).clamp(0, 1),
                    alignment: Alignment.topRight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackCard(int index) {
    final scale = 1.0 - (index * 0.05) + (_dragOffset.dx.abs() / 5000);
    final yOffset = index * 10.0 - (_dragOffset.dx.abs() / 20);
    return Transform(
      transform: Matrix4.identity()
        ..translate(0.0, yOffset.clamp(0, 20))
        ..scale(scale.clamp(0.9, 1.0)),
      alignment: Alignment.center,
      child: ProfileCard(profile: widget.profiles[index]),
    );
  }
}

class _SwipeOverlay extends StatelessWidget {
  final String label;
  final Color color;
  final double opacity;
  final Alignment alignment;

  const _SwipeOverlay({
    required this.label,
    required this.color,
    required this.opacity,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Opacity(
          opacity: opacity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.explore_outlined, size: 80, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(
            "You've seen everyone nearby",
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for new people',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Action Button Row

Five circular action buttons with icons and scale animation on tap.

```dart
class ActionButtonRow extends StatelessWidget {
  final VoidCallback onRewind;
  final VoidCallback onNope;
  final VoidCallback onSuperLike;
  final VoidCallback onLike;
  final VoidCallback onBoost;

  const ActionButtonRow({
    super.key,
    required this.onRewind,
    required this.onNope,
    required this.onSuperLike,
    required this.onLike,
    required this.onBoost,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.replay_rounded,
            color: AppColors.gold,
            size: 44,
            onTap: onRewind,
          ),
          _ActionButton(
            icon: Icons.close_rounded,
            color: AppColors.nope,
            size: 56,
            onTap: onNope,
          ),
          _ActionButton(
            icon: Icons.star_rounded,
            color: AppColors.superLike,
            size: 44,
            onTap: onSuperLike,
          ),
          _ActionButton(
            icon: Icons.favorite_rounded,
            color: AppColors.like,
            size: 56,
            onTap: onLike,
          ),
          _ActionButton(
            icon: Icons.bolt_rounded,
            color: AppColors.boost,
            size: 44,
            onTap: onBoost,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween(begin: 1.0, end: 0.85).animate(
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
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: widget.color.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: widget.color.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            color: widget.color,
            size: widget.size * 0.5,
          ),
        ),
      ),
    );
  }
}
```

---

## Profile Card

The main display card used in the swipe stack.

```dart
class ProfileCard extends StatelessWidget {
  final ProfileData profile;

  const ProfileCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        boxShadow: AppSpacing.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            Image.network(
              profile.photoUrl,
              fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const ShimmerBox();
              },
            ),

            // Bottom gradient overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
                    ],
                  ),
                ),
              ),
            ),

            // Info overlay
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${profile.name}, ${profile.age}',
                          style: AppTypography.cardName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (profile.isVerified) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.verified,
                          color: Color(0xFF1DA1F2),
                          size: 22,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (profile.jobTitle != null)
                    Text(
                      profile.jobTitle!,
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                  if (profile.distance != null)
                    Text(
                      '${profile.distance} km away',
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                ],
              ),
            ),

            // Photo page indicator (top)
            if (profile.photoUrls.length > 1)
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: _PhotoIndicator(
                  count: profile.photoUrls.length,
                  currentIndex: 0, // bind to PageController
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PhotoIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _PhotoIndicator({
    required this.count,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        return Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: i == currentIndex
                  ? Colors.white
                  : Colors.white.withOpacity(0.4),
            ),
          ),
        );
      }),
    );
  }
}
```

---

## Match Overlay

Full-screen overlay shown when two users match.

```dart
class MatchOverlay extends StatefulWidget {
  final ProfileData currentUser;
  final ProfileData matchedUser;
  final VoidCallback onSendMessage;
  final VoidCallback onKeepSwiping;

  const MatchOverlay({
    super.key,
    required this.currentUser,
    required this.matchedUser,
    required this.onSendMessage,
    required this.onKeepSwiping,
  });

  @override
  State<MatchOverlay> createState() => _MatchOverlayState();
}

class _MatchOverlayState extends State<MatchOverlay>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late Animation<double> _titleScale;
  late Animation<double> _avatarSlide;
  late Animation<double> _buttonsOpacity;

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _titleScale = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
      ),
    );
    _avatarSlide = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.2, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _buttonsOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeIn),
      ),
    );

    _mainController.forward();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _mainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.black.withOpacity(0.6),
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _mainController,
              builder: (context, _) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // "It's a Match!" title
                    Transform.scale(
                      scale: _titleScale.value,
                      child: ShaderMask(
                        shaderCallback: (bounds) =>
                            AppColors.gradient.createShader(bounds),
                        child: Text(
                          "It's a Match!",
                          style: AppTypography.displayLarge.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: _avatarSlide.value,
                      child: Text(
                        'You and ${widget.matchedUser.name} liked each other',
                        style: AppTypography.bodyLarge.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Avatars
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(
                            -60 * (1 - _avatarSlide.value), 0,
                          ),
                          child: _MatchAvatar(
                            imageUrl: widget.currentUser.photoUrl,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Transform.translate(
                          offset: Offset(
                            60 * (1 - _avatarSlide.value), 0,
                          ),
                          child: _MatchAvatar(
                            imageUrl: widget.matchedUser.photoUrl,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),

                    // Buttons
                    Opacity(
                      opacity: _buttonsOpacity.value,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          children: [
                            GradientButton(
                              label: 'Send a Message',
                              onTap: widget.onSendMessage,
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: widget.onKeepSwiping,
                              child: Text(
                                'Keep Swiping',
                                style: AppTypography.bodyLarge.copyWith(
                                  color: Colors.white60,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchAvatar extends StatelessWidget {
  final String imageUrl;
  const _MatchAvatar({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
          ),
        ],
        image: DecorationImage(
          image: NetworkImage(imageUrl),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
```

---

## Chat Bubble

Message bubbles with gradient for sent, gray for received.

```dart
class ChatBubble extends StatelessWidget {
  final String message;
  final bool isMine;
  final String? timestamp;
  final bool showTimestamp;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.timestamp,
    this.showTimestamp = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMine ? 60 : 12,
        right: isMine ? 12 : 60,
        bottom: showTimestamp ? 4 : 2,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: isMine ? AppColors.gradient : null,
              color: isMine ? null : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMine ? 20 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 20),
              ),
            ),
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: isMine ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
          if (showTimestamp && timestamp != null) ...[
            const SizedBox(height: 4),
            Text(
              timestamp!,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

---

## Gradient Button

Reusable gradient call-to-action button.

```dart
class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final double? width;

  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.width,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.96).animate(
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
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        if (!widget.isLoading) widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: widget.width ?? double.infinity,
          height: 52,
          decoration: BoxDecoration(
            gradient: AppColors.gradient,
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF5864).withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : Text(
                    widget.label,
                    style: AppTypography.titleLarge.copyWith(
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
```

---

## Interest Chip

Tag chips for user interests on profile screens.

```dart
class InterestChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;

  const InterestChip({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: isSelected ? AppColors.gradient : null,
        color: isSelected ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
        border: isSelected
            ? null
            : Border.all(color: AppColors.divider, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: isSelected ? Colors.white : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Bottom Navigation Bar

Icon-only navigation with gradient active state and unread badge.

```dart
class AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  final Map<int, int> unreadCounts;

  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadCounts = const {},
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(Icons.local_fire_department_rounded, 'Discover'),
      _NavItem(Icons.search_rounded, 'Explore'),
      _NavItem(Icons.chat_bubble_rounded, 'Matches'),
      _NavItem(Icons.person_rounded, 'Profile'),
    ];

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final isActive = i == currentIndex;
          final unread = unreadCounts[i] ?? 0;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 20,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => isActive
                        ? AppColors.gradient.createShader(bounds)
                        : LinearGradient(
                            colors: [AppColors.textSecondary, AppColors.textSecondary],
                          ).createShader(bounds),
                    child: Icon(
                      items[i].icon,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.nope,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          '$unread',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
```

---

## Shimmer Loading Card

Skeleton loading placeholder for the swipe card.

```dart
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
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
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ??
                BorderRadius.circular(AppSpacing.cardRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2 * _controller.value, 0),
              end: Alignment(-1.0 + 2 * _controller.value + 1, 0),
              colors: const [
                Color(0xFFEEEEEE),
                Color(0xFFF5F5F5),
                Color(0xFFEEEEEE),
              ],
            ),
          ),
        );
      },
    );
  }
}
```
