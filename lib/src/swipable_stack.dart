import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'swipable_positioned.dart';
import 'swipable_stack_controller.dart';
import 'swipe_sesion_state.dart';

extension _Animating on AnimationController {
  bool get animating =>
      status == AnimationStatus.forward || status == AnimationStatus.reverse;
}

enum SwipeDirection {
  left,
  right,
  up,
  down,
}

extension _SwipeDirectionX on SwipeDirection {
  Offset maxMovingDistance(BuildContext context) {
    final deviceSize = MediaQuery.of(context).size;
    switch (this) {
      case SwipeDirection.left:
        return Offset(-deviceSize.width, 0) * 1.04;
      case SwipeDirection.right:
        return Offset(deviceSize.width, 0) * 1.04;
      case SwipeDirection.up:
        return Offset(0, -deviceSize.height);
      case SwipeDirection.down:
        return Offset(0, deviceSize.height);
    }
  }

  bool get isHorizontal =>
      this == SwipeDirection.right || this == SwipeDirection.left;
}

typedef SwipeCompletionCallback = void Function(
  int index,
  SwipeDirection direction,
);

typedef OnWillMoveNext = bool Function(
  int index,
  SwipeDirection direction,
);

typedef SwipableStackOverlayBuilder = Widget Function(
  SwipeDirection direction,
  double valuePerThreshold,
);

extension SwipeSessionStateX on SwipeSessionState {
  RatePerThreshold swipeDirectionRate({
    required BoxConstraints constraints,
    required double horizontalSwipeThreshold,
    required double verticalSwipeThreshold,
  }) {
    final horizontalRate = (difference.dx.abs() / constraints.maxWidth) /
        (horizontalSwipeThreshold / 2);
    final verticalRate = (difference.dy.abs() / constraints.maxHeight) /
        (verticalSwipeThreshold / 2);
    final horizontalRateGreater = horizontalRate >= verticalRate;
    if (horizontalRateGreater) {
      return RatePerThreshold(
        direction:
            difference.dx >= 0 ? SwipeDirection.right : SwipeDirection.left,
        rate: horizontalRate,
      );
    } else {
      return RatePerThreshold(
        direction: difference.dy >= 0 ? SwipeDirection.down : SwipeDirection.up,
        rate: verticalRate,
      );
    }
  }

  SwipeDirection? swipeAssistDirection({
    required BoxConstraints constraints,
    required double horizontalSwipeThreshold,
    required double verticalSwipeThreshold,
  }) {
    final directionRate = swipeDirectionRate(
      constraints: constraints,
      horizontalSwipeThreshold: horizontalSwipeThreshold,
      verticalSwipeThreshold: verticalSwipeThreshold,
    );
    if (directionRate.rate < 1) {
      return null;
    } else {
      return directionRate.direction;
    }
  }
}

class RatePerThreshold {
  RatePerThreshold({
    required this.direction,
    required this.rate,
  }) : assert(rate >= 0);

  final SwipeDirection direction;

  final double rate;

  double get animationValue => math.min(rate * 0.8, 1);
}

class SwipableStack extends StatefulWidget {
  SwipableStack({
    required this.builder,
    this.controller,
    this.onSwipeCompleted,
    this.onWillMoveNext,
    this.overlayBuilder,
    this.horizontalSwipeThreshold = _defaultHorizontalSwipeThreshold,
    this.verticalSwipeThreshold = _defaultVerticalSwipeThreshold,
    this.itemCount,
  })  : assert(0 <= horizontalSwipeThreshold && horizontalSwipeThreshold <= 1),
        super(key: controller?.swipableStackStateKey);

  final IndexedWidgetBuilder builder;
  final SwipableStackController? controller;
  final SwipeCompletionCallback? onSwipeCompleted;
  final OnWillMoveNext? onWillMoveNext;
  final SwipableStackOverlayBuilder? overlayBuilder;
  final int? itemCount;
  final double horizontalSwipeThreshold;
  final double verticalSwipeThreshold;

  static const double _defaultHorizontalSwipeThreshold = 0.44;
  static const double _defaultVerticalSwipeThreshold = 0.32;

  static bool allowOnlyLeftAndRight(
    int index,
    SwipeDirection direction,
  ) =>
      direction == SwipeDirection.right || direction == SwipeDirection.left;

  static bool allowAllDirection(
    int index,
    SwipeDirection direction,
  ) =>
      true;

  @override
  SwipableStackState createState() => SwipableStackState();
}

class SwipableStackState extends State<SwipableStack>
    with TickerProviderStateMixin {
  late final AnimationController _swipeCancelAnimationController =
      AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  Animation<Offset> _cancelAnimation({
    required Offset startPosition,
    required Offset currentPosition,
  }) {
    return Tween<Offset>(
      begin: currentPosition,
      end: startPosition,
    ).animate(
      CurvedAnimation(
        parent: _swipeCancelAnimationController,
        curve: const ElasticOutCurve(0.95),
      ),
    );
  }

  double _distanceToAssist({
    required BuildContext context,
    required Offset difference,
    required SwipeDirection swipeDirection,
  }) {
    final deviceSize = MediaQuery.of(context).size;
    if (swipeDirection.isHorizontal) {
      final maxWidth = _areConstraints?.maxWidth ?? deviceSize.width;
      final maxHeight = _areConstraints?.maxHeight ?? deviceSize.height;
      final cardAngle = SwipablePositioned.calculateAngle(
        difference.dx,
        maxWidth,
      ).abs();
      final maxCardBackDistance = math.cos(math.pi / 2 - cardAngle) * maxHeight;
      return deviceSize.width - (difference.dx.abs() - maxCardBackDistance);
    } else {
      return deviceSize.height - difference.dy.abs();
    }
  }

  Offset _offsetToAssist({
    required Offset difference,
    required BuildContext context,
    required SwipeDirection swipeDirection,
  }) {
    final isHorizontal = swipeDirection.isHorizontal;
    if (isHorizontal) {
      final adjustedHorizontally = Offset(difference.dx * 2, difference.dy);
      final absX = adjustedHorizontally.dx.abs();
      final rate = _distanceToAssist(
            swipeDirection: swipeDirection,
            context: context,
            difference: difference,
          ) /
          absX;
      return adjustedHorizontally * rate;
    } else {
      final adjustedVertically = Offset(difference.dx, difference.dy * 2);
      final absY = adjustedVertically.dy.abs();
      final rate = _distanceToAssist(
            swipeDirection: swipeDirection,
            context: context,
            difference: difference,
          ) /
          absY;
      return adjustedVertically * rate;
    }
  }

  AnimationController _swipeAssistController({
    required SwipeDirection swipeDirection,
    required Offset difference,
  }) {
    final pixelPerMilliseconds = swipeDirection.isHorizontal ? 1.5 : 2.0;
    final distToAssist = _distanceToAssist(
      swipeDirection: swipeDirection,
      context: context,
      difference: difference,
    );

    return AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: math.min(distToAssist ~/ pixelPerMilliseconds, 500),
      ),
    );
  }

  Animation<Offset> _swipeAnimation({
    required AnimationController controller,
    required Offset startPosition,
    required Offset endPosition,
  }) {
    return Tween<Offset>(
      begin: startPosition,
      end: endPosition,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: const Cubic(0.7, 1, 0.73, 1),
      ),
    );
  }

  int _currentIndex = 0;
  bool _animatingSwipeAssistController = false;
  SwipeSessionState? _sessionState;
  BoxConstraints? _areConstraints;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _areConstraints = constraints;
        return Stack(
          children: _buildCards(
            context,
            constraints,
          ),
        );
      },
    );
  }

  List<Widget> _buildCards(BuildContext context, BoxConstraints constraints) {
    final cards = <Widget>[];
    for (var index = _currentIndex;
        index <
            math.min(_currentIndex + 3, widget.itemCount ?? _currentIndex + 3);
        index++) {
      cards.add(
        widget.builder(
          context,
          index,
        ),
      );
    }
    if (cards.isEmpty) {
      return [];
    } else {
      final positionedCards = List<Widget>.generate(
        cards.length,
        (index) => _buildCard(
          index: index,
          child: cards[index],
          constraints: constraints,
        ),
      ).reversed.toList();
      final swipeDirectionRate = _sessionState?.swipeDirectionRate(
        constraints: constraints,
        horizontalSwipeThreshold: widget.horizontalSwipeThreshold,
        verticalSwipeThreshold: widget.verticalSwipeThreshold,
      );

      if (swipeDirectionRate != null) {
        final overlay = widget.overlayBuilder?.call(
          swipeDirectionRate.direction,
          swipeDirectionRate.animationValue,
        );
        if (overlay != null) {
          final session = _sessionState ?? SwipeSessionState.notMoving();
          positionedCards.add(
            SwipablePositioned.overlay(
              sessionState: session,
              swipeDirectionRate: swipeDirectionRate,
              areaConstraints: constraints,
              child: overlay,
            ),
          );
        }
      }

      return positionedCards;
    }
  }

  Widget _buildCard({
    required int index,
    required Widget child,
    required BoxConstraints constraints,
  }) {
    final session = _sessionState ?? SwipeSessionState.notMoving();
    return SwipablePositioned(
      key: child.key,
      state: session,
      index: index,
      swipeDirectionRate: session.swipeDirectionRate(
        constraints: constraints,
        horizontalSwipeThreshold: widget.horizontalSwipeThreshold,
        verticalSwipeThreshold: widget.verticalSwipeThreshold,
      ),
      areaConstraints: constraints,
      child: GestureDetector(
        key: child.key,
        onPanStart: (d) {
          if (_animatingSwipeAssistController) {
            return;
          }

          if (_swipeCancelAnimationController.animating) {
            _swipeCancelAnimationController
              ..stop()
              ..reset();
          }
          setState(() {
            _sessionState = SwipeSessionState(
              localPosition: d.localPosition,
              startPosition: d.globalPosition,
              currentPosition: d.globalPosition,
            );
          });
        },
        onPanUpdate: (d) {
          if (_animatingSwipeAssistController) {
            return;
          }
          if (_swipeCancelAnimationController.animating) {
            _swipeCancelAnimationController
              ..stop()
              ..reset();
          }
          setState(() {
            final updated = _sessionState?.copyWith(
              currentPosition: d.globalPosition,
            );
            _sessionState = updated ??
                SwipeSessionState(
                  localPosition: d.localPosition,
                  startPosition: d.globalPosition,
                  currentPosition: d.globalPosition,
                );
          });
        },
        onPanEnd: (d) {
          if (_animatingSwipeAssistController) {
            return;
          }
          final swipeAssistDirection = _sessionState?.swipeAssistDirection(
            constraints: constraints,
            horizontalSwipeThreshold: widget.horizontalSwipeThreshold,
            verticalSwipeThreshold: widget.verticalSwipeThreshold,
          );

          if (swipeAssistDirection == null) {
            _cancelSwipe();
            return;
          }
          final allowMoveNext = widget.onWillMoveNext?.call(
                _currentIndex,
                swipeAssistDirection,
              ) ??
              true;
          if (!allowMoveNext) {
            _cancelSwipe();
            return;
          }
          _swipeNext(swipeAssistDirection);
        },
        child: child,
      ),
    );
  }

  void _animatePosition(Animation<Offset> positionAnimation) {
    final currentSession = _sessionState;
    if (currentSession == null) {
      return;
    }
    setState(() {
      _sessionState = currentSession.copyWith(
        currentPosition: positionAnimation.value,
      );
    });
  }

  void _cancelSwipe() {
    final currentSession = _sessionState;
    if (currentSession == null) {
      return;
    }
    final cancelAnimation = _cancelAnimation(
      startPosition: currentSession.startPosition,
      currentPosition: currentSession.currentPosition,
    );
    void _animate() {
      _animatePosition(cancelAnimation);
    }

    cancelAnimation.addListener(_animate);
    _swipeCancelAnimationController.forward(from: 0).then(
      (_) {
        cancelAnimation.removeListener(_animate);
        setState(() {
          _sessionState = null;
        });
      },
    );
  }

  void _swipeNext(SwipeDirection swipeDirection) {
    final currentSession = _sessionState;
    if (currentSession == null) {
      return;
    }
    if (_animatingSwipeAssistController) {
      return;
    }
    _animatingSwipeAssistController = true;
    final controller = _swipeAssistController(
      swipeDirection: swipeDirection,
      difference: currentSession.difference,
    );
    final animation = _swipeAnimation(
      controller: controller,
      startPosition: currentSession.currentPosition,
      endPosition: currentSession.currentPosition +
          _offsetToAssist(
            difference: currentSession.difference,
            context: context,
            swipeDirection: swipeDirection,
          ),
    );
    void animate() {
      _animatePosition(animation);
    }

    animation.addListener(animate);
    controller.forward().then(
      (_) {
        widget.onSwipeCompleted?.call(
          _currentIndex,
          swipeDirection,
        );
        animation.removeListener(animate);
        setState(() {
          _currentIndex += 1;
          _sessionState = null;
          _animatingSwipeAssistController = false;
        });
        controller.dispose();
      },
    );
  }

  /// This method not calls [SwipableStack.onWillMoveNext].
  void next({
    required SwipeDirection swipeDirection,
    bool shouldCallCompletionCallback = true,
  }) {
    if (_animatingSwipeAssistController) {
      return;
    }
    _animatingSwipeAssistController = true;
    final startPosition = SwipeSessionState.notMoving();
    _sessionState = startPosition;
    final controller = _swipeAssistController(
      swipeDirection: swipeDirection,
      difference: startPosition.difference,
    );
    final animation = _swipeAnimation(
      controller: controller,
      startPosition: Offset.zero,
      endPosition: swipeDirection.maxMovingDistance(context),
    );
    void animate() {
      _animatePosition(animation);
    }

    animation.addListener(animate);
    controller.forward().then(
      (_) {
        if (shouldCallCompletionCallback) {
          widget.onSwipeCompleted?.call(
            _currentIndex,
            swipeDirection,
          );
        }
        animation.removeListener(animate);
        setState(() {
          _currentIndex += 1;
          _sessionState = null;
          _animatingSwipeAssistController = false;
        });
        controller.dispose();
      },
    );
  }

  @override
  void dispose() {
    _swipeCancelAnimationController.dispose();
    super.dispose();
  }
}
