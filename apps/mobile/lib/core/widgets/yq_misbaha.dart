import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// A misbaha loop: [beads] beads on a ring with the imam bead (and its tassel) at the top. Counted
/// beads turn gold; the latest one is slightly larger with a soft glow. [counted] may be fractional
/// while it animates.
class MisbahaPainter extends CustomPainter {
  MisbahaPainter({required this.counted, required this.beads});
  final double counted;
  final int beads;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final k = size.width / 100; // designed at 100 px; scales with the disc
    final r = size.width / 2 - 6 * k;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = k
        ..color = const Color(0x40C6A867),
    );
    final top = Offset(c.dx, c.dy - r);
    canvas.drawCircle(top, 4.6 * k, Paint()..color = YqColors.goldText);

    final step = math.pi * 2 / (beads + 1);
    final latest = counted.ceil() - 1;
    for (var i = 0; i < beads; i++) {
      final a = -math.pi / 2 + step * (i + 1);
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      final fill = (counted - i).clamp(0.0, 1.0);
      final isLatest = i == latest && fill > 0;
      final radius = (isLatest ? 3.8 : 2.9) * k * (beads <= 12 ? 1.6 : 1);
      if (isLatest) canvas.drawCircle(p, 7 * k * (beads <= 12 ? 1.4 : 1), Paint()..color = const Color(0x40E9D49E));
      canvas.drawCircle(p, radius, Paint()..color = Color.lerp(const Color(0xFFFFFFFF), YqColors.gold, fill)!);
      canvas.drawCircle(
        p,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = Color.lerp(const Color(0x591F3F94), YqColors.goldText, fill)!,
      );
    }
  }

  @override
  bool shouldRepaint(MisbahaPainter old) => old.counted != counted || old.beads != beads;
}

