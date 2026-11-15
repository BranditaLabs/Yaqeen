import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/design/motion.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_once.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../profile/domain/me_profile.dart';
import '../../profile/presentation/me_profile_controller.dart';
import 'badge_label.dart';

/// KV: the `startsOn` of the last week whose result was shown.
const seenWeekKey = 'community.seenWeek';

/// Shows «انتهى الأسبوع» once per finished week (from the cached profile, never waiting on the
/// network) and returns whether it showed. Home calls it after the first frame; so does the league.
///
/// No sheet when the person left that week (`outcome` null), when the leagues flag is off, or for
/// guests. Results are in-app only — never a push (rule 5).
Future<bool> maybeShowWeekResult(BuildContext context, WidgetRef ref) async {
  // Home and the league can both ask at once: only one caller reads, writes and shows.
  if (_weekResultInFlight) return false;
  _weekResultInFlight = true;
  try {
    return await _maybeShowWeekResult(context, ref);
  } finally {
    _weekResultInFlight = false;
  }
}

bool _weekResultInFlight = false;

Future<bool> _maybeShowWeekResult(BuildContext context, WidgetRef ref) async {
  if (!ref.read(sessionProvider).canEarnPoints) return false;
  if (!ref.read(remoteConfigProvider).isOn(Flags.leagues)) return false;
  // The profile's first value is the on-device cache (never the network): wait for it if the
  // screen opened before it was read.
  var profile = ref.read(meProfileProvider).valueOrNull;
  if (profile == null) {
    try {
      profile = await ref.read(meProfileProvider.future).timeout(const Duration(seconds: 2));
    } on Object {
      return false;
    }
    if (!context.mounted) return false;
  }
  final league = profile.league;
  final last = league?.lastWeek;
  if (league == null || last == null || last.outcome == null) return false;
  final kv = ref.read(kvStoreProvider);
  if (await kv.read(seenWeekKey) == last.startsOn) return false;
  // The caller may be gone after the reads (a screen popped quickly): then the week stays unseen
  // for the next caller. The sheet is pushed before the key is written, so it is never lost.
  if (!context.mounted) return false;
  unawaited(showYqSheet<void>(context, spring: true, builder: (_) => WeekResultSheet(lastWeek: last, current: league)));
  await kv.write(seenWeekKey, last.startsOn);
  return true;
}

class WeekResultSheet extends StatelessWidget {
  const WeekResultSheet({super.key, required this.lastWeek, this.current});
  final LeagueLastWeek lastWeek;

  /// The current placement: its division name is the admin's name in force for [LeagueLastWeek.newDivision].
  final LeagueSummary? current;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final c = current;
    final division = divisionName(
      lastWeek.newDivision,
      t,
      custom: c != null && c.division == lastWeek.newDivision ? c.divisionName(locale) : null,
    );
    final line = switch (lastWeek.outcome) {
      LeagueOutcome.up => t.cmMovedUp(division),
      LeagueOutcome.stay => t.cmStayed(division),
      _ => t.cmStartsIn(division),
    };
    final badge = lastWeek.badge;
    final rank = lastWeek.rank;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.cmWeekEnded, textAlign: TextAlign.center, style: text.titleLarge)),
        const SizedBox(height: YqSpace.l),
        // The outcome settles into place with an overshoot (the line below says it in words).
        Center(child: OutcomeGlyph(outcome: lastWeek.outcome ?? LeagueOutcome.stay)),
        if (rank != null && rank >= 1 && rank <= 3) ...[
          const SizedBox(height: YqSpace.l),
          WeekPodium(rank: rank),
        ],
        const SizedBox(height: YqSpace.m),
        Text(line, textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(color: YqColors.ink, height: 1.5)),
        if (badge != null) ...[
          const SizedBox(height: YqSpace.xl),
          // Gold only here: a badge was earned.
          Center(
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: YqColors.cream,
                border: Border.all(color: YqColors.gold, width: 2),
              ),
              child: const YqIcon(YqIcons.badge, size: 34, tone: YqIconTone.gold),
            ),
          ),
          const SizedBox(height: YqSpace.s),
          Text(
            badgeLabel(badge, t, locale),
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(color: YqColors.goldText, fontWeight: FontWeight.w700),
          ),
        ],
        const SizedBox(height: YqSpace.xl),
        YqButton(label: t.cmClose, onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// The week's outcome as a glyph that settles with a visible overshoot: up rises into place,
/// down sinks into place, staying simply lands. Lapis for up, ink for staying, muted for the
/// previous division — never red. Decorative: the sheet's line says it.
class OutcomeGlyph extends StatelessWidget {
  const OutcomeGlyph({super.key, required this.outcome});
  final LeagueOutcome outcome;

  static const size = 64.0;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (outcome) {
      LeagueOutcome.up => (Icons.arrow_upward_rounded, YqColors.lapis),
      LeagueOutcome.stay => (Icons.horizontal_rule_rounded, YqColors.ink),
      LeagueOutcome.down => (Icons.arrow_downward_rounded, YqColors.muted),
    };
    final from = switch (outcome) {
      LeagueOutcome.up => 14.0,
      LeagueOutcome.down => -14.0,
      LeagueOutcome.stay => 0.0,
    };
    final disc = Container(
      key: ValueKey('outcome-${outcome.name}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: YqColors.lapis.withValues(alpha: 0.07),
        border: Border.all(color: YqColors.white, width: 1.5),
      ),
      child: Icon(icon, size: 32, color: color),
    );
    if (reduceMotion(context)) return ExcludeSemantics(child: disc);
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.settleCurve.settle + const Duration(milliseconds: 120),
        // A beat after the sheet arrives, then the spring.
        curve: Interval(0.15, 1, curve: Motion.settleCurve),
        child: disc,
        builder: (context, v, child) => Opacity(
          opacity: (v * 2).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, from * (1 - v)),
            child: Transform.scale(scale: 0.6 + 0.4 * v, child: child),
          ),
        ),
      ),
    );
  }
}

/// A closed week's podium when the person finished in the top three: three steps (2 · 1 · 3)
/// rising in sequence — first, second, third — with the person's own step in lapis and «أنت».
/// Only their own place is named; the others are steps, never people.
class WeekPodium extends StatelessWidget {
  const WeekPodium({super.key, required this.rank});
  final int rank;

  static const heights = {1: 56.0, 2: 42.0, 3: 32.0};
  static const step = Duration(milliseconds: 140);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget place(int p) {
      final mine = p == rank;
      return Expanded(
        child: YqSlideIn(
          key: ValueKey('podium-$p'),
          offset: const Offset(0, 0.5),
          delay: Motion.emphasised + step * (p - 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 20,
                child: mine
                    ? Text(t.cmYou, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: YqColors.lapis))
                    : null,
              ),
              const SizedBox(height: YqSpace.xs),
              Container(
                height: heights[p],
                alignment: Alignment.center,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: mine ? YqColors.lapis : YqColors.line,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(YqRadii.chip)),
                ),
                child: Text(
                  YqFormat.number(p),
                  style: YqText.numeral.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: mine ? YqColors.white : YqColors.muted),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: t.cmPodiumPlace(YqFormat.number(rank)),
      excludeSemantics: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [place(2), place(1), place(3)]),
        ),
      ),
    );
  }
}
