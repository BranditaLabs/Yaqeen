import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/theme/tokens.dart';

/// A glass orb filled to [level] (0…1) with a calm wave surface. The level eases on change; the
/// wave is still (no per-frame animation), so it costs nothing while scrolling.
class LiquidOrb extends StatelessWidget {
  const LiquidOrb({super.key, required this.level, this.size = 50, this.complete = false, this.child});

  final double level;
  final double size;
  final bool complete;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: level.clamp(0.0, 1.0)),
          duration: YqMotion.slow,
          curve: Curves.easeOutCubic,
          builder: (context, v, child) => CustomPaint(painter: _OrbPainter(level: v, complete: complete), child: child),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.level, required this.complete});
  final double level;
  final bool complete;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final circle = Path()..addOval(Rect.fromCircle(center: c, radius: r - 1));
    canvas.drawPath(circle, Paint()..color = const Color(0xB3FFFFFF));

    if (level > 0) {
      canvas.save();
      canvas.clipPath(circle);
      final surface = size.height * (1 - level);
      final amp = level >= 1 ? 0.0 : 2.4;
      final wave = Path()..moveTo(0, surface);
      for (var x = 0.0; x <= size.width; x += 2) {
        wave.lineTo(x, surface + math.sin(x / size.width * math.pi * 2) * amp);
      }
      wave
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final colors = complete ? const [Color(0xFF8FD3B0), YqColors.success] : const [YqColors.sky400, YqColors.lapis500];
      canvas.drawPath(
        wave,
        Paint()
          ..shader =
              LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(Offset.zero & size),
      );
      canvas.restore();
    }
    // Glass rim and a specular glint.
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x331F3F94),
    );
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r - 5),
      math.pi * 1.1,
      math.pi * 0.35,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xCCFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.level != level || old.complete != complete;
}
