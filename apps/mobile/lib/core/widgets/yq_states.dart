/// Loading, empty, error and offline states (spec §2.5, docs/DESIGN_SYSTEM.md).
///
/// **Loading rule (spec §2 / §6, «no bare spinners»).** Loading is a skeleton shaped like the real
/// content — [YqSkeletonBox], [YqSkeletonLine], [YqSkeletonOrbs], [YqSkeletonRows],
/// [YqSkeletonText], [YqSkeletonCard] and the prefabs beside them (`YqSkeletonAvatarRows`,
/// `YqSkeletonMushafPage`) — inside **one** [YqSkeleton], the single RTL-aware shimmer for the
/// whole region (never one shimmer per row). Determinate progress (downloads, installs, steps) is a
/// `YqRing`. A working button keeps its label and shimmers it (`YqButton(loading: true)`).
/// `CircularProgressIndicator`, `LinearProgressIndicator` and `RefreshProgressIndicator` are never
/// named in `lib/`; `test/core/no_spinner_test.dart` fails the build if one appears outside this
/// file. The one recorded exception is pull-to-refresh: Material's `RefreshIndicator` (in
/// `YqStage`'s `onRefresh` and on Home) paints its own pull cue while the content underneath stays
/// on screen, so it is not a loading state; the guard pins it to those two files.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../l10n/gen/app_localizations.dart';
import '../design/motion.dart';
import '../theme/tokens.dart';
import 'floating_tab_bar.dart';
import 'yq_button.dart';
import 'yq_icon.dart';

/// Empty state: idle icon + one-line title + one-line hint + optional action (spec §2.5).
class YqEmptyState extends StatelessWidget {
  const YqEmptyState({super.key, required this.icon, required this.title, this.hint, this.actionLabel, this.onAction});

  final YqIcons icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YqSpace.xxl, horizontal: YqSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0x99FFFFFF), borderRadius: BorderRadius.circular(YqRadii.tile)),
            child: YqIcon(icon, size: 28, tone: YqIconTone.idle),
          ),
          const SizedBox(height: YqSpace.l),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          if (hint != null) ...[const SizedBox(height: YqSpace.xs), Text(hint!, style: text.bodySmall, textAlign: TextAlign.center)],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: YqSpace.l),
            YqButton.secondary(label: actionLabel!, onPressed: onAction, expand: false),
          ],
        ],
      ),
    );
  }
}

/// «تعذّر التحميل. تحقق من الاتصال.» + «إعادة المحاولة» (spec §2.5).
class YqErrorState extends StatelessWidget {
  const YqErrorState({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return YqEmptyState(icon: YqIcons.download, title: message ?? t.errorGeneric, actionLabel: t.retry, onAction: onRetry);
  }
}

/// Thin banner on screens that need the network: «أنت غير متصل · نعمل بما على جهازك».
class YqOfflineBanner extends StatelessWidget {
  const YqOfflineBanner({super.key, required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AnimatedSize(
      duration: YqMotion.base,
      curve: YqMotion.ease,
      child: offline
          ? Padding(
              padding: const EdgeInsets.only(bottom: YqSpace.m),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
                  decoration: BoxDecoration(
                    color: const Color(0xCCFFFFFF),
                    borderRadius: BorderRadius.circular(YqRadii.pill),
                    border: Border.all(color: YqColors.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: YqColors.gold, shape: BoxShape.circle)),
                      const SizedBox(width: YqSpace.s),
                      Flexible(child: Text(t.offlineBanner, style: const TextStyle(fontSize: 12, color: YqColors.muted))),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

//// Skeleton → content (docs/DESIGN_SYSTEM.md §5): the new child cross-fades in over 200 ms while
/// the old one fades out underneath — no jump, no slide. Give each state its own [Key] (or a
/// different widget type). Instant under reduce-motion.
///
/// Every state sits in the same slot widget at the same depth, so a state that turns from current
/// to outgoing keeps its element (no remount: its scroll position, controllers and one-time
/// moments carry on while it fades). Only the current state decides the size; outgoing states are
/// laid out with the constraints they had, placed by [alignment], and take no taps or semantics.
class YqFadeSwap extends StatelessWidget {
  const YqFadeSwap({super.key, required this.child, this.alignment = Alignment.topCenter, this.expand = false});
  final Widget child;
  final AlignmentGeometry alignment;

  /// Whole screens (a loading scaffold giving way to the loaded one): both fill the space.
  final bool expand;

  static const duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => _FadeStack(
          alignment: alignment,
          expand: expand,
          children: [
            for (final p in previous) _FadeSlot(key: p.key, active: false, child: p),
            if (current != null) _FadeSlot(key: current.key, active: true, child: current),
          ],
        ),
        child: child,
      );
}

/// One state of a [YqFadeSwap]: the same widget at the same depth whether it is current or
/// outgoing, so flipping [active] only updates properties and never remounts the state.
class _FadeSlot extends StatelessWidget {
  const _FadeSlot({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) => _FadeSlotData(
        active: active,
        child: IgnorePointer(ignoring: !active, child: ExcludeSemantics(excluding: !active, child: child)),
      );
}

class _FadeSlotParentData extends ContainerBoxParentData<RenderBox> {
  bool active = true;
}

class _FadeSlotData extends ParentDataWidget<_FadeSlotParentData> {
  const _FadeSlotData({required this.active, required super.child});
  final bool active;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _FadeSlotParentData;
    if (data.active == active) return;
    data.active = active;
    final parent = renderObject.parent;
    if (parent is RenderObject) parent.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _FadeStack;
}

class _FadeStack extends MultiChildRenderObjectWidget {
  const _FadeStack({required this.alignment, required this.expand, super.children});
  final AlignmentGeometry alignment;
  final bool expand;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFadeStack(alignment: alignment, expand: expand, textDirection: Directionality.maybeOf(context));

  @override
  void updateRenderObject(BuildContext context, _RenderFadeStack renderObject) {
    renderObject
      ..alignment = alignment
      ..expand = expand
      ..textDirection = Directionality.maybeOf(context);
  }
}

/// A stack sized by its active (current) children only. Outgoing children get the same
/// constraints the current one gets, are placed by [alignment] and clipped to the box when they
/// overflow it (like `Stack`'s default clip).
class _RenderFadeStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FadeSlotParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FadeSlotParentData> {
  _RenderFadeStack({required AlignmentGeometry alignment, required bool expand, TextDirection? textDirection})
      : _alignment = alignment,
        _expand = expand,
        _textDirection = textDirection;

  AlignmentGeometry _alignment;
  set alignment(AlignmentGeometry v) {
    if (v == _alignment) return;
    _alignment = v;
    markNeedsLayout();
  }

  bool _expand;
  set expand(bool v) {
    if (v == _expand) return;
    _expand = v;
    markNeedsLayout();
  }

  TextDirection? _textDirection;
  set textDirection(TextDirection? v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  bool _overflows = false;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FadeSlotParentData) child.parentData = _FadeSlotParentData();
  }

  BoxConstraints _inner(BoxConstraints c) => _expand ? BoxConstraints.tight(c.biggest) : c.loosen();

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = (child.parentData! as _FadeSlotParentData).nextSibling;
    }
    return out;
  }

  static bool _active(RenderBox child) => (child.parentData! as _FadeSlotParentData).active;

  Size _sizeFor(BoxConstraints constraints, Size Function(RenderBox child, BoxConstraints inner) measure) {
    if (_expand) return constraints.biggest;
    final inner = _inner(constraints);
    var w = 0.0, h = 0.0;
    var any = false;
    for (final child in _kids) {
      if (!_active(child)) continue;
      any = true;
      final s = measure(child, inner);
      if (s.width > w) w = s.width;
      if (s.height > h) h = s.height;
    }
    if (!any) return constraints.biggest.isFinite ? constraints.biggest : constraints.smallest;
    return constraints.constrain(Size(w, h));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _sizeFor(constraints, (child, inner) => child.getDryLayout(inner));

  @override
  void performLayout() {
    final inner = _inner(constraints);
    final kids = _kids;
    if (_expand) {
      size = constraints.biggest;
    } else {
      size = _sizeFor(constraints, (child, c) {
        child.layout(c, parentUsesSize: true);
        return child.size;
      });
    }
    final align = _alignment.resolve(_textDirection);
    _overflows = false;
    for (final child in kids) {
      if (_expand || !_active(child)) child.layout(inner, parentUsesSize: true);
      final data = child.parentData! as _FadeSlotParentData;
      data.offset = align.alongOffset(Offset(size.width - child.size.width, size.height - child.size.height));
      if (child.size.width > size.width || child.size.height > size.height) _overflows = true;
    }
  }

  double _maxOverActive(double Function(RenderBox child) f) {
    var m = 0.0;
    for (final child in _kids) {
      if (!_active(child)) continue;
      final v = f(child);
      if (v > m) m = v;
    }
    return m;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _maxOverActive((c) => c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => _maxOverActive((c) => c.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) => _maxOverActive((c) => c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => _maxOverActive((c) => c.getMaxIntrinsicHeight(width));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    for (final child in _kids) {
      if (!_active(child)) continue;
      final d = child.getDistanceToActualBaseline(baseline);
      if (d != null) return d + (child.parentData! as _FadeSlotParentData).offset.dy;
    }
    return null;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_overflows) {
      _clip.layer = context.pushClipRect(needsCompositing, offset, Offset.zero & size, defaultPaint, oldLayer: _clip.layer);
    } else {
      _clip.layer = null;
      defaultPaint(context, offset);
    }
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => _overflows ? Offset.zero & size : null;

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

/// The sliver form of [YqFadeSwap] for lazy lists that replace a skeleton: the list fades in over
/// 200 ms when it first builds (no rebuild per frame). Instant under reduce-motion.
class YqSliverFadeIn extends StatefulWidget {
  const YqSliverFadeIn({super.key, required this.sliver});
  final Widget sliver;

  @override
  State<YqSliverFadeIn> createState() => _YqSliverFadeInState();
}

class _YqSliverFadeInState extends State<YqSliverFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: YqFadeSwap.duration);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SliverFadeTransition(opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut), sliver: widget.sliver);
}

/// Skeleton of the real layout: glass blocks under one 1.6 s shimmer (never a bare spinner on first paint).
class YqSkeleton extends StatefulWidget {
  const YqSkeleton({super.key, required this.child});

  /// Layout made of [YqSkeletonBox]es (or the prefabs below), shaped like the real content.
  final Widget child;

  /// One sweep. Everything inside one [YqSkeleton] shimmers as a single surface.
  static const period = Duration(milliseconds: 1600);

  @override
  State<YqSkeleton> createState() => _YqSkeletonState();
}

class _YqSkeletonState extends State<YqSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: YqSkeleton.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The light sweeps with the reading direction (right → left in Arabic), eased so it glides in
    // and lingers rather than ticking across at constant speed.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      label: Localizations.of<AppLocalizations>(context, AppLocalizations)?.skLoading ??
          MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final t = Curves.easeInOutSine.transform(_c.value);
              final x = -2.2 + 4.4 * t; // band centre travels from beyond one edge to beyond the other
              final c = rtl ? -x : x;
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment(c - 1.1, -0.25),
                  end: Alignment(c + 1.1, 0.25),
                  colors: const [Color(0x00FFFFFF), Color(0x66FFFFFF), Color(0xD9FFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
                  stops: const [0, 0.32, 0.5, 0.68, 1],
                ).createShader(rect),
                child: child,
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A placeholder shape: a soft mist tint that sits on the living ground and on glass alike.
class YqSkeletonBox extends StatelessWidget {
  const YqSkeletonBox({super.key, this.width, required this.height, this.radius = YqRadii.chip}) : circle = false;

  /// A disc of [size] (orbs, avatars, rings).
  const YqSkeletonBox.circle(double size, {super.key})
      : width = size,
        height = size,
        radius = 0,
        circle = true;

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  static const fill = Color(0xB3DCE4F2);

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: fill,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// A glass-shaped card placeholder of [height] (a hero card, a chart, a preview), the same glass as
/// [YqSkeletonRows]. Put it inside one [YqSkeleton].
class YqSkeletonCard extends StatelessWidget {
  const YqSkeletonCard({super.key, this.height = 120, this.radius = YqRadii.card});
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: YqSkeletonBox.fill,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0xB3FFFFFF)),
        ),
      );
}

/// A line of text-shaped placeholder; [widthFactor] of the available width.
class YqSkeletonLine extends StatelessWidget {
  const YqSkeletonLine({super.key, this.widthFactor = 1, this.height = 12});
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: YqSkeletonBox(height: height, radius: YqRadii.pill),
      );
}

/// Three complication orbs with their title and status lines.
class YqSkeletonOrbs extends StatelessWidget {
  const YqSkeletonOrbs({super.key, this.count = 3, this.size = 100});
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Column(
                children: [
                  YqSkeletonBox.circle(size),
                  const SizedBox(height: 10),
                  const YqSkeletonBox(width: 56, height: 11, radius: YqRadii.pill),
                  const SizedBox(height: 6),
                  const YqSkeletonBox(width: 40, height: 9, radius: YqRadii.pill),
                ],
              ),
            ),
        ],
      );
}

/// A glass-shaped card of [rows] list rows: an optional leading disc, a title and a subtitle line.
class YqSkeletonRows extends StatelessWidget {
  const YqSkeletonRows({super.key, this.rows = 4, this.leading = 40, this.trailing = false});
  final int rows;

  /// Leading disc size; 0 = none.
  final double leading;
  final bool trailing;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
        decoration: BoxDecoration(
          color: const Color(0x66FFFFFF),
          borderRadius: BorderRadius.circular(YqRadii.card),
          border: Border.all(color: const Color(0xB3FFFFFF)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: YqSpace.s + 2),
                child: Row(
                  children: [
                    if (leading > 0) ...[YqSkeletonBox.circle(leading), const SizedBox(width: YqSpace.m)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Varied lengths read as text, not as a barcode.
                          YqSkeletonLine(widthFactor: const [0.62, 0.48, 0.7, 0.55][i % 4], height: 13),
                          const SizedBox(height: 7),
                          YqSkeletonLine(widthFactor: const [0.38, 0.3, 0.44, 0.34][i % 4], height: 9),
                        ],
                      ),
                    ),
                    if (trailing) const YqSkeletonBox(width: 64, height: 32, radius: YqRadii.pill),
                  ],
                ),
              ),
          ],
        ),
      );
}

/// A card of text lines (a passage, a dua, a zikr), centred like the real text.
class YqSkeletonText extends StatelessWidget {
  const YqSkeletonText({super.key, this.lines = 4, this.lineHeight = 16});
  final int lines;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(YqSpace.xl),
        decoration: BoxDecoration(
          color: const Color(0x66FFFFFF),
          borderRadius: BorderRadius.circular(YqRadii.hero),
          border: Border.all(color: const Color(0xB3FFFFFF)),
        ),
        child: Column(
          children: [
            for (var i = 0; i < lines; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              FractionallySizedBox(
                widthFactor: i == lines - 1 ? 0.55 : const [1.0, 0.92, 0.97][i % 3],
                child: YqSkeletonBox(height: lineHeight, radius: YqRadii.pill),
              ),
            ],
          ],
        ),
      );
}

/// Short-lived glass pill message at the bottom (spec §2.5 «حُفظ وسيُزامَن عند الاتصال»).
abstract final class YqToast {
  static OverlayEntry? _current;
  static Timer? _timer;

  static void show(BuildContext context, String message, {Duration duration = const Duration(milliseconds: 2600)}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _remove();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: YqSpace.gutter,
        right: YqSpace.gutter,
        // Above the dock, wherever it is shown.
        bottom: FloatingTabBar.clearanceFor(Theme.of(context).platform, MediaQuery.paddingOf(context).bottom),
        child: IgnorePointer(
          child: Semantics(
            liveRegion: true,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: YqMotion.base,
              curve: YqMotion.ease,
              builder: (context, v, child) =>
                  Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child)),
              child: Center(
                // 90% opaque: a backdrop blur behind it would be invisible but cost a full blur pass.
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl, vertical: YqSpace.m),
                  decoration: BoxDecoration(color: const Color(0xE60A1530), borderRadius: BorderRadius.circular(YqRadii.pill)),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: YqColors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry);
    _timer = Timer(duration, _remove);
  }

  static void _remove() {
    _timer?.cancel();
    _timer = null;
    _current?.remove();
    _current = null;
  }
}

/// Glass bottom sheet with a grabber and 28-pt top radius (spec §2.4 `YqSheet`).
Future<T?> showYqSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = false, bool spring = false}) {
  final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    // [spring]: a moment worth arriving (the week result) opens on a critically damped spring.
    sheetAnimationStyle: still
        ? AnimationStyle.noAnimation
        : spring
            ? AnimationStyle(duration: Motion.sheetCurve.settle, curve: Motion.sheetCurve, reverseDuration: Motion.standard)
            : null,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x590A1530),
    builder: (context) {
      final sheet = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        // 96% opaque fill: no backdrop blur needed (it would be invisible and cost a full-screen pass).
        child: Container(
          decoration: const BoxDecoration(
            gradient:
                LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF5FFFFFF), Color(0xEDF3F6FB)]),
            border: Border(top: BorderSide(color: Color(0xE6FFFFFF))),
          ),
          padding: EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.m, YqSpace.gutter, YqSpace.xl + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(color: YqColors.mist, borderRadius: BorderRadius.circular(YqRadii.pill)),
                ),
              ),
              const SizedBox(height: YqSpace.l),
              Flexible(child: scrollable ? SingleChildScrollView(child: builder(context)) : builder(context)),
            ],
          ),
        ),
      );
      return Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: sheet);
    },
  );
}
