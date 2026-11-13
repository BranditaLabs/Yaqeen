import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../profile/presentation/me_profile_controller.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'community_providers.dart';
import 'community_widgets.dart';
import 'join_sheets.dart';
import 'report_sheet.dart';
import 'tournaments_screen.dart';

/// `/profile/tournaments/:id` (APP_SPEC §5.31.2, design §6.7): one tournament and its paged
/// snapshot standings. The caller's live points appear only in the stage caption.
class TournamentScreen extends ConsumerWidget {
  const TournamentScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final flagOn = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.tournaments)));
    final account = ref.watch(sessionProvider.select((s) => s.canEarnPoints));

    Widget simple(Widget child, {String? title}) => Scaffold(
          backgroundColor: YqColors.porcelain,
          body: YqCanvas(
            stage: YqStage(compact: true, child: YqStageBar(back: true, title: title ?? t.cmTournaments)),
            children: [child],
          ),
        );

    if (!flagOn) return simple(YqEmptyState(icon: YqIcons.trophy, title: t.cmFeatureOff));
    if (!account) {
      return simple(
        CommunityNote(icon: YqIcons.trophy, title: t.cmGuest, actionLabel: t.cmJoin, onAction: () => showSignInSheet(context)),
      );
    }
    if (ref.watch(meProfileProvider.select((p) => p.valueOrNull?.community.banned ?? false))) {
      return simple(CommunityNote(icon: YqIcons.lock, title: t.cmBanned));
    }

    final async = ref.watch(tournamentProvider(id));
    final error = async.error;
    if (error is CommunityException && error.failure == CommunityFailure.featureOff) {
      return simple(YqEmptyState(icon: YqIcons.trophy, title: t.cmFeatureOff));
    }
    final fresh = async.valueOrNull;
    if (fresh == null) {
      if (async.hasError) return simple(YqErrorState(onRetry: () => ref.invalidate(tournamentProvider(id))));
      return const _Loading();
    }
    return _Body(tournament: fresh.value, offline: fresh.offline);
  }
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
              YqStageBar(back: true, title: t.cmTournaments),
              const SizedBox(height: YqSpace.l),
              const YqSkeleton(
                child: Column(
                  children: [
                    YqSkeletonBox(width: 90, height: 12, radius: YqRadii.pill),
                    SizedBox(height: YqSpace.s),
                    YqSkeletonBox(width: 72, height: 44),
                    SizedBox(height: YqSpace.s),
                    YqSkeletonBox(width: 150, height: 12, radius: YqRadii.pill),
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

class _Body extends ConsumerWidget {
  const _Body({required this.tournament, required this.offline});
  final Tournament tournament;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final now = ref.watch(clockProvider)();
    final x = tournament;
    final open = x.joinOpen(now);
    final ended = x.phase == TournamentPhase.ended || x.closed;
    final body = x.body(locale).trim();

    Future<void> join() async {
      await showJoinTournamentSheet(context, x.id);
    }

    final Widget moment;
    if (x.joined) {
      final me = x.me;
      moment = CommunityMoment(
        eyebrow: tournamentStatus(x, now, t),
        value: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : YqMotion.base,
          child: Text(rankText(me?.rank, t), key: ValueKey(me?.rank), style: YqMoment.numeral()),
        ),
        caption: t.cmTournamentPoints(YqFormat.number(me?.points ?? 0)),
      );
    } else if (open) {
      moment = CommunityMoment(
        eyebrow: tournamentStatus(x, now, t),
        // The moment itself invites; the one primary button stays in the body.
        value: Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: join,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: YqSpace.touch, minWidth: YqSpace.touch),
              child: Text(t.cmJoin, style: YqMoment.display(context, size: 34).copyWith(color: YqColors.lapis)),
            ),
          ),
        ),
      );
    } else {
      moment = CommunityMoment(
        eyebrow: tournamentStatus(x, now, t),
        value: Text(ended ? t.cmEnded : t.cmJoinClosed, style: YqMoment.display(context, size: 26)),
      );
    }

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        onRefresh: () async {
          ref
            ..invalidate(tournamentProvider(x.id))
            ..invalidate(standingsProvider(x.id));
        },
        stage: YqStage(
          compact: true,
          child: Column(
            children: [
              YqStageBar(back: true, title: x.title(locale), subtitle: tournamentWindow(x, locale)),
              const SizedBox(height: YqSpace.l),
              moment,
            ],
          ),
        ),
        slivers: [
          if (x.phase != TournamentPhase.upcoming) ..._standings(context, ref, x),
          const SliverToBoxAdapter(child: CommunityFooter()),
        ],
        children: [
          YqOfflineBanner(offline: offline),
          if (body.isNotEmpty) ...[Text(body, style: text.bodyMedium?.copyWith(height: 1.7)), const SizedBox(height: YqSpace.m)],
          Row(
            children: [
              const YqIcon(YqIcons.badge, size: 20, tone: YqIconTone.idle),
              const SizedBox(width: YqSpace.s),
              Expanded(child: Text(t.cmBadgeLabel(x.badge(locale)), style: text.bodyMedium)),
            ],
          ),
          const SizedBox(height: YqSpace.s),
          Text(t.cmParticipants(YqFormat.number(x.participants)), style: text.bodySmall),
          const SizedBox(height: YqSpace.l),
          if (x.joined) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                  decoration: BoxDecoration(
                    color: YqColors.lapis.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(YqRadii.pill),
                  ),
                  child: Text(t.cmJoined, style: const TextStyle(fontWeight: FontWeight.w700, color: YqColors.lapis)),
                ),
              ],
            ),
            if (!ended) ...[
              const SizedBox(height: YqSpace.m),
              YqButton.secondary(
                label: t.cmLeaveTournament,
                onPressed: () async {
                  final ok = await confirmLeave(context, title: t.cmLeaveTournament, body: t.cmLeaveTournamentBody);
                  if (ok) await leaveTournament(ref, x.id);
                },
              ),
            ],
          ] else if (open)
            YqButton(label: t.cmJoinTournament, onPressed: join)
          else if (!ended)
            Text(t.cmJoinClosed, style: text.bodyMedium?.copyWith(color: YqColors.muted)),
        ],
      ),
    );
  }

  List<Widget> _standings(BuildContext context, WidgetRef ref, Tournament x) {
    final async = ref.watch(standingsProvider(x.id));
    final page = async.valueOrNull;
    if (page == null) {
      if (async.hasError) {
        return [
          SliverToBoxAdapter(
            child: YqErrorState(onRetry: () => ref.invalidate(standingsProvider(x.id))),
          ),
        ];
      }
      return const [
        SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: YqSpace.xl), child: CompetitorSkeleton(rows: 6))),
      ];
    }
    final hidden = ref.watch(hiddenHandlesProvider);
    final rows = [for (final r in page.rows) if (!hidden.contains(r.handle)) r];
    final closed = x.closed || x.phase == TournamentPhase.ended;
    return [
      const SliverToBoxAdapter(child: SizedBox(height: YqSpace.xl)),
      SliverList.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          // Near the end of what's loaded: fetch the next snapshot page.
          if (i >= rows.length - 5 && page.nextCursor != null && !page.loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(standingsProvider(x.id).notifier).loadMore());
          }
          final c = rows[i];
          return CompetitorRow(
            key: ValueKey(c.handle),
            competitor: c,
            podium: closed,
            onLongPress: c.me ? null : () => showReportSheet(context, c),
          );
        },
      ),
      if (page.loadingMore) const SliverToBoxAdapter(child: CompetitorSkeleton(rows: 2)),
      const SliverToBoxAdapter(child: SnapshotLine()),
    ];
  }
}
