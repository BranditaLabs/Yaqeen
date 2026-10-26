import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../theme/tokens.dart';
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

/// Skeleton of the real layout: glass blocks with a 1.2 s shimmer (never a bare spinner on first paint).
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
      label: MaterialLocalizations.of(context).refreshIndicatorSemanticLabel,
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

  static const fill = Color(0xB3E1E8F3);

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
        bottom: MediaQuery.paddingOf(context).bottom + 104,
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
Future<T?> showYqSheet<T>(BuildContext context, {required WidgetBuilder builder, bool scrollable = false}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
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
