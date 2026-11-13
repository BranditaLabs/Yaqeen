import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../profile/domain/me_profile.dart';
import '../../profile/presentation/me_profile_controller.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'community_providers.dart';
import 'community_widgets.dart';
import 'join_sheets.dart';
import 'report_sheet.dart';

/// The country's name from the bundled `assets/geo/cities.json`.
final countryNameProvider = FutureProvider.autoDispose.family<String, ({String code, String locale})>((ref, a) async {
  final cities = ref.watch(cityRepositoryProvider);
  await cities.all();
  return cities.countryName(a.code, a.locale);
});

/// `/profile/leaderboard` (APP_SPEC §5.31.3, design §6.8): the level board — rings only, never
/// points — worldwide and (its own opt-in) for the person's country.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  LeaderboardScope _scope = LeaderboardScope.global;
  bool _busy = false;
  String? _error;

  Future<void> _join({required bool country}) async {
    final attested = ref.read(meProfileProvider).valueOrNull?.community.attestedAdult ?? false;
    if (!attested) {
      await showJoinBoardSheet(context, country: country);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppLocalizations.of(context);
    final f = await joinBoard(ref, country: country);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = f == null ? null : communityFailureText(t, f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final flagOn = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.leaderboard)));
    final account = ref.watch(sessionProvider.select((s) => s.canEarnPoints));
    final bar = YqStageBar(back: true, title: t.cmLeaderboardTitle);

    Widget canvas(List<Widget> children, {List<Widget> slivers = const [], Widget? footer, Future<void> Function()? onRefresh}) =>
        Scaffold(
          backgroundColor: YqColors.porcelain,
          body: YqCanvas(
            onRefresh: onRefresh,
            stage: YqStage(compact: true, child: bar),
            footer: footer,
            slivers: slivers,
            children: children,
          ),
        );

    if (!flagOn) return canvas([YqEmptyState(icon: YqIcons.podium, title: t.cmFeatureOff)]);
    if (!account) {
      return canvas([
        CommunityNote(
          icon: YqIcons.podium,
          title: t.cmGuest,
          body: t.cmShowMeBody,
          actionLabel: t.cmJoin,
          onAction: () => showSignInSheet(context),
        ),
        const CommunityFooter(),
      ]);
    }
    final profile = ref.watch(meProfileProvider).valueOrNull;
    if (profile?.community.banned ?? false) return canvas([CommunityNote(icon: YqIcons.lock, title: t.cmBanned)]);

    final country = profile?.community.country;
    final countryName = country == null ? null : ref.watch(countryNameProvider((code: country, locale: locale))).valueOrNull;
    final segmented = YqSegmented<LeaderboardScope>(
      segments: [(LeaderboardScope.global, t.cmWorld), (LeaderboardScope.country, countryName ?? t.cmSwitchCountry)],
      selected: _scope,
      onChanged: (s) => setState(() {
        _scope = s;
        _error = null;
      }),
    );
    Future<void> refresh() async => ref.invalidate(leaderboardProvider(_scope));

    // No city chosen: no country board to ask for.
    if (_scope == LeaderboardScope.country && country == null) {
      return canvas([segmented, const SizedBox(height: YqSpace.l), CommunityNote(icon: YqIcons.flag, title: t.cmCountryUnknown)]);
    }

    final async = ref.watch(leaderboardProvider(_scope));
    final error = async.error;
    if (error is CommunityException) {
      final note = switch (error.failure) {
        CommunityFailure.featureOff => YqEmptyState(icon: YqIcons.podium, title: t.cmFeatureOff),
        CommunityFailure.countryUnknown => CommunityNote(icon: YqIcons.flag, title: t.cmCountryUnknown),
        CommunityFailure.countryTooSmall => CommunityNote(icon: YqIcons.flag, title: t.cmCountryTooSmall),
        CommunityFailure.communityBanned => CommunityNote(icon: YqIcons.lock, title: t.cmBanned),
        _ => YqErrorState(onRetry: refresh),
      };
      final countryOn = profile?.community.leaderboardCountry ?? false;
      return canvas(onRefresh: refresh, [
        segmented,
        const SizedBox(height: YqSpace.l),
        note,
        // A small country board grows only if people can still opt in to it.
        if (error.failure == CommunityFailure.countryTooSmall && !countryOn) ...[
          const SizedBox(height: YqSpace.m),
          _JoinCard(country: true, busy: _busy, error: _error, onJoin: () => _join(country: true)),
        ],
      ]);
    }
    final fresh = async.valueOrNull;
    if (fresh == null) {
      if (async.hasError) return canvas([segmented, const SizedBox(height: YqSpace.l), YqErrorState(onRetry: refresh)]);
      return canvas([segmented, const SizedBox(height: YqSpace.l), const CompetitorSkeleton(rows: 8)]);
    }
    final view = fresh.value;
    final left = _leftHere(profile, _scope);
    final hidden = ref.watch(hiddenHandlesProvider);
    final rows = [
      for (final r in view.rows)
        if (!hidden.contains(r.handle) && !(left && r.me)) r,
    ];
    final joined = !left && (_scope == LeaderboardScope.global ? view.joined : view.countryJoined);
    final me = joined ? view.me : null;

    return canvas(
      onRefresh: refresh,
      [
        YqOfflineBanner(offline: fresh.offline),
        segmented,
        const SizedBox(height: YqSpace.l),
        if (!joined) ...[
          _JoinCard(country: _scope == LeaderboardScope.country, busy: _busy, error: _error, onJoin: () => _join(country: _scope == LeaderboardScope.country)),
          const SizedBox(height: YqSpace.l),
        ],
      ],
      slivers: [
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final c = rows[i];
            return CompetitorRow(
              key: ValueKey(c.handle),
              competitor: c,
              showPoints: false,
              onLongPress: c.me ? null : () => showReportSheet(context, c),
            );
          },
        ),
        const SliverToBoxAdapter(child: SnapshotLine()),
        const SliverToBoxAdapter(child: CommunityFooter()),
      ],
      footer: joined ? _MyRank(rank: me?.rank) : null,
    );
  }

  /// Left on this phone (queued): hidden here at once, whatever the cached board says.
  static bool _leftHere(MeProfile? p, LeaderboardScope scope) {
    if (p == null || p.handle == null) return false;
    return scope == LeaderboardScope.global ? !p.community.leaderboard : !p.community.leaderboardCountry;
  }
}

/// «أظهرني في اللوحة» / «أظهرني في لوحة بلدي» with its disclosure.
class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.country, required this.busy, required this.error, required this.onJoin});
  final bool country;
  final bool busy;
  final String? error;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommunityNote(
          icon: country ? YqIcons.flag : YqIcons.podium,
          title: country ? t.cmSwitchCountry : t.cmLeaderboardTitle,
          body: country ? t.cmShowMeCountryBody : t.cmShowMeBody,
          actionLabel: country ? t.cmShowMeCountry : t.cmShowMe,
          onAction: onJoin,
          busy: busy,
        ),
        InlineFailure(error),
      ],
    );
  }
}

/// «ترتيبك {rank}» pinned above the dock, or «يظهر ترتيبك بعد التحديث الليلي».
class _MyRank extends StatelessWidget {
  const _MyRank({required this.rank});
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label = rank == null ? t.cmRankAfterSnapshot : t.cmYourRank(YqFormat.number(rank!));
    return Semantics(
      liveRegion: true,
      child: LiquidGlass(
        radius: YqRadii.pill,
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl, vertical: YqSpace.m),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: rank == null ? YqColors.muted : YqColors.lapis,
          ),
        ),
      ),
    );
  }
}
