import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../profile/domain/me_profile.dart';
import '../../profile/presentation/me_profile_controller.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'badge_label.dart';
import 'community_providers.dart';
import 'community_widgets.dart';
import 'join_sheets.dart';
import 'report_sheet.dart';
import 'week_result_sheet.dart';

/// `/profile/leagues` (APP_SPEC §5.31.1, design §6.6): the weekly league.
///
/// Rows are the server's nightly snapshot (ranks shared on ties, «—» for null/0); the caller's own
/// live week points appear only in the stage caption. Leaving is queued and immediate here.
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key});

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowWeekResult(context, ref);
    });
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(leagueProvider)
      ..invalidate(leagueHistoryProvider);
    await ref.read(meProfileProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final flagOn = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.leagues)));
    final account = ref.watch(sessionProvider.select((s) => s.canEarnPoints));
    final bar = YqStageBar(back: true, title: t.cmLeagueTitle);

    if (!flagOn) return _Simple(bar: bar, child: YqEmptyState(icon: YqIcons.league, title: t.cmFeatureOff));
    if (!account) {
      return _Simple(
        bar: bar,
        footer: true,
        child: CommunityNote(
          icon: YqIcons.league,
          title: t.cmGuest,
          body: t.cmJoinLeagueBody,
          actionLabel: t.cmJoin,
          onAction: () => showSignInSheet(context),
        ),
      );
    }
    final profile = ref.watch(meProfileProvider).valueOrNull;
    if (profile?.community.banned ?? false) return _Simple(bar: bar, child: CommunityNote(icon: YqIcons.lock, title: t.cmBanned));

    final async = ref.watch(leagueProvider);
    final error = async.error;
    if (error is CommunityException) {
      return switch (error.failure) {
        CommunityFailure.featureOff => _Simple(bar: bar, child: YqEmptyState(icon: YqIcons.league, title: t.cmFeatureOff)),
        CommunityFailure.communityBanned => _Simple(bar: bar, child: CommunityNote(icon: YqIcons.lock, title: t.cmBanned)),
        _ => _Simple(bar: bar, child: YqErrorState(onRetry: () => ref.invalidate(leagueProvider))),
      };
    }
    final fresh = async.valueOrNull;
    if (fresh == null) {
      if (async.hasError) return _Simple(bar: bar, child: YqErrorState(onRetry: () => ref.invalidate(leagueProvider)));
      return const _Loading();
    }
    var league = fresh.value;
    // Left on this phone (queued): hidden at once, whatever the server still says.
    if (league is LeagueJoined && profile != null && profile.handle != null && !profile.community.leagues) league = const LeagueOff();

    return switch (league) {
      LeagueOff() => _Simple(
          bar: bar,
          offline: fresh.offline,
          footer: true,
          onRefresh: _refresh,
          child: CommunityNote(
            icon: YqIcons.league,
            title: t.cmJoinLeagueTitle,
            body: t.cmJoinLeagueBody,
            actionLabel: t.cmJoin,
            onAction: () => showJoinLeagueSheet(context),
          ),
        ),
      LeagueClosing() => _Simple(
          bar: bar,
          offline: fresh.offline,
          onRefresh: _refresh,
          child: CommunityNote(icon: YqIcons.league, title: t.cmClosing),
        ),
      final LeagueJoined j => _Joined(league: j, offline: fresh.offline, profile: profile, onRefresh: _refresh),
    };
  }
}

/// A compact stage with one body block (states).
class _Simple extends StatelessWidget {
  const _Simple({required this.bar, required this.child, this.offline = false, this.footer = false, this.onRefresh});
  final Widget bar;
  final Widget child;
  final bool offline;
  final bool footer;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: YqColors.porcelain,
        body: YqCanvas(
          onRefresh: onRefresh,
          stage: YqStage(compact: true, child: bar),
          children: [
            YqOfflineBanner(offline: offline),
            child,
            if (footer) const CommunityFooter(),
          ],
        ),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(
          compact: true,
          child: Column(
            children: [
              YqStageBar(back: true, title: t.cmLeagueTitle),
              const SizedBox(height: YqSpace.l),
              const YqSkeleton(
                child: Column(
                  children: [
                    YqSkeletonBox(width: 64, height: 12, radius: YqRadii.pill),
                    SizedBox(height: YqSpace.s),
                    YqSkeletonBox(width: 72, height: 44),
                    SizedBox(height: YqSpace.s),
                    YqSkeletonBox(width: 140, height: 12, radius: YqRadii.pill),
                  ],
                ),
              ),
            ],
          ),
        ),
        children: const [CompetitorSkeleton(rows: 8)],
      ),
    );
  }
}

/// One entry of the lazy list: a person, or a zone separator before them.
sealed class _Entry {
  const _Entry();
}

class _RowEntry extends _Entry {
  const _RowEntry(this.c);
  final PublicCompetitor c;
}

class _ZoneEntry extends _Entry {
  const _ZoneEntry(this.label);
  final String label;
}

/// The promote zone is everyone ranked within it (ties at the boundary all move up; 0 points never
/// does); the demote zone is the last [LeagueJoined.demoteZone] places. Zones of 0 draw no label.
List<_Entry> _leagueEntries(LeagueJoined l, List<PublicCompetitor> rows, {required String? next, required String? prev, required AppLocalizations t}) {
  final up = l.promoteZone > 0 ? rows.where((r) => r.rank != null && r.rank! <= l.promoteZone).length : 0;
  final downFrom = l.demoteZone > 0 ? (rows.length - l.demoteZone).clamp(up, rows.length) : rows.length;
  final out = <_Entry>[];
  for (var i = 0; i < rows.length; i++) {
    if (i == 0 && up > 0 && next != null) out.add(_ZoneEntry(t.cmPromoteZone(next)));
    if (i == downFrom && prev != null && l.demoteZone > 0) out.add(_ZoneEntry(t.cmDemoteZone(prev)));
    out.add(_RowEntry(rows[i]));
    // The line closing the promote zone.
    if (i == up - 1 && up > 0 && next != null && i != rows.length - 1) out.add(const _ZoneEntry(''));
  }
  return out;
}

class _Joined extends ConsumerWidget {
  const _Joined({required this.league, required this.offline, required this.profile, required this.onRefresh});
  final LeagueJoined league;
  final bool offline;
  final MeProfile? profile;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final now = ref.watch(clockProvider)();
    final hidden = ref.watch(hiddenHandlesProvider);
    final rows = [for (final r in league.rows) if (!hidden.contains(r.handle)) r];
    final days = daysLeft(league.endsAt, now);
    final myRank = league.rows.where((r) => r.me).firstOrNull?.rank ?? profile?.league?.rank;
    final division = divisionName(league.division, t, custom: league.divisionName(locale));
    final entries = _leagueEntries(league, rows, next: league.nextName(locale), prev: league.prevName(locale), t: t);

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        onRefresh: onRefresh,
        stage: YqStage(
          compact: true,
          child: Column(
            children: [
              YqStageBar(back: true, title: t.cmLeagueTitle, subtitle: days <= 0 ? t.cmEndsTonight : t.cmEndsInDays(days)),
              const SizedBox(height: YqSpace.l),
              CommunityMoment(
                eyebrow: division,
                value: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : YqMotion.base,
                  child: Text(rankText(myRank, t), key: ValueKey(myRank), style: YqMoment.numeral()),
                ),
                caption: t.cmWeekPoints(YqFormat.number(league.myLivePoints)),
              ),
            ],
          ),
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(padding: const EdgeInsets.only(top: YqSpace.xl), child: YqOfflineBanner(offline: offline)),
          ),
          if (rows.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: YqSpace.l),
                child: Text(t.cmLeagueEmpty, textAlign: TextAlign.center, style: const TextStyle(color: YqColors.muted)),
              ),
            )
          else
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) => switch (entries[i]) {
                _ZoneEntry(:final label) when label.isEmpty => const Padding(
                    padding: EdgeInsets.symmetric(vertical: YqSpace.xs),
                    child: Divider(color: YqColors.line, height: 1),
                  ),
                _ZoneEntry(:final label) => ZoneLabel(label),
                _RowEntry(:final c) => CompetitorRow(
                    key: ValueKey(c.handle),
                    competitor: c,
                    onLongPress: c.me ? null : () => showReportSheet(context, c),
                  ),
              },
            ),
          const SliverToBoxAdapter(child: SnapshotLine()),
          const SliverToBoxAdapter(child: _History()),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CommunityFooter(),
                const SizedBox(height: YqSpace.m),
                YqButton.secondary(
                  label: t.cmLeaveLeague,
                  onPressed: () async {
                    final ok = await confirmLeave(context, title: t.cmLeaveLeague, body: t.cmLeaveLeagueBody);
                    if (ok) await leaveLeague(ref);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «الأسابيع السابقة».
class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final async = ref.watch(leagueHistoryProvider);
    final items = async.valueOrNull?.value;
    if (items == null) {
      if (async.hasError) return const SizedBox.shrink();
      return const Padding(
        padding: EdgeInsets.only(top: YqSpace.l),
        child: YqSkeleton(child: YqSkeletonRows(rows: 2, leading: 0)),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: YqSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YqHeading(t.cmPastWeeks),
          YqGroup(
            children: [
              for (final w in items)
                YqListRow(
                  dense: true,
                  title: '${YqFormat.dayMonth(DateTime.parse(w.startsOn), locale)} · ${divisionName(w.division, t)}',
                  subtitle: [
                    t.cmHistoryRank(rankText(w.rank, t), YqFormat.number(w.size)),
                    if (w.outcome != null)
                      switch (w.outcome!) {
                        LeagueOutcome.up => t.cmOutcomeUp,
                        LeagueOutcome.stay => t.cmOutcomeStay,
                        LeagueOutcome.down => t.cmOutcomeDown,
                      },
                  ].join(' · '),
                  trailing: Text(pointsText(w.points, t), style: const TextStyle(color: YqColors.muted)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
