import 'package:flutter/material.dart';

import '../design/living_sky.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'ambient_background.dart';
import 'yq_layout.dart';
import 'yq_rise.dart';

/// The living-sky stage every screen opens with (docs/DESIGN_SYSTEM.md §3): edge to edge under
/// the status bar, tinted by the time of day, with rounded lower corners. Holds the screen's bar
/// ([YqStageBar]) and its one large moment ([YqMoment]).
///
/// [gold] warms the sky with a gold bloom (reward screens), never replacing it.
class YqStage extends StatelessWidget {
  const YqStage({super.key, required this.child, this.gold = false, this.compact = false});

  final Widget child;
  final bool gold;

  /// Pushed screens: smaller corners and bottom padding.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final radius = Radius.circular(compact ? 32 : 40);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: LivingSky(
              builder: (context, sky) => AnimatedContainer(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(bottom: radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [sky.palette.top, sky.palette.bottom],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x240A1530), blurRadius: 30, spreadRadius: -12, offset: Offset(0, 12)),
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.vertical(bottom: radius),
                  gradient: RadialGradient(
                    center: Alignment(skyX(sky.position, rtl: rtl), -0.9),
                    radius: 1.1,
                    colors: [
                      (gold ? YqColors.goldLight : sky.palette.glow).withValues(alpha: gold ? 0.55 : 0.32),
                      sky.palette.glow.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(YqSpace.gutter, top + YqSpace.m, YqSpace.gutter, compact ? YqSpace.l : YqSpace.xl),
          // Full width, so a centred moment is centred on the stage (not on its widest line at the start edge).
          child: SizedBox(width: double.infinity, child: child),
        ),
      ],
    );
  }
}

/// The stage's top row: optional back button, title + subtitle, actions.
class YqStageBar extends StatelessWidget {
  const YqStageBar({
    super.key,
    required this.title,
    this.subtitle,
    this.back = false,
    this.backLabel,
    this.actions = const [],
    this.leading,
    this.large = false,
  });

  final String title;
  final String? subtitle;
  final bool back;
  final String? backLabel;
  final List<Widget> actions;

  /// Replaces the back button (an avatar, a medallion).
  final Widget? leading;

  /// Tab roots: the display face at 28.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        if (back) ...[YqBackButton(label: backLabel), const SizedBox(width: YqSpace.m)],
        if (leading != null) ...[leading!, const SizedBox(width: YqSpace.m)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: large ? YqText.display.copyWith(fontSize: 28) : text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (subtitle != null) Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            ],
          ),
        ),
        for (final a in actions) ...[const SizedBox(width: YqSpace.s), a],
      ],
    );
  }
}

/// The one large moment of a screen: a gold eyebrow, the value in large type, a caption.
class YqMoment extends StatelessWidget {
  const YqMoment({super.key, this.eyebrow, required this.value, this.caption, this.center = true});

  final String? eyebrow;
  final Widget value;
  final Widget? caption;
  final bool center;

  /// The large value style: display face (Arabic) or Jost Light (numbers).
  static TextStyle display(BuildContext context, {double size = 44}) =>
      Theme.of(context).textTheme.headlineLarge!.copyWith(fontSize: size, height: 1.15, fontWeight: FontWeight.w700);
  static TextStyle numeral({double size = 46, Color color = YqColors.ink}) =>
      YqText.numeral.copyWith(fontSize: size, fontWeight: FontWeight.w300, color: color, height: 1.05, letterSpacing: 0.5);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Text(
            eyebrow!,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: text.labelSmall?.copyWith(color: YqColors.goldText, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6),
          ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(textAlign: center ? TextAlign.center : TextAlign.start, child: value),
        if (caption != null) ...[
          const SizedBox(height: 4),
          DefaultTextStyle.merge(
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: text.bodySmall?.copyWith(fontSize: 13),
            child: caption!,
          ),
        ],
      ],
    );
  }
}

/// A full screen in the living-canvas pattern: the living ground, the [stage] edge to edge, then
/// the body under the gutter — either [children] (rise in once, staggered) or lazy [slivers].
class YqCanvas extends StatelessWidget {
  const YqCanvas({
    super.key,
    required this.stage,
    this.children = const [],
    this.slivers = const [],
    this.lights,
    this.onRefresh,
    this.bottom = 140,
    this.controller,
    this.footer,
  });

  final Widget stage;
  final List<Widget> children;

  /// Lazy content after [children] (long lists). Each sliver gets the gutter.
  final List<Widget> slivers;
  final List<AmbientLight>? lights;
  final Future<void> Function()? onRefresh;

  /// Space under the content (the floating tab bar on tab roots; less on pushed screens).
  final double bottom;
  final ScrollController? controller;

  /// A fixed block under the scroll view (a primary action), kept above the system inset.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    const gutter = EdgeInsets.symmetric(horizontal: YqSpace.gutter);
    final scroll = CustomScrollView(
      controller: controller,
      slivers: [
        SliverToBoxAdapter(child: YqRise(order: 0, child: stage)),
        if (children.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.xl, YqSpace.gutter, 0),
            sliver: SliverList.list(
              children: [for (var i = 0; i < children.length; i++) YqRise(order: i + 1, child: children[i])],
            ),
          ),
        for (final s in slivers) SliverPadding(padding: gutter, sliver: s),
        SliverToBoxAdapter(child: SizedBox(height: bottom + (footer == null ? MediaQuery.paddingOf(context).bottom : 0))),
      ],
    );
    final body = onRefresh == null
        ? scroll
        : RefreshIndicator(
            color: YqColors.lapis,
            edgeOffset: MediaQuery.paddingOf(context).top,
            onRefresh: onRefresh!,
            child: scroll,
          );
    return AmbientBackground(
      lights: lights,
      child: footer == null
          ? body
          : Column(
              children: [
                Expanded(child: body),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.s, YqSpace.gutter, YqSpace.m),
                    child: footer,
                  ),
                ),
              ],
            ),
    );
  }
}

/// A section heading inside the canvas body.
class YqHeading extends StatelessWidget {
  const YqHeading(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: YqSpace.m, top: YqSpace.s),
        child: Row(
          children: [
            Expanded(child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium))),
            if (action != null) action!,
          ],
        ),
      );
}
