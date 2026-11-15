import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Shared motion tokens (docs/DESIGN_SYSTEM.md §5). Premium here means restrained and physical:
/// springs that settle, light that passes once, never confetti and never a loop that runs forever.
///
/// `YqMotion` in `theme/tokens.dart` keeps the older 200 / 350 / 600 ms set used by existing
/// widgets; new moments use these.
abstract final class Motion {
  /// Small state changes: a press, a label swap, a skeleton giving way to content (with [fade]).
  static const quick = Duration(milliseconds: 160);

  /// Most UI transitions.
  static const standard = Duration(milliseconds: 280);

  /// Moments that carry meaning: a value arriving, a sheet opening, a glyph settling.
  static const emphasised = Duration(milliseconds: 450);

  /// Skeleton → content (§5 rule 14): one cross-fade, no jump.
  static const fade = Duration(milliseconds: 200);

  /// The level ring drawing in on first show: the Profile stage, and the smaller Home chip.
  static const ringDraw = Duration(milliseconds: 900);
  static const ringDrawSmall = Duration(milliseconds: 600);

  /// The level-up light sweeping once round the ring; the quiet toast follows it.
  static const glint = Duration(milliseconds: 900);

  /// How long the ring stays gold for a level just reached before settling back to lapis.
  static const glintHold = Duration(milliseconds: 1600);

  /// Default UI curve.
  static const easeOut = Curves.easeOutCubic;

  /// Emphasised: a fast start that lands softly (Material's emphasised decelerate).
  static const emphasisedCurve = Cubic(0.2, 0, 0, 1);

  /// Press feedback: a firm, quick spring with no wobble.
  static const pressSpring = SpringDescription(mass: 1, stiffness: 520, damping: 40);

  /// Releases and pops: a touch of overshoot, settles in ~400 ms.
  static const popSpring = SpringDescription(mass: 1, stiffness: 380, damping: 22);

  /// Sheets: critically damped — physical, never lifting off the bottom edge.
  static const sheetSpring = SpringDescription(mass: 1, stiffness: 260, damping: 32.25);

  /// A glyph settling with a visible overshoot (week result).
  static const settleSpring = SpringDescription(mass: 1, stiffness: 300, damping: 15);

  /// Curves made from the springs above, for implicit animations and routes.
  static final pressCurve = SpringCurve(pressSpring);
  static final popCurve = SpringCurve(popSpring);
  static final sheetCurve = SpringCurve(sheetSpring);
  static final settleCurve = SpringCurve(settleSpring);
}

/// True when the person asked the system for less motion: every moment then jumps to its end
/// state, with no reveal and no running ticker (docs/DESIGN_SYSTEM.md §5).
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [d], or zero under reduce-motion.
Duration motionOr(BuildContext context, Duration d) => reduceMotion(context) ? Duration.zero : d;

/// A [SpringDescription] as a [Curve] from 0 to 1, so springs can drive implicit animations and
/// routes. The curve spans the spring's settling time; give the animation about [settle] long.
class SpringCurve extends Curve {
  SpringCurve(this.spring, {this.tolerance = 0.001})
      : _settle = _settleTime(spring, tolerance),
        _sim = SpringSimulation(spring, 0, 1, 0);

  final SpringDescription spring;
  final double tolerance;
  final double _settle;
  final SpringSimulation _sim;

  /// Seconds until the spring stays within [tolerance] of the end.
  Duration get settle => Duration(microseconds: (_settle * 1e6).round());

  static double _settleTime(SpringDescription s, double tolerance) {
    final sim = SpringSimulation(s, 0, 1, 0);
    var last = 0.0;
    for (var t = 0.0; t < 5; t += 1 / 240) {
      if ((sim.x(t) - 1).abs() > tolerance || sim.dx(t).abs() > tolerance * 10) last = t;
    }
    return math.max(last, 1 / 60);
  }

  @override
  double transformInternal(double t) => _sim.x(t * _settle);
}

/// Remembers which one-time moments a screen has already played (a row's sheen, a zone line
/// drawing in, a podium rising), so lazy list items rebuilt by scrolling never replay them.
/// Lives as long as the screen's state; read it with [YqMotionMemo.firstTime].
class MotionMemo {
  final Set<String> _seen = {};

  /// True the first time [key] is asked for, false afterwards.
  bool first(String key) => _seen.add(key);

  bool seen(String key) => _seen.contains(key);
}

/// Provides a [MotionMemo] to a subtree (a screen's list).
class YqMotionMemo extends InheritedWidget {
  const YqMotionMemo({super.key, required this.memo, required super.child});
  final MotionMemo memo;

  /// True the first time [key] is asked for under this memo. Without a memo above, always true
  /// (the moment simply plays when built).
  static bool firstTime(BuildContext context, String key) =>
      context.getInheritedWidgetOfExactType<YqMotionMemo>()?.memo.first(key) ?? true;

  @override
  bool updateShouldNotify(YqMotionMemo old) => old.memo != memo;
}
