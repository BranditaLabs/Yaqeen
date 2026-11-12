import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Drop shadows painted **outside** a shape only.
///
/// A plain `BoxShadow` is drawn under the whole box, so under translucent glass it shows through
/// as a grey patch inside the card. This clips the shape out of the shadow layer: the glass stays
/// clean and the shadow only lifts it off the page. [circle] makes the shape the inscribed circle.
class OuterShadow extends StatelessWidget {
  const OuterShadow({super.key, required this.shadows, required this.child, this.borderRadius = BorderRadius.zero, this.circle = false});

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;
  final bool circle;
  final Widget child;

  @override
  Widget build(BuildContext context) => shadows.isEmpty
      ? child
      : CustomPaint(painter: _OuterShadowPainter(shadows: shadows, borderRadius: borderRadius, circle: circle), child: child);
}

class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter({required this.shadows, required this.borderRadius, required this.circle});
  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = circle
        ? RRect.fromRectAndRadius(Rect.fromCircle(center: rect.center, radius: size.shortestSide / 2), Radius.circular(size.shortestSide / 2))
        : borderRadius.toRRect(rect);
    final reach = shadows.fold<double>(0, (m, s) => math.max(m, s.blurRadius * 2 + s.spreadRadius.abs() + s.offset.distance));
    canvas.save();
    canvas.clipPath(
      Path.combine(PathOperation.difference, Path()..addRect(rect.inflate(reach + 4)), Path()..addRRect(shape)),
    );
    for (final s in shadows) {
      canvas.drawRRect(
        shape.shift(s.offset).inflate(s.spreadRadius),
        Paint()
          ..color = s.color
          ..maskFilter = s.blurRadius > 0 ? MaskFilter.blur(BlurStyle.normal, s.blurSigma) : null,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) => !listEquals(old.shadows, shadows) || old.borderRadius != borderRadius || old.circle != circle;
}
