import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// One soft light on the porcelain ground.
class AmbientLight {
  const AmbientLight(this.alignment, this.color, {this.radius = 0.9});
  final Alignment alignment;
  final Color color;
  final double radius;
}

/// Porcelain ground with faint blue/gold light blooms. Gives the liquid
/// glass something to refract without adding shapes or full-screen colour.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child, this.lights = defaultLights, this.base = YqColors.porcelain});

  final Widget child;
  final List<AmbientLight> lights;
  final Color base;

  static const defaultLights = [
    AmbientLight(Alignment(0.85, -0.95), Color(0x528FB0E0)),
    AmbientLight(Alignment(-0.9, -0.2), Color(0x2EC6A867)),
    AmbientLight(Alignment(0.45, 1.0), Color(0x338FB0E0)),
  ];

  static const goldLights = [
    AmbientLight(Alignment(0, -0.8), Color(0x6BE9D49E)),
    AmbientLight(Alignment(0.9, 0.1), Color(0x428FB0E0)),
    AmbientLight(Alignment(-0.85, 0.85), Color(0x2EC6A867)),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final l in lights)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: l.alignment,
                  radius: l.radius,
                  colors: [l.color, l.color.withAlpha(0)],
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
