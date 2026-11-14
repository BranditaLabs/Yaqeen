import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../theme/tokens.dart';

/// One-time moments (docs/DESIGN_SYSTEM.md §5): each plays once when it first builds (or when its
/// trigger turns on), then rests. All of them jump to the end state under reduce-motion and hold
/// no ticker afterwards.

/// Mixin for a state that runs one [AnimationController] once. A [delay] is part of the
/// controller's run (no timers), so a disposed widget never leaves one pending.
mixin _OnceController<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController c = AnimationController(vsync: this, duration: delay + onceDuration);

  Duration get onceDuration;

  /// Whether to play on the first build.
  bool get playOnStart;

  Duration get delay => Duration.zero;

  bool _started = false;

  /// Progress of the moment itself (0…1), after its delay.
  double get t {
    final total = c.duration!.inMicroseconds;
    if (total == 0) return 1;
    final start = delay.inMicroseconds / total;
    return start <= 0 ? c.value : Interval(start, 1).transform(c.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!playOnStart || reduceMotion(context)) {
      c.value = 1;
    } else {
      play();
    }
  }

  void play() {
    if (reduceMotion(context)) {
      c.value = 1;
    } else {
      c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }
}

/// A band of light that passes once across [child] (clipped to it): gold over an earned medal,
/// a soft lapis over the person's own row. [play] false draws [child] alone; [delay] staggers a
/// group. The band travels with the reading direction.
class YqSheen extends StatefulWidget {
  const YqSheen({
    super.key,
    required this.child,
    this.play = true,
    this.color = YqColors.goldLight,
    this.opacity = 0.75,
    this.duration = const Duration(milliseconds: 1100),
    this.delay = Duration.zero,
    this.circle = false,
    this.radius = 0,
  });

  final Widget child;
  final bool play;
  final Color color;

  /// The band's peak opacity.
  final double opacity;
  final Duration duration;
  final Duration delay;

  /// Clip the light to a circle (a medal) instead of a rounded rectangle of [radius].
  final bool circle;
  final double radius;

  @override
  State<YqSheen> createState() => _YqSheenState();
}

class _YqSheenState extends State<YqSheen> with SingleTickerProviderStateMixin, _OnceController {
  @override
  Duration get onceDuration => widget.duration;
  @override
  bool get playOnStart => widget.play;
  @override
  Duration get delay => widget.delay;

  @override
  void didUpdateWidget(YqSheen old) {
    super.didUpdateWidget(old);
    // Told to play after the first build (e.g. once a «seen» list has been read).
    if (widget.play && !old.play) play();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.play) return widget.child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: c,
                builder: (context, _) {
                  final t = this.t;
                  if (t <= 0 || t >= 1) return const SizedBox.shrink();
                  final x = Curves.easeInOutSine.transform(t) * 3.2 - 1.6; // beyond one edge → beyond the other
                  final cx = rtl ? -x : x;
                  final band = DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(cx - 0.9, -1),
                        end: Alignment(cx + 0.9, 1),
                        colors: [
                          widget.color.withValues(alpha: 0),
                          widget.color.withValues(alpha: widget.opacity),
                          widget.color.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  );
                  return widget.circle
                      ? ClipOval(child: band)
                      : ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: band);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A soft scale pulse (1.0 → [peak] → 1.0) played once when [active] first turns on — the avatar
/// breathing with the level-up light.
class YqPulse extends StatefulWidget {
  const YqPulse({super.key, required this.active, required this.child, this.peak = 1.04, this.duration = const Duration(milliseconds: 620)});
  final bool active;
  final Widget child;
  final double peak;
  final Duration duration;

  @override
  State<YqPulse> createState() => _YqPulseState();
}

class _YqPulseState extends State<YqPulse> with SingleTickerProviderStateMixin, _OnceController {
  @override
  Duration get onceDuration => widget.duration;
  @override
  bool get playOnStart => widget.active;

  @override
  void didUpdateWidget(YqPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) play();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        child: widget.child,
        builder: (context, child) {
          final t = this.t;
          // Up quickly, down gently.
          final s = t < .4 ? Curves.easeOut.transform(t / .4) : 1 - Curves.easeInOut.transform((t - .4) / .6);
          return Transform.scale(scale: 1 + (widget.peak - 1) * s, child: child);
        },
      );
}

/// A hairline that draws itself from [from] across its width once (zone lines in a league).
class YqDrawLine extends StatefulWidget {
  const YqDrawLine({
    super.key,
    this.color = YqColors.line,
    this.thickness = 1,
    this.from = AlignmentDirectional.centerStart,
    this.play = true,
    this.delay = Duration.zero,
  });
  final Color color;
  final double thickness;

  /// The end the line grows from.
  final AlignmentDirectional from;
  final bool play;
  final Duration delay;

  @override
  State<YqDrawLine> createState() => _YqDrawLineState();
}

class _YqDrawLineState extends State<YqDrawLine> with SingleTickerProviderStateMixin, _OnceController {
  @override
  Duration get onceDuration => Motion.emphasised + const Duration(milliseconds: 150);
  @override
  bool get playOnStart => widget.play;
  @override
  Duration get delay => widget.delay;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.thickness,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: c,
          builder: (context, _) => FractionallySizedBox(
            alignment: widget.from,
            widthFactor: Motion.emphasisedCurve.transform(t),
            child: ColoredBox(color: widget.color),
          ),
        ),
      );
}

/// A small dot that breathes (opacity only, one breath per [period]) to say «live», for a few
/// breaths and then rests lit: calm by default, nothing loops forever. Off-screen (TickerMode) it
/// pauses; under reduce-motion it is simply lit.
class YqBreathingDot extends StatefulWidget {
  const YqBreathingDot({super.key, this.size = 7, this.color = YqColors.lapis, this.period = const Duration(seconds: 2), this.breaths = 5});
  final double size;
  final Color color;
  final Duration period;
  final int breaths;

  @override
  State<YqBreathingDot> createState() => _YqBreathingDotState();
}

class _YqBreathingDotState extends State<YqBreathingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period * widget.breaths);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Opacity at controller value [t]: a slow sine breath between 0.35 and 1, ending lit.
  double _opacity(double t) {
    if (t >= 1) return 1;
    final phase = (t * widget.breaths) % 1;
    final s = Curves.easeInOutSine.transform(phase < .5 ? phase * 2 : (1 - phase) * 2);
    return 1 - 0.65 * s;
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Opacity(
            opacity: _opacity(_c.value),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ),
        ),
      );
}

/// Slides [child] in once from [offset] (a fraction of its own size) with a fade — the pinned
/// «ترتيبك» row rising from the bottom, a mini card arriving from the side.
class YqSlideIn extends StatefulWidget {
  const YqSlideIn({
    super.key,
    required this.child,
    this.offset = const Offset(0, 1),
    this.play = true,
    this.delay = Duration.zero,
    this.duration = Motion.emphasised,
  });
  final Widget child;
  final Offset offset;
  final bool play;
  final Duration delay;
  final Duration duration;

  @override
  State<YqSlideIn> createState() => _YqSlideInState();
}

class _YqSlideInState extends State<YqSlideIn> with SingleTickerProviderStateMixin, _OnceController {
  @override
  Duration get onceDuration => widget.duration;
  @override
  bool get playOnStart => widget.play;
  @override
  Duration get delay => widget.delay;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        child: widget.child,
        builder: (context, child) {
          final p = this.t;
          final t = Motion.emphasisedCurve.transform(p);
          return Opacity(
            opacity: Curves.easeOut.transform(p).clamp(0.0, 1.0),
            alwaysIncludeSemantics: true,
            child: FractionalTranslation(translation: widget.offset * (1 - t), child: child),
          );
        },
      );
}

//// A row that moved in a ranked list glides from where it was: [rows] is how many rows it moved
/// (positive = it was lower and climbed). Played when the row first builds with a move, or when a
/// new move arrives. A move of more than [maxRows] does not travel the whole way (it would cross
/// the rows around it): the row fades in from [maxRows] rows away instead.
class YqShiftIn extends StatefulWidget {
  const YqShiftIn({super.key, required this.rows, required this.child});
  final int rows;
  final Widget child;

  /// The furthest a row slides; larger moves fade in from here.
  static const maxRows = 3;

  @override
  State<YqShiftIn> createState() => _YqShiftInState();
}

class _YqShiftInState extends State<YqShiftIn> with SingleTickerProviderStateMixin, _OnceController {
  late int _rows = widget.rows;

  @override
  Duration get onceDuration => Motion.emphasised + const Duration(milliseconds: 100);
  @override
  bool get playOnStart => widget.rows != 0;

  @override
  void didUpdateWidget(YqShiftIn old) {
    super.didUpdateWidget(old);
    if (widget.rows != 0 && widget.rows != old.rows) {
      _rows = widget.rows;
      play();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        child: widget.child,
        builder: (context, child) {
          final t = Motion.emphasisedCurve.transform(this.t);
          if (t >= 1 || _rows == 0) return child!;
          final far = _rows.abs() > YqShiftIn.maxRows;
          final rows = _rows.clamp(-YqShiftIn.maxRows, YqShiftIn.maxRows);
          final moved = FractionalTranslation(translation: Offset(0, rows * (1 - t)), child: child);
          if (!far) return moved;
          return Opacity(opacity: t.clamp(0.0, 1.0), alwaysIncludeSemantics: true, child: moved);
        },
      );
}

/// Builds [builder] with `seen` false until the widget first scrolls into view (its top inside
/// the lower edge of the screen), then true for good — so an illustration below the fold plays
/// when the person reaches it, not while they are still at the top. No ticker: it listens to the
/// nearest scroll position only until seen.
class YqWhenVisible extends StatefulWidget {
  const YqWhenVisible({super.key, required this.builder, this.inset = 0.12});
  final Widget Function(BuildContext context, bool seen) builder;

  /// How far above the screen's bottom edge (a fraction of its height) counts as seen.
  final double inset;

  @override
  State<YqWhenVisible> createState() => _YqWhenVisibleState();
}

class _YqWhenVisibleState extends State<YqWhenVisible> {
  bool _seen = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seen) return;
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_check);
      _position = p?..addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_seen || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final height = MediaQuery.sizeOf(context).height;
    if (top < height * (1 - widget.inset)) {
      _position?.removeListener(_check);
      _position = null;
      setState(() => _seen = true);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _seen);
}
