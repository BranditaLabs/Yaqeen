import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A progress ring that eases to [value] (0…1), starting at the top and running with the reading
/// direction. Gold for rewards and worship goals, lapis otherwise; [color] overrides both. [glint]
/// sweeps one soft highlight round the ring once (600 ms; static under reduce-motion) — used for the
/// level-up moment only. [child] sits in the centre.
class YqRing extends StatelessWidget {
  const YqRing({
    super.key,
    required this.value,
    this.size = 96,
    this.stroke = 7,
    this.gold = false,
    this.color,
    this.glint = false,
    this.track,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final bool gold;
  final Color? color;
  final bool glint;
  final Color? track;
  final Widget? child;

  Color get _color => color ?? (gold ? YqColors.gold : YqColors.lapis);

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final ring = RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value.clamp(0.0, 1.0)),
          duration: YqMotion.slow,
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => CustomPaint(
            painter: _RingPainter(
              value: v,
              stroke: stroke,
              color: _color,
              track: track ?? _color.withValues(alpha: gold && color == null ? 0x33 / 255 : 0x26 / 255),
              rtl: rtl,
            ),
            child: child,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
    if (!glint || reduceMotion) return ring;
    return Stack(
      alignment: Alignment.center,
      children: [
        ring,
        IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: YqMotion.slow,
            curve: Curves.easeInOutSine,
            builder: (context, t, _) => CustomPaint(
              size: Size.square(size),
              painter: _GlintPainter(t: t, stroke: stroke, rtl: rtl),
            ),
          ),
        ),
      ],
    );
  }
}

/// One soft highlight travelling once round the ring, fading out at the end.
class _GlintPainter extends CustomPainter {
  _GlintPainter({required this.t, required this.stroke, required this.rtl});
  final double t;
  final double stroke;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    final arc = (Offset.zero & size).deflate(stroke / 2 + 1);
    final dir = rtl ? -1.0 : 1.0;
    final start = -math.pi / 2 + dir * math.pi * 2 * t;
    final opacity = (t < .8 ? 1.0 : (1 - t) / .2).clamp(0.0, 1.0);
    canvas.drawArc(
      arc,
      start,
      dir * math.pi / 5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = YqColors.goldLight.withValues(alpha: .9 * opacity),
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
    if (value <= 0) return;
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
