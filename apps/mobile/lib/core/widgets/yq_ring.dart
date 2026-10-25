import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A progress ring that eases to [value] (0…1), starting at the top and running with the reading
/// direction. Gold for rewards and worship goals, lapis otherwise. [child] sits in the centre.
class YqRing extends StatelessWidget {
  const YqRing({
    super.key,
    required this.value,
    this.size = 96,
    this.stroke = 7,
    this.gold = false,
    this.track,
    this.child,
  });

  final double value;
  final double size;
  final double stroke;
  final bool gold;
  final Color? track;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return RepaintBoundary(
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
              color: gold ? YqColors.gold : YqColors.lapis,
              track: track ?? (gold ? const Color(0x33C6A867) : const Color(0x261F3F94)),
              rtl: rtl,
            ),
            child: child,
          ),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
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
