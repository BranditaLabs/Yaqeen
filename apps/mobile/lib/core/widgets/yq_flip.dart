import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/motion.dart';

/// Two faces of one disc: turning [showBack] on flips it about its vertical axis (perspective
/// 0.001, [Motion.emphasised]), turning with the reading direction. Only the face toward the eye is
/// built at any moment, so each face stays legible and hit-testable on its own. Under reduce-motion
/// the face simply changes.
class YqFlip extends StatelessWidget {
  const YqFlip({super.key, required this.showBack, required this.front, required this.back});

  final bool showBack;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return showBack ? back : front;
    final dir = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: showBack ? 1 : 0),
      duration: Motion.emphasised,
      curve: Motion.emphasisedCurve,
      builder: (context, t, _) {
        final angle = t * math.pi;
        final backFacing = angle > math.pi / 2;
        // The back face is pre-turned by half a turn so it reads the right way round.
        final face = backFacing ? back : front;
        final shown = backFacing ? angle - math.pi : angle;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(dir * shown),
          child: KeyedSubtree(key: ValueKey(backFacing), child: face),
        );
      },
    );
  }
}
