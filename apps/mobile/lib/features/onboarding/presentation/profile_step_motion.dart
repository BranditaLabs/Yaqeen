import 'package:flutter/material.dart';

import '../../../core/design/motion.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_count.dart';
import '../../../core/widgets/yq_once.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../profile/domain/avatar.dart';
import '../../profile/domain/level.dart';

/// The «how it works» illustrations of onboarding step 05·ج «ملفّك» (design §8): each plays once
/// per visit, when it scrolls into view, and rests on the honest state — everyone starts at level
/// one, nobody is in a league until they switch it on. Decorative (the copy beside them says it),
/// so they are hidden from screen readers; still under reduce-motion.

/// A small ring that fills while the numeral climbs through the six levels and their dots light
/// one by one; then it settles back to where everyone starts (level 1, an empty ring).
class LevelsDemo extends StatefulWidget {
  const LevelsDemo({super.key, required this.play});

  /// Starts the fill (the card has scrolled into view).
  final bool play;

  static const fill = Duration(milliseconds: 1500);
  static const hold = Duration(milliseconds: 450);
  static const settle = Duration(milliseconds: 550);

  @override
  State<LevelsDemo> createState() => _LevelsDemoState();
}

class _LevelsDemoState extends State<LevelsDemo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: LevelsDemo.fill + LevelsDemo.hold + LevelsDemo.settle);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void didUpdateWidget(LevelsDemo old) {
    super.didUpdateWidget(old);
    _maybeStart();
  }

  void _maybeStart() {
    if (_started || !widget.play || reduceMotion(context)) return;
    _started = true;
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// The ring's fill at controller value [t]: up through the six levels, a beat, then back to 0.
  double _fill(double t) {
    final total = _c.duration!.inMicroseconds;
    final up = LevelsDemo.fill.inMicroseconds / total;
    final hold = (LevelsDemo.fill + LevelsDemo.hold).inMicroseconds / total;
    if (t <= 0 || t >= 1) return 0;
    if (t < up) return Motion.emphasisedCurve.transform(t / up);
    if (t < hold) return 1;
    return 1 - Curves.easeInOutCubic.transform((t - hold) / (1 - hold));
  }

  @override
  Widget build(BuildContext context) {
    final count = cardLevels.length;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _fill(_c.value);
            final lit = 1 + (v * (count - 1)).floor();
            return Row(
              children: [
                YqRing(
                  value: v,
                  size: 40,
                  stroke: 3,
                  color: YqColors.lapis,
                  track: YqColors.lapis100.withValues(alpha: 0.5),
                  change: Duration.zero,
                  child: Text(
                    YqFormat.number(lit),
                    key: const ValueKey('levels-demo-numeral'),
                    textScaler: TextScaler.noScaling,
                    style: tabular(YqText.numeral.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: YqColors.ink)),
                  ),
                ),
                const SizedBox(width: YqSpace.m),
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    key: ValueKey('levels-demo-dot-$i'),
                    duration: Motion.quick,
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: i < lit ? YqColors.lapis : YqColors.line),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A miniature league: two quiet neighbour rows (shapes, never people) around the person's own
/// row — their picture, the name they typed and «أنت» — sliding in from the reading side when it
/// scrolls into view. Switching the league on lights their row in lapis with one soft sheen.
class MiniLeagueCard extends StatelessWidget {
  const MiniLeagueCard({super.key, required this.play, required this.avatar, required this.name, required this.joined});

  final bool play;
  final AvatarRef avatar;
  final String? name;
  final bool joined;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    Widget neighbour(int rank, double width) => _MiniRow(
          rank: rank,
          leading: const _Dot(),
          title: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: width,
              height: 8,
              decoration: BoxDecoration(color: YqColors.line, borderRadius: BorderRadius.circular(YqRadii.pill)),
            ),
          ),
        );
    final mine = _MiniRow(
      rank: 2,
      tint: joined,
      leading: YqAvatarSwap(avatar: avatar, size: 24, name: name, rim: false),
      title: Row(
        children: [
          Flexible(
            child: Text(
              (name?.trim().isNotEmpty ?? false) ? name!.trim() : t.obNameHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: joined ? YqColors.ink : YqColors.muted),
            ),
          ),
          const SizedBox(width: YqSpace.xs),
          AnimatedOpacity(
            opacity: joined ? 1 : 0.45,
            duration: motionOr(context, Motion.standard),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: YqColors.lapis.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(YqRadii.pill)),
              child: Text(t.cmYou, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: YqColors.lapis)),
            ),
          ),
        ],
      ),
    );
    return ExcludeSemantics(
      child: _Arrive(
        play: play,
        // From the end of the reading line toward its start.
        from: Offset(rtl ? -0.25 : 0.25, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.s, vertical: YqSpace.xs),
          decoration: BoxDecoration(
            color: YqColors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(YqRadii.chip),
            border: Border.all(color: YqColors.line),
          ),
          child: Column(
            children: [
              neighbour(1, 72),
              YqSheen(key: ValueKey('mini-league-sheen-$joined'), play: joined, color: YqColors.lapis, opacity: 0.16, radius: YqRadii.chip, child: mine),
              neighbour(3, 52),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({required this.rank, required this.leading, required this.title, this.tint = false});
  final int rank;
  final Widget leading;
  final Widget title;
  final bool tint;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: motionOr(context, Motion.standard),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.s),
        decoration: BoxDecoration(
          color: tint ? YqColors.lapis.withValues(alpha: 0.07) : YqColors.lapis.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(YqRadii.chip),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                YqFormat.number(rank),
                textScaler: TextScaler.noScaling,
                style: YqText.numeral.copyWith(fontSize: 11, color: YqColors.muted),
              ),
            ),
            const SizedBox(width: YqSpace.xs),
            SizedBox.square(dimension: 24, child: Center(child: leading)),
            const SizedBox(width: YqSpace.s),
            Expanded(child: title),
          ],
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: YqColors.line),
      );
}

/// Slides [child] in from [from] (a fraction of its size) with a fade once [play] turns on;
/// hidden until then. At rest under reduce-motion.
class _Arrive extends StatefulWidget {
  const _Arrive({required this.play, required this.from, required this.child});
  final bool play;
  final Offset from;
  final Widget child;

  @override
  State<_Arrive> createState() => _ArriveState();
}

class _ArriveState extends State<_Arrive> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.emphasised + const Duration(milliseconds: 150));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (widget.play && _c.isDismissed) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(_Arrive old) {
    super.didUpdateWidget(old);
    if (widget.play && !old.play && _c.isDismissed) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = Motion.emphasisedCurve.transform(_c.value);
          return Opacity(
            opacity: Curves.easeOut.transform(_c.value),
            child: FractionalTranslation(translation: widget.from * (1 - t), child: child),
          );
        },
      );
}

/// The preset tiles arriving: each pops in (scale from 0.85 with a fade) [step] after the one
/// before, when the grid first builds on this visit. A tile that is rebuilt later (a filter
/// change reusing its place) does not replay: the animation only ever runs toward the same end.
class PresetCascade extends StatelessWidget {
  const PresetCascade({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  static const step = Duration(milliseconds: 30);

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    final delay = step * index.clamp(0, 20);
    final total = delay + Motion.emphasised;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: Motion.popCurve),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        alwaysIncludeSemantics: true,
        child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
      ),
    );
  }
}
