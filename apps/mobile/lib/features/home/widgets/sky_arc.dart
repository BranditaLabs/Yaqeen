import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/tokens.dart';

/// Time of day, for the hero's sky colours and the sun/moon.
enum SkyPhase { dawn, day, golden, dusk, night }

/// Sky gradient per phase, from the brand tints only.
List<Color> skyColors(SkyPhase p) => switch (p) {
      SkyPhase.dawn => const [YqColors.gold100, YqColors.sky100],
      SkyPhase.day => const [YqColors.white, YqColors.sky200],
      SkyPhase.golden => const [YqColors.cream, YqColors.sand],
      SkyPhase.dusk => const [YqColors.sand, YqColors.gold300],
      SkyPhase.night => const [YqColors.sky200, YqColors.lapis100],
    };

/// Position along the arc (0 = start edge … 1 = end edge) for [now], with the five prayers as
/// evenly spaced stations at (i + 0.5) / 5 — the same x as the prayer labels in the row below.
/// Between two prayers the orb moves in proportion to the time elapsed between them.
double skyPosition(List<DateTime> prayers, DateTime previousIsha, DateTime nextFajr, DateTime now) {
  final n = prayers.length;
  double station(int i) => (i + 0.5) / n;
  double frac(DateTime a, DateTime b) {
    final span = b.difference(a).inSeconds;
    return span <= 0 ? 0 : (now.difference(a).inSeconds / span).clamp(0.0, 1.0);
  }

  if (now.isBefore(prayers.first)) return station(0) * frac(previousIsha, prayers.first);
  for (var i = 0; i < n - 1; i++) {
    if (now.isBefore(prayers[i + 1])) return station(i) + (station(i + 1) - station(i)) * frac(prayers[i], prayers[i + 1]);
  }
  return station(n - 1) + (1 - station(n - 1)) * frac(prayers.last, nextFajr);
}

/// The day as an arc: a faint path, the travelled part in gold, five prayer stations (passed =
/// filled, next = ringed) and the sun — or a crescent moon at night — at [position].
class SkyArcPainter extends CustomPainter {
  SkyArcPainter({required this.position, required this.nextIndex, required this.night, required this.rtl});

  final double position;
  final int nextIndex;
  final bool night;
  final bool rtl;

  static const stations = 5;

  Offset _at(Size size, double t) {
    final x = (rtl ? 1 - t : t) * size.width;
    const top = 14.0;
    final base = size.height - 6;
    return Offset(x, base - (base - top) * math.sin(math.pi * t));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    const steps = 60;
    for (var i = 0; i <= steps; i++) {
      final p = _at(size, i / steps);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x401F3F94),
    );

    // Travelled part.
    final done = Path();
    final until = (position * steps).round().clamp(0, steps);
    for (var i = 0; i <= until; i++) {
      final p = _at(size, i / steps);
      i == 0 ? done.moveTo(p.dx, p.dy) : done.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      done,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..color = night ? YqColors.lapis500 : YqColors.gold,
    );

    for (var i = 0; i < stations; i++) {
      final c = _at(size, (i + 0.5) / stations);
      final passed = i < nextIndex;
      final next = i == nextIndex;
      if (next) {
        canvas.drawCircle(c, 7, Paint()..color = const Color(0x33C6A867));
        canvas.drawCircle(
          c,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = YqColors.goldText,
        );
      } else {
        canvas.drawCircle(c, 3.5, Paint()..color = passed ? (night ? YqColors.lapis500 : YqColors.gold) : const Color(0xFFFFFFFF));
        if (!passed) {
          canvas.drawCircle(
            c,
            3.5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = const Color(0x661F3F94),
          );
        }
      }
    }

    final o = _at(size, position);
    if (night) {
      canvas.drawCircle(o, 16, Paint()..color = const Color(0x40FFFFFF));
      canvas.drawCircle(o, 8.5, Paint()..color = YqColors.white);
      // Crescent: cut the disc with an offset circle in the sky colour.
      canvas.drawCircle(o + Offset(rtl ? -3.5 : 3.5, -2.5), 7.2, Paint()..color = YqColors.sky200);
    } else {
      canvas.drawCircle(
        o,
        18,
        Paint()
          ..shader =
              const RadialGradient(colors: [Color(0x80E9D49E), Color(0x00E9D49E)]).createShader(Rect.fromCircle(center: o, radius: 18)),
      );
      canvas.drawCircle(o, 7.5, Paint()..color = YqColors.gold);
      canvas.drawCircle(o, 4.5, Paint()..color = YqColors.goldLight);
    }
  }

  @override
  bool shouldRepaint(SkyArcPainter old) => old.position != position || old.nextIndex != nextIndex || old.night != night || old.rtl != rtl;
}
