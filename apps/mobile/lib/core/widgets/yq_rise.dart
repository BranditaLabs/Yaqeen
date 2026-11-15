import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Rises [distance] (14 px) and fades in once, staggered by [order] × [stagger] (70 ms; the orbs
/// use 40 ms). Skipped with reduced motion (docs/DESIGN_SYSTEM.md §5).
///
/// Inside a [YqRiseScope] (every `YqCanvas`, Home) only content that appears while the page opens
/// rises; a lazy list item built later — scrolled into view, or rebuilt after scrolling away — is
/// simply there, so long pages never fade in under the finger.
class YqRise extends StatefulWidget {
  const YqRise({super.key, this.order = 0, this.stagger = const Duration(milliseconds: 70), this.distance = 14, required this.child});
  final int order;
  final Duration stagger;
  final double distance;
  final Widget child;

  /// Each item's own rise.
  static const run = Duration(milliseconds: 350);

  /// The latest an item starts, however long the list.
  static const maxDelay = Duration(milliseconds: 420);

  @override
  State<YqRise> createState() => _YqRiseState();
}

class _YqRiseState extends State<YqRise> {
  bool? _play;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _play ??= !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
        (context.getInheritedWidgetOfExactType<_RiseWindow>()?.scope.isOpen ?? true);
  }

  @override
  Widget build(BuildContext context) {
    if (_play != true) return widget.child;
    final delayUs = (widget.stagger.inMicroseconds * widget.order).clamp(0, YqRise.maxDelay.inMicroseconds);
    final totalUs = delayUs + YqRise.run.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(microseconds: totalUs),
      curve: Interval(delayUs / totalUs, 1, curve: Curves.easeOutCubic),
      child: widget.child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        // Screen readers see the content at once; only the eye waits for the rise.
        alwaysIncludeSemantics: true,
        child: Transform.translate(offset: Offset(0, widget.distance * (1 - v)), child: child),
      ),
    );
  }
}

/// Marks a page whose [YqRise]s play only while it opens (the first [window] of frames).
class YqRiseScope extends StatefulWidget {
  const YqRiseScope({super.key, required this.child});
  final Widget child;

  /// How long after the page's first frame new content still rises (data that loads quickly).
  static const window = Duration(milliseconds: 800);

  @override
  State<YqRiseScope> createState() => _YqRiseScopeState();
}

class _YqRiseScopeState extends State<YqRiseScope> {
  Duration? _opened;

  /// Frame time, so it follows the test clock too; null between frames.
  static Duration? get _now {
    final binding = SchedulerBinding.instance;
    return binding.schedulerPhase == SchedulerPhase.idle ? null : binding.currentFrameTimeStamp;
  }

  @override
  void initState() {
    super.initState();
    _opened = _now;
  }

  bool get isOpen {
    final now = _now;
    _opened ??= now;
    final opened = _opened;
    return now == null || opened == null || now - opened < YqRiseScope.window;
  }

  @override
  Widget build(BuildContext context) => _RiseWindow(scope: this, child: widget.child);
}

class _RiseWindow extends InheritedWidget {
  const _RiseWindow({required this.scope, required super.child});
  final _YqRiseScopeState scope;

  @override
  bool updateShouldNotify(_RiseWindow old) => false;
}
