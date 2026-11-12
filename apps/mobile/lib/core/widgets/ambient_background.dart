import 'package:flutter/material.dart';

import '../design/living_sky.dart';
import '../theme/tokens.dart';

/// One soft light on the porcelain ground.
class AmbientLight {
  const AmbientLight(this.alignment, this.color, {this.radius = 0.9});
  final Alignment alignment;
  final Color color;
  final double radius;
}

/// The app's ground: porcelain lit by the living sky (docs/DESIGN_SYSTEM.md §1).
///
/// The tint follows the time of day (palette blended between keyframes at the real prayer
/// times) and the main glow sits under the sun's position on the day arc, mirrored in RTL — the
/// same light as Home's sky, on every screen. [lights] add accents on top (gold on reward
/// screens, the aligned Qibla). Repaints at most every 30 s and eases each change over ~1 s.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child, this.lights, this.base = YqColors.porcelain});

  final Widget child;

  /// Accent lights over the living sky; null = the sky alone.
  final List<AmbientLight>? lights;
  final Color base;

  /// The pre-living-sky blooms, kept as an accent set.
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
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: LivingSky(
              builder: (context, sky) => TweenAnimationBuilder<SkyPalette>(
                tween: SkyPaletteTween(end: sky.palette),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeInOut,
                builder: (context, p, _) => TweenAnimationBuilder<double>(
                  tween: Tween(end: skyX(sky.position, rtl: rtl)),
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeInOut,
                  builder: (context, x, _) => _SkyLight(palette: p, sunX: x, base: base),
                ),
              ),
            ),
          ),
          for (final l in lights ?? const <AmbientLight>[])
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: l.alignment, radius: l.radius, colors: [l.color, l.color.withAlpha(0)]),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// The sky's light on the ground: a tint fading down the page, a glow under the sun and a fainter
/// counter-light lower on the opposite side, so the page never reads flat.
class _SkyLight extends StatelessWidget {
  const _SkyLight({required this.palette, required this.sunX, required this.base});
  final SkyPalette palette;
  final double sunX;
  final Color base;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        key: const ValueKey('sky-light'),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(base, palette.bottom, 0.45)!, base, base],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(sunX, -0.72),
                  radius: 0.95,
                  colors: [palette.glow.withValues(alpha: 0.42), palette.glow.withValues(alpha: 0)],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-sunX * 0.8, 0.55),
                  radius: 0.9,
                  colors: [palette.top.withValues(alpha: 0.5), palette.top.withValues(alpha: 0)],
                ),
              ),
            ),
          ],
        ),
      );
}
