import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/time/zoned.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'community_providers.dart';
import 'community_widgets.dart';

/// `/profile/tournaments` (APP_SPEC §5.31.2, design §6.7): live, upcoming and ended tournaments.
class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  TournamentPhase _phase = TournamentPhase.live;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final flagOn = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.tournaments)));
    final account = ref.watch(sessionProvider.select((s) => s.canEarnPoints));
    final bar = YqStageBar(back: true, title: t.cmTournaments);

    Widget canvas(List<Widget> children, {Future<void> Function()? onRefresh}) => Scaffold(
          backgroundColor: YqColors.porcelain,
          body: YqCanvas(
            onRefresh: onRefresh,
            stage: YqStage(compact: true, child: bar),
            children: children,
          ),
        );

    if (!flagOn) return canvas([YqEmptyState(icon: YqIcons.trophy, title: t.cmFeatureOff)]);
    if (!account) {
      return canvas([
        CommunityNote(icon: YqIcons.trophy, title: t.cmGuest, actionLabel: t.cmJoin, onAction: () => showSignInSheet(context)),
        const CommunityFooter(),
      ]);
    }

    final async = ref.watch(tournamentsProvider);
    final error = async.error;
    if (error is CommunityException && error.failure == CommunityFailure.featureOff) {
      return canvas([YqEmptyState(icon: YqIcons.trophy, title: t.cmFeatureOff)]);
    }
    final fresh = async.valueOrNull;
    final segmented = YqSegmented<TournamentPhase>(
      segments: [(TournamentPhase.live, t.cmLive), (TournamentPhase.upcoming, t.cmUpcoming), (TournamentPhase.ended, t.cmEnded)],
      selected: _phase,
      onChanged: (p) => setState(() => _phase = p),
    );
    if (fresh == null) {
      if (async.hasError) return canvas([YqErrorState(onRetry: () => ref.invalidate(tournamentsProvider))]);
      return canvas([
        segmented,
        const SizedBox(height: YqSpace.l),
        const YqSkeleton(
          child: Column(
            children: [
              YqSkeletonBox(height: 120, radius: YqRadii.card),
              SizedBox(height: YqSpace.m),
              YqSkeletonBox(height: 120, radius: YqRadii.card),
            ],
          ),
        ),
      ]);
    }
    final list = fresh.value.where((x) => x.phase == _phase).toList();
    Future<void> refresh() async => ref.invalidate(tournamentsProvider);
    return canvas(
      onRefresh: refresh,
      [
        YqOfflineBanner(offline: fresh.offline),
        segmented,
        const SizedBox(height: YqSpace.l),
        if (list.isEmpty)
          YqEmptyState(icon: YqIcons.trophy, title: t.cmTournamentsEmpty)
        else
          for (final x in list) ...[TournamentCard(tournament: x), const SizedBox(height: YqSpace.m)],
        const CommunityFooter(),
      ],
    );
  }
}

/// «19 أكتوبر – 9 نوفمبر 2026»: the whole Cairo days of the window (ends are exclusive midnights).
String tournamentWindow(Tournament x, String locale) {
  final first = cairoDay(x.startsAt);
  final last = Zoned.addDays(cairoDay(x.endsAt), -1);
  final from = first.year == last.year ? YqFormat.dayMonth(first, locale) : YqFormat.fullDate(first, locale);
  return '$from – ${YqFormat.fullDate(last, locale)}';
}

/// «تنتهي بعد {days} أيام» / «تبدأ بعد {days} أيام» / «انتهت».
String tournamentStatus(Tournament x, DateTime now, AppLocalizations t) {
  if (x.phase == TournamentPhase.ended || x.closed) return t.cmEnded;
  if (x.phase == TournamentPhase.upcoming) {
    final d = Zoned.daysBetween(cairoToday(now), cairoDay(x.startsAt));
    return t.cmTStartsInDays(d < 1 ? 1 : d);
  }
  final d = daysLeft(x.endsAt, now);
  return d <= 0 ? t.cmTEndsTonight : t.cmTEndsInDays(d);
}

class TournamentCard extends ConsumerWidget {
  const TournamentCard({super.key, required this.tournament});
  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final now = ref.watch(clockProvider)();
    final x = tournament;
    final title = x.title(locale);
    final status = tournamentStatus(x, now, t);
    final window = tournamentWindow(x, locale);
    final participants = t.cmParticipants(YqFormat.number(x.participants));
    return GlassTap(
      semanticLabel: [title, window, status, participants, if (x.joined) t.cmJoined].join('، '),
      onTap: () => context.push('/profile/tournaments/${x.id}'),
      child: LiquidGlass(
        padding: const EdgeInsets.all(YqSpace.l),
        child: Row(
          children: [
            const YqIcon(YqIcons.trophy, size: 28, tone: YqIconTone.active),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(window, style: text.bodySmall),
                  const SizedBox(height: YqSpace.s),
                  Wrap(
                    spacing: YqSpace.s,
                    runSpacing: YqSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // A live tournament's status breathes a little (a few slow breaths, then lit).
                      if (x.phase == TournamentPhase.live && !x.closed)
                        LivePill(label: status, style: text.bodySmall?.copyWith(color: YqColors.ink, fontWeight: FontWeight.w600))
                      else
                        Text(status, style: text.bodySmall?.copyWith(color: YqColors.ink, fontWeight: FontWeight.w600)),
                      Text('·', style: text.bodySmall),
                      Text(participants, style: text.bodySmall),
                      if (x.joined)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: YqSpace.s, vertical: 2),
                          decoration: BoxDecoration(
                            color: YqColors.lapis.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(YqRadii.pill),
                          ),
                          child: Text(t.cmJoined, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: YqColors.lapis)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: YqColors.muted),
          ],
        ),
      ),
    );
  }
}
