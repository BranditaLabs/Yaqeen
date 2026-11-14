import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/design/motion.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_once.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../profile/domain/me_profile.dart';
import '../../profile/presentation/me_avatar.dart';
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
    final profile = ref.read(meProfileProvider).valueOrNull;
    final attested = profile?.community.attestedAdult ?? false;
    // The attestation or a shown name is still missing: the sheet asks for it.
    if (!attested || needsDisplayName(profile)) {
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

    // Every state is the same tree (motion scope → scaffold → canvas, the segmented control at
    // the same place), so switching World/Country or loading a board never remounts the screen:
    // the segmented thumb glides, the scroll stays, and only the board area changes.
    Widget canvas(
      List<Widget> children, {
      List<String> handles = const [],
      List<Widget> slivers = const [],
      Widget? footer,
      Future<void> Function()? onRefresh,
    }) =>
        RankMotionScope(
          listId: _scope,
          handles: handles,
          child: Scaffold(
            backgroundColor: YqColors.porcelain,
            body: YqCanvas(
              onRefresh: onRefresh,
              stage: YqStage(compact: true, child: bar),
              footer: footer,
              slivers: slivers,
              children: children,
            ),
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

    // The board's states share one head: the offline line, the segmented control, a gap.
    List<Widget> head({bool offline = false}) => [YqOfflineBanner(offline: offline), segmented, const SizedBox(height: YqSpace.l)];

    // No city chosen: no country board to ask for.
    if (_scope == LeaderboardScope.country && country == null) {
      return canvas(onRefresh: () async {}, [...head(), CommunityNote(icon: YqIcons.flag, title: t.cmCountryUnknown)]);
    }

    final async = ref.watch(leaderboardProvider(_scope));
    final error = async.error;
    final globalOn = profile?.community.leaderboard ?? false;
    // Typed states replace the board; any other failure keeps a board already shown.
    if (error is CommunityException && (!async.hasValue || _typed.contains(error.failure))) {
      final note = switch (error.failure) {
        CommunityFailure.featureOff => YqEmptyState(icon: YqIcons.podium, title: t.cmFeatureOff),
        CommunityFailure.countryUnknown => CommunityNote(icon: YqIcons.flag, title: t.cmCountryUnknown),
        CommunityFailure.countryTooSmall => CommunityNote(icon: YqIcons.flag, title: t.cmCountryTooSmall),
        CommunityFailure.communityBanned => CommunityNote(icon: YqIcons.lock, title: t.cmBanned),
        _ => YqErrorState(onRetry: refresh),
      };
      final countryOn = profile?.community.leaderboardCountry ?? false;
      return canvas(onRefresh: refresh, [
        ...head(),
        note,
        // A small country board grows only if people can still opt in to it.
        if (error.failure == CommunityFailure.countryTooSmall && !countryOn) ...[
          const SizedBox(height: YqSpace.m),
          _JoinCard(country: true, needsBoard: !globalOn, busy: _busy, error: _error, onJoin: () => _join(country: globalOn)),
        ],
      ]);
    }
    final fresh = async.valueOrNull;
    if (fresh == null) {
      if (async.hasError) return canvas(onRefresh: refresh, [...head(), YqErrorState(onRetry: refresh)]);
      return canvas(onRefresh: refresh, [...head(), const CompetitorSkeleton(rows: 8)]);
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

    // Rows that moved glide; the person's own ring draws in and their pinned rank slides up, once.
    // The board fades in over the skeleton's place (and again when the scope changes).
    return canvas(
      handles: [for (final r in rows) r.handle],
      onRefresh: refresh,
      [
        ...head(offline: fresh.offline),
        if (!joined) ...[
          _JoinCard(
            country: _scope == LeaderboardScope.country,
            needsBoard: _scope == LeaderboardScope.country && !globalOn,
            busy: _busy,
            error: _error,
            // The country board is offered only on top of the level board (never both at once).
            onJoin: () => _join(country: _scope == LeaderboardScope.country && globalOn),
          ),
          const SizedBox(height: YqSpace.l),
        ],
      ],
      slivers: [
        YqSliverFadeIn(
          key: ValueKey(_scope),
          sliver: SliverList.builder(
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
        ),
        const SliverToBoxAdapter(child: SnapshotLine()),
        const SliverToBoxAdapter(child: CommunityFooter()),
      ],
      footer: joined ? _MyRank(rank: me?.rank) : null,
    );
  }

  static const _typed = {
    CommunityFailure.featureOff,
    CommunityFailure.countryUnknown,
    CommunityFailure.countryTooSmall,
    CommunityFailure.communityBanned,
  };

  /// Left on this phone (queued): hidden here at once, whatever the cached board says.
  static bool _leftHere(MeProfile? p, LeaderboardScope scope) {
    if (p == null || p.handle == null) return false;
    return scope == LeaderboardScope.global ? !p.community.leaderboard : !p.community.leaderboardCountry;
  }
}

/// «أظهرني في اللوحة» / «أظهرني في لوحة بلدي» with its disclosure. While the level board is off
/// ([needsBoard]) the country card says so and offers the level board itself, by name.
class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.country, this.needsBoard = false, required this.busy, required this.error, required this.onJoin});
  final bool country;
  final bool needsBoard;
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
          body: needsBoard ? '${t.cmCountryNeedsBoard}\n${t.cmShowMeBody}' : (country ? t.cmShowMeCountryBody : t.cmShowMeBody),
          actionLabel: country && !needsBoard ? t.cmShowMeCountry : t.cmShowMe,
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
    // It slides up from the bottom once, with the person's own ring drawing in beside the rank.
    return YqSlideIn(
      offset: const Offset(0, 1.2),
      delay: Motion.standard,
      child: Semantics(
        liveRegion: true,
        label: label,
        excludeSemantics: true,
        child: LiquidGlass(
          radius: YqRadii.pill,
          padding: const EdgeInsetsDirectional.fromSTEB(YqSpace.s, YqSpace.s, YqSpace.xl, YqSpace.s),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MeAvatar(size: 32, ring: true, stroke: 2, drawIn: Motion.ringDraw),
              const SizedBox(width: YqSpace.m),
              Flexible(
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
            ],
          ),
        ),
      ),
    );
  }
}
