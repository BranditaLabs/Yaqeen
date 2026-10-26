import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/public_card.dart';

/// The owner's private journey (GET /v1/me/journey). Online; the section hides itself offline.
final myJourneyProvider = FutureProvider.autoDispose((ref) => ref.watch(cardRepositoryProvider).journey());

/// One milestone as a neutral phrase — the same wording the public page uses (no worship detail).
String journeyLabel(AppLocalizations t, JourneyEvent e, String locale) {
  final v = e.value ?? 0;
  return switch (e.kind) {
    JourneyKind.joined => t.journeyJoined,
    JourneyKind.challengeStart => t.journeyChallengeStart,
    JourneyKind.challengeDay => t.journeyChallengeDay(YqFormat.number(v)),
    JourneyKind.level => t.journeyLevel(levelName(v, locale)),
    JourneyKind.badge => t.journeyBadge(v),
  };
}

String levelName(int level, String locale) {
  final l = cardLevels[(level - 1).clamp(0, cardLevels.length - 1)];
  return locale == 'ar' ? l.$2 : l.$3;
}

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// A number that counts up to [value] (and glides between values when it changes).
/// Screen readers get the final value at once.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, this.style, this.builder});
  final int value;
  final TextStyle? style;

  /// Wraps the formatted number in a sentence, e.g. «{n} نقطة».
  final String Function(String n)? builder;

  @override
  Widget build(BuildContext context) {
    String text(num v) => builder == null ? YqFormat.number(v.round()) : builder!(YqFormat.number(v.round()));
    if (_still(context)) return Text(text(value), style: style);
    return Semantics(
      label: text(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: Duration(milliseconds: 700 + math.min(value, 600)),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(text(v), style: style),
      ),
    );
  }
}

/// Dated milestones on a rail that draws itself: each row rises, its dot springs in, then the
/// thread runs on to the next. Newest first. [night] for the dark card look.
class JourneyRail extends StatefulWidget {
  const JourneyRail({super.key, required this.events, this.night = false, this.dense = false});
  final List<JourneyEvent> events;
  final bool night;
  final bool dense;

  @override
  State<JourneyRail> createState() => _JourneyRailState();
}

class _JourneyRailState extends State<JourneyRail> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: _duration(widget.events.length));

  static Duration _duration(int n) => Duration(milliseconds: 650 + 130 * math.min(n, 8));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _c.value = 1;
    } else if (_c.isDismissed) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(JourneyRail old) {
    super.didUpdateWidget(old);
    // Rows added by «show all» play in from where the rail already is.
    if (widget.events.length != old.events.length && !_still(context)) {
      _c.duration = _duration(widget.events.length);
      _c.forward(from: math.min(_c.value, old.events.length / math.max(widget.events.length, 1)));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.events.length;
    final step = n <= 1 ? 0.0 : math.min(0.12, 0.55 / (n - 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < n; i++)
          _Row(
            event: widget.events[i],
            first: i == 0,
            last: i == n - 1,
            night: widget.night,
            dense: widget.dense,
            animation: _c,
            start: i * step,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.event,
    required this.first,
    required this.last,
    required this.night,
    required this.dense,
    required this.animation,
    required this.start,
  });
  final JourneyEvent event;
  final bool first;
  final bool last;
  final bool night;
  final bool dense;
  final Animation<double> animation;
  final double start;

  static const _dot = 28.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final title = journeyLabel(t, event, locale);
    final date = YqFormat.fullDate(event.date, locale);
    final rise = CurvedAnimation(parent: animation, curve: Interval(start, math.min(1, start + 0.4), curve: Curves.easeOutCubic));
    final pop = CurvedAnimation(parent: animation, curve: Interval(math.min(1, start + 0.05), math.min(1, start + 0.45), curve: Curves.elasticOut));
    final draw = CurvedAnimation(parent: animation, curve: Interval(math.min(1, start + 0.15), math.min(1, start + 0.55), curve: YqMotion.ease));
    final thread = night ? const Color(0x33FFFFFF) : YqColors.line;
    final gap = dense ? YqSpace.m : YqSpace.l;

    return Semantics(
      container: true,
      label: '$title، $date',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The thread: from this dot down to the next one.
          if (!last)
            PositionedDirectional(
              start: _dot / 2 - 1,
              top: _dot / 2,
              bottom: -_dot / 2,
              width: 2,
              child: AnimatedBuilder(
                animation: draw,
                builder: (context, _) => Align(
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(
                    widthFactor: 1,
                    heightFactor: draw.value.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [event.golden ? YqColors.gold : YqColors.lapis300, thread],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(bottom: last ? 0 : gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScaleTransition(scale: pop, child: _Dot(kind: event.kind, night: night, size: _dot)),
                const SizedBox(width: YqSpace.m),
                Expanded(
                  child: FadeTransition(
                    opacity: rise,
                    child: AnimatedBuilder(
                      animation: rise,
                      builder: (context, child) => Transform.translate(offset: Offset(0, 10 * (1 - rise.value)), child: child),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: dense ? 13 : 14.5,
                                height: 1.45,
                                fontWeight: FontWeight.w700,
                                color: night ? YqColors.white : YqColors.ink,
                              ),
                            ),
                            Text(date, style: TextStyle(fontSize: dense ? 11 : 12, color: night ? YqColors.navy200 : YqColors.muted)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.kind, required this.night, required this.size});
  final JourneyKind kind;
  final bool night;
  final double size;

  @override
  Widget build(BuildContext context) {
    final golden = kind == JourneyKind.level || kind == JourneyKind.badge;
    final accent = night ? YqColors.goldLight : YqColors.lapis;
    final Widget mark = switch (kind) {
      JourneyKind.level => Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(colors: [YqColors.goldLight, YqColors.gold]),
            ),
          ),
        ),
      JourneyKind.badge => Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: YqColors.gold, width: 2.5)),
        ),
      JourneyKind.challengeDay => Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: accent)),
      JourneyKind.challengeStart => Icon(Icons.flag_rounded, size: 14, color: accent),
      JourneyKind.joined => Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: YqColors.goldLight,
            boxShadow: [BoxShadow(color: Color(0xB3E9D49E), blurRadius: 8, spreadRadius: 1)],
          ),
        ),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: golden || kind == JourneyKind.joined ? null : (night ? YqColors.navy : YqColors.porcelain),
        gradient: golden
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [YqColors.cream, YqColors.sand])
            : kind == JourneyKind.joined
                ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [YqColors.lapis500, YqColors.navy])
                : null,
        border: Border.all(
          color: golden ? YqColors.gold : (kind == JourneyKind.joined ? YqColors.navy : (night ? YqColors.lapis300 : YqColors.lapis500)),
          width: 2,
        ),
        boxShadow: golden ? const [BoxShadow(color: Color(0x40E9D49E), spreadRadius: 5)] : null,
      ),
      child: mark,
    );
  }
}

/// Profile tab: where the user stands (level ring, lifetime points, to-next) and every milestone
/// so far. Private — the public card shows the rail only when its switch is on.
class JourneySection extends ConsumerStatefulWidget {
  const JourneySection({super.key});

  static const preview = 5;

  @override
  ConsumerState<JourneySection> createState() => _JourneySectionState();
}

class _JourneySectionState extends ConsumerState<JourneySection> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final journey = ref.watch(myJourneyProvider);
    final Widget body;
    switch (journey) {
      case AsyncData(:final value):
        body = _content(context, t, locale, value);
      case AsyncError():
        return const SizedBox.shrink();
      default:
        body = const LiquidGlass(radius: YqRadii.hero, child: YqSkeletonRows(rows: 3, leading: 28));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YqHeading(t.journeyTitle),
        AnimatedSwitcher(duration: YqMotion.base, child: body),
        const SizedBox(height: YqSpace.xl),
      ],
    );
  }

  Widget _content(BuildContext context, AppLocalizations t, String locale, MyJourney j) {
    final events = _all ? j.events : j.events.take(JourneySection.preview).toList();
    final toNext = j.toNext;
    return LiquidGlass(
      key: const ValueKey('journey'),
      radius: YqRadii.hero,
      padding: const EdgeInsets.fromLTRB(YqSpace.l, YqSpace.l, YqSpace.l, YqSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              YqRing(
                value: j.level.progress,
                gold: true,
                size: 84,
                stroke: 5,
                child: Text(YqFormat.number(j.level.level), style: YqMoment.numeral(size: 30, color: YqColors.goldDeep)),
              ),
              const SizedBox(width: YqSpace.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(j.level.name(locale), style: YqMoment.display(context, size: 24)),
                    CountUp(
                      value: j.lifetimePoints,
                      builder: t.journeyLifetime,
                      style: const TextStyle(fontSize: 13, color: YqColors.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toNext == null ? t.journeyTop : t.journeyToNext(YqFormat.number(toNext), levelName(j.level.level + 1, locale)),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: YqColors.goldText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.l),
          if (j.events.isEmpty)
            Text(t.journeyEmpty, style: const TextStyle(fontSize: 13, color: YqColors.muted))
          else
            AnimatedSize(
              duration: YqMotion.slow,
              curve: YqMotion.ease,
              alignment: Alignment.topCenter,
              child: JourneyRail(events: events),
            ),
          if (j.events.length > JourneySection.preview)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? t.journeyShowLess : t.journeyShowAll),
              ),
            )
          else
            const SizedBox(height: YqSpace.s),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 14, color: YqColors.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(t.journeyPrivate, style: const TextStyle(fontSize: 11.5, color: YqColors.muted))),
            ],
          ),
        ],
      ),
    );
  }
}
