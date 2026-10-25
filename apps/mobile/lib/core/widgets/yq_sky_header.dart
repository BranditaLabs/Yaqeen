import 'package:flutter/material.dart';

import '../design/living_sky.dart';
import '../theme/tokens.dart';

/// A tab root's header as a band of the living sky (docs/DESIGN_SYSTEM.md §3): edge to edge and
/// under the status bar, tinted by the time of day like Home's sky stage, with rounded lower
/// corners. Wraps the screen's own header [child] (title, subtitle, actions).
///
/// Use it as the first item of a scroll view whose horizontal padding is [bleed] and whose
/// parent SafeArea has `top: false` — the band paints past both to reach the screen edges.
class YqSkyHeader extends StatelessWidget {
  const YqSkyHeader({super.key, required this.child, this.bleed = YqSpace.gutter});

  final Widget child;

  /// The scroll view's horizontal padding, painted over so the band meets the screen edges.
  final double bleed;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -bleed,
          right: -bleed,
          top: 0,
          bottom: 0,
          child: RepaintBoundary(
            child: LivingSky(
              builder: (context, sky) => AnimatedContainer(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [sky.palette.top, sky.palette.bottom],
                  ),
                  boxShadow: const [BoxShadow(color: Color(0x1F0F1A36), blurRadius: 26, spreadRadius: -12, offset: Offset(0, 10))],
                ),
              ),
            ),
          ),
        ),
        Padding(padding: EdgeInsets.only(top: top + YqSpace.m, bottom: YqSpace.xl), child: child),
      ],
    );
  }
}
