import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
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
  await kv.write(seenWeekKey, last.startsOn);
  if (!context.mounted) return false;
  unawaited(showYqSheet<void>(context, builder: (_) => WeekResultSheet(lastWeek: last, current: league)));
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.cmWeekEnded, textAlign: TextAlign.center, style: text.titleLarge)),
        const SizedBox(height: YqSpace.s),
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
