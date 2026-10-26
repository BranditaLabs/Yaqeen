import 'package:flutter/widgets.dart';

/// Rises 14 px and fades in once, staggered by [order] (70 ms apart). Not replayed on rebuilds or
/// tab switches; skipped with reduced motion (docs/DESIGN_SYSTEM.md §5).
class YqRise extends StatelessWidget {
  const YqRise({super.key, this.order = 0, required this.child});
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final start = (order * 0.07).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        // Screen readers see the content at once; only the eye waits for the rise.
        alwaysIncludeSemantics: true,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
    );
  }
}
