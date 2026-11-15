import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../theme/tokens.dart';

/// A progress ring that eases to [value] (0…1), starting at the top and running with the reading
/// direction. Gold for rewards and worship goals, lapis otherwise; [color] overrides both. [child]
/// sits in the centre.
///
/// Motion (docs/DESIGN_SYSTEM.md §5):
/// - [drawIn]: on first show the track fades in, then the arc sweeps from 0 to [value] (emphasised).
///   Without it the ring appears at its value. Either way a later change eases from the old value
///   to the new one — never from 0 again.
/// - [glint]: one soft light sweeps once round the ring ([Motion.glint]) when the ring first shows
///   with it, or when it turns on — the level-up moment only.
/// - A colour change (lapis → gold for a level just reached) blends over [Motion.standard].
/// - Reduce-motion: every value is drawn at once and the glint is skipped.
class YqRing extends StatefulWidget {
  const YqRing({
    super.key,
    required this.value,
    this.size = 96,
    this.stroke = 7,
    this.gold = false,
    this.color,
    this.glint = false,
    this.track,
    this.drawIn,
    this.change = YqRing.changeDuration,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final bool gold;
  final Color? color;
  final bool glint;
  final Color? track;

  /// How long the first sweep from 0 takes ([Motion.ringDraw] on the Profile stage,
  /// [Motion.ringDrawSmall] on the Home chip); null shows the value at once.
  final Duration? drawIn;

  /// How long a later value change takes; zero follows [value] exactly (a parent animating it).
  final Duration change;
  final Widget? child;

  static const changeDuration = YqMotion.slow;

  Color get _color => color ?? (gold ? YqColors.gold : YqColors.lapis);

  Color get _track => track ?? _color.withValues(alpha: gold && color == null ? 0x33 / 255 : 0x26 / 255);

  @override
  State<YqRing> createState() => _YqRingState();
}

class _YqRingState extends State<YqRing> with TickerProviderStateMixin {
  /// Drives the arc from [_from] to [_to].
  late final AnimationController _move = AnimationController(vsync: this, value: 1);

  /// The one light sweep; null until the first glint.
  AnimationController? _glint;

  /// Colour blends (lapis ↔ gold).
  late final AnimationController _tint = AnimationController(vsync: this, duration: Motion.standard, value: 1);

  double _from = 0;
  double _to = 0;
  Curve _curve = Curves.easeOutCubic;

  /// The first draw is running: the track fades in during its first third.
  bool _drawing = false;

  late Color _colorFrom = widget._color;
  late Color _trackFrom = widget._track;

  bool _started = false;

  double get _clamped => widget.value.clamp(0.0, 1.0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _to = _clamped;
    final still = reduceMotion(context);
    final draw = widget.drawIn;
    if (draw != null && !still && draw > Duration.zero) {
      _from = 0;
      _drawing = true;
      _curve = const Interval(0.15, 1, curve: Motion.emphasisedCurve);
      _move
        ..duration = draw
        ..forward(from: 0).whenCompleteOrCancel(() => _drawing = false);
    } else {
      _from = _to;
    }
    if (widget.glint && !still) _playGlint();
  }

  @override
  void didUpdateWidget(YqRing old) {
    super.didUpdateWidget(old);
    final still = reduceMotion(context);
    final next = _clamped;
    if (next != _to) {
      final current = _value;
      _to = next;
      _drawing = false;
      if (still || widget.change == Duration.zero) {
        _from = next;
        _move.value = 1;
      } else {
        _from = current;
        _curve = Curves.easeOutCubic;
        _move
          ..duration = widget.change
          ..forward(from: 0);
      }
    }
    if (old._color != widget._color || old._track != widget._track) {
      _colorFrom = Color.lerp(_colorFrom, old._color, _tint.value) ?? old._color;
      _trackFrom = Color.lerp(_trackFrom, old._track, _tint.value) ?? old._track;
      if (still) {
        _tint.value = 1;
      } else {
        _tint.forward(from: 0);
      }
    }
    if (widget.glint && !old.glint && !still) _playGlint();
  }

  void _playGlint() {
    final c = _glint ??= AnimationController(vsync: this, duration: Motion.glint);
    c.forward(from: 0);
  }

  double get _value => _from + (_to - _from) * _curve.transform(_move.value.clamp(0.0, 1.0));

  @override
  void dispose() {
    _move.dispose();
    _tint.dispose();
    _glint?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final size = widget.size;
    final ring = AnimatedBuilder(
      animation: Listenable.merge([_move, _tint]),
      child: widget.child == null ? null : Center(child: widget.child),
      builder: (context, child) {
        final tint = Curves.easeInOut.transform(_tint.value);
        final trackOpacity = _drawing ? const Interval(0, 0.33, curve: Curves.easeOut).transform(_move.value) : 1.0;
        final track = Color.lerp(_trackFrom, widget._track, tint)!;
        return CustomPaint(
          painter: _RingPainter(
            value: _value,
            stroke: widget.stroke,
            color: Color.lerp(_colorFrom, widget._color, tint)!,
            track: track.withValues(alpha: track.a * trackOpacity),
            rtl: rtl,
          ),
          child: child,
        );
      },
    );
    final glint = _glint;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: glint == null
            ? ring
            : Stack(
                fit: StackFit.expand,
                children: [
                  ring,
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: glint,
                      builder: (context, _) => CustomPaint(
                        painter: _GlintPainter(t: glint.value, stroke: widget.stroke, rtl: rtl),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// One light passing once round the ring: a soft comet (a bright head with a fading tail) that
/// eases in, travels a full turn with the reading direction and fades out. Light only, no shape.
class _GlintPainter extends CustomPainter {
  _GlintPainter({required this.t, required this.stroke, required this.rtl});
  final double t;
  final double stroke;
  final bool rtl;

  static const _tail = math.pi * 0.55;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final arc = (Offset.zero & size).deflate(stroke / 2 + 1);
    final dir = rtl ? -1.0 : 1.0;
    final travel = Curves.easeInOutCubic.transform(t);
    final head = -math.pi / 2 + dir * math.pi * 2 * travel;
    final opacity = (t < .12 ? t / .12 : (t > .75 ? (1 - t) / .25 : 1.0)).clamp(0.0, 1.0);
    final center = arc.center;
    // The tail: a sweep gradient from clear to light, ending at the head.
    final tailStart = head - dir * _tail;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rtl ? head : tailStart);
    canvas.translate(-center.dx, -center.dy);
    final shader = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: _tail,
      colors: rtl
          ? [YqColors.white.withValues(alpha: .95 * opacity), YqColors.goldLight.withValues(alpha: 0)]
          : [YqColors.goldLight.withValues(alpha: 0), YqColors.white.withValues(alpha: .95 * opacity)],
    ).createShader(arc);
    canvas.drawArc(
      arc,
      0,
      _tail,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..shader = shader,
    );
    canvas.restore();
    // The head: a small bloom of light where the comet is.
    final p = center + Offset(math.cos(head) * arc.width / 2, math.sin(head) * arc.height / 2);
    final r = stroke * 2.2;
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [YqColors.white.withValues(alpha: .9 * opacity), YqColors.goldLight.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: p, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GlintPainter old) => old.t != t || old.stroke != stroke || old.rtl != rtl;
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.stroke, required this.color, required this.track, required this.rtl});
  final double value;
  final double stroke;
  final Color color;
  final Color track;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2 + 1);
    if (track.a > 0) {
      canvas.drawArc(
        arc,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track,
      );
    }
    if (value <= 0.0005) return;
    final sweep = math.pi * 2 * value * (rtl ? -1 : 1);
    canvas.drawArc(
      arc,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track || old.stroke != stroke || old.rtl != rtl;
}
