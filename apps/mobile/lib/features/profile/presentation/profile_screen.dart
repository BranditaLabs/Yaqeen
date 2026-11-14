import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/product_analytics.dart';
import '../../../core/config/config_controller.dart';
import '../../../core/config/env.dart';
import '../../../core/design/motion.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_count.dart';
import '../../../core/widgets/yq_flip.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../card/presentation/card_screen.dart' show myCardProvider;
import '../../card/presentation/journey_widgets.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../community/presentation/badge_label.dart';
import '../../content/presentation/pack_row.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../domain/avatar.dart';
import '../domain/me_profile.dart';
import 'avatar_sheet.dart';
import 'badges_strip.dart';
import 'edit_name_sheet.dart';
import 'level_ladder_sheet.dart';
import 'me_avatar.dart';
import 'me_profile_controller.dart';
import 'profile_providers.dart';
import 'profile_settings_screen.dart';

// The sub-screens used to live in this file; keep them importable from here.
export 'downloads_screen.dart';
export 'ledger_screen.dart';
export 'privacy_screen.dart';
export 'profile_providers.dart';

/// `21 · Profile` (APP_SPEC §5.24, design §6.1): who you are and where you stand.
///
/// Stage: the avatar inside the level ring (lapis; gold only at the top level or for the one-shot
/// level-up glint), the name and the level caption. Orbs: Level · Points (or Language) · League (or
/// Downloads) — the set depends on flags and session only, so it never swaps while loading. Body:
/// badges (the only gold block), the journey, «المنافسة», the card row and the rewards group.
/// Everything else lives in `/profile/settings`. Never shows which prayers or azkar.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// The level-up moment is playing (gold ring + glint), then the ring settles back to lapis.
  bool _celebrating = false;
  Timer? _celebration;
  Timer? _toast;

  static const celebration = Motion.glintHold;

  @override
  void dispose() {
    _celebration?.cancel();
    _toast?.cancel();
    super.dispose();
  }

  /// Plays the level-up moment once, unless Home already did: the light sweeps round the ring
  /// and the picture swells softly, then a quiet toast, and the level is marked seen. Under
  /// reduce-motion the toast comes at once.
  void _maybeCelebrate(LevelUp up) {
    if (!up.pending || up.level == null || _celebrating) return;
    // Only on screen (an offstage tab keeps its tickers off): the moment must be seen to be spent.
    if (!TickerMode.valuesOf(context).enabled) return;
    _celebrating = true;
    final level = up.level!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      final locale = Localizations.localeOf(context).languageCode;
      final message = t.lvlReached(level.name(locale));
      setState(() {});
      ref.read(levelUpProvider.notifier).markSeen().ignore();
      if (reduceMotion(context)) {
        YqToast.show(context, message);
      } else {
        _toast = Timer(Motion.glint, () {
          if (mounted) YqToast.show(context, message);
        });
      }
      _celebration = Timer(celebration, () {
        if (mounted) setState(() => _celebrating = false);
      });
    });
  }

  /// A signed-in cold start with nothing cached: the controller's own background refresh fails
  /// silently, so the tab fetches once itself to know when to stop shimmering and offer a retry.
  bool _coldFetching = false;
  bool _coldFailed = false;

  void _coldFetch() {
    if (_coldFetching || _coldFailed) return;
    _coldFetching = true;
    Future.microtask(() async {
      await ref.read(meProfileProvider.notifier).refresh(); // keeps the placeholder on failure
      final cached = await ref.read(profileRepositoryProvider).cached();
      _coldFetching = false;
      if (mounted && cached == null) setState(() => _coldFailed = true);
    });
  }

  Future<void> _refresh() async {
    final t = AppLocalizations.of(context);
    final session = ref.read(sessionProvider);
    ref
      ..invalidate(pendingSyncProvider)
      ..invalidate(downloadsBytesProvider)
      ..invalidate(myJourneyProvider);
    if (!session.canEarnPoints) return;
    ref
      ..invalidate(challengeControllerProvider)
      ..invalidate(myCardProvider);
    final before = ref.read(meProfileProvider).valueOrNull;
    await ref.read(meProfileProvider.notifier).refresh();
    // A failed refresh keeps the cached profile (the controller only replaces it on success).
    if (before != null && identical(ref.read(meProfileProvider).valueOrNull, before) && mounted) {
      YqToast.show(context, t.errorGeneric);
    }
    try {
      await ref.read(challengeControllerProvider.future);
    } on Exception {
      // Offline: the cached summary stays.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final config = ref.watch(remoteConfigProvider);
    final signedIn = session.canEarnPoints;
    final me = ref.watch(meProfileProvider);
    // An account with nothing cached is first given a level-1 placeholder: treat it as still loading.
    final ready = ref.watch(meProfileReadyProvider).valueOrNull;
    final real = !signedIn || ready == true;
    final profile = real ? me.valueOrNull : null;
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    if (real) {
      _coldFailed = false;
    } else if (me.hasValue && ready == false) {
      _coldFetch();
    }
    // Only once the real profile is on screen: LevelUpController reads the profile in a microtask
    // after its first build, and must neither be created while the profile is still resolving nor
    // record the placeholder's level 1 as seen (the real level would then read as a level-up).
    if (profile != null) _maybeCelebrate(ref.watch(levelUpProvider));
    // A name the server refused on replay is announced app-wide by NameRevertToaster (app shell).

    final rewards = signedIn && config.isOn(Flags.rewards);
    final competitions = anyCompetitionOn(config);

    final settings = GlassIconButton(
      tooltip: t.pfSettings,
      onPressed: () => context.push('/profile/settings'),
      icon: const YqIcon(YqIcons.settings, size: 20),
    );
    final bar = YqStageBar(large: true, title: t.tabProfile, actions: [settings]);

    // No profile at all (a cold start whose first fetch failed): the error with a retry.
    if (profile == null && ((me.hasError && !me.isLoading) || _coldFailed)) {
      return YqCanvas(
        stage: YqStage(child: bar),
        children: [
          YqOfflineBanner(offline: !online),
          LiquidGlass(
            child: YqErrorState(
              onRetry: () {
                if (me.hasError) ref.invalidate(meProfileProvider);
                setState(() => _coldFailed = false); // the next build fetches again
              },
            ),
          ),
        ],
      );
    }

    return YqCanvas(
      onRefresh: _refresh,
      stage: YqStage(
        child: Column(
          children: [
            bar,
            const SizedBox(height: YqSpace.l),
            YqFadeSwap(
              child: profile == null ? const _StageSkeleton() : _Stage(key: const ValueKey('profile-stage'), profile: profile, celebrating: _celebrating),
            ),
          ],
        ),
      ),
      children: [
        YqOfflineBanner(offline: !online),
        YqFadeSwap(
          child: profile == null
              ? const YqSkeleton(key: ValueKey('profile-orbs-skeleton'), child: YqSkeletonOrbs(count: 3))
              : YqOrbRow(
                  key: const ValueKey('profile-orbs'),
                  rise: true,
                  orbs: [
                    _LevelOrb(profile: profile),
                    if (rewards) _PointsOrb(weekPoints: profile.weekPoints) else const _LanguageOrb(),
                    if (config.isOn(Flags.leagues)) _LeagueOrb(profile: profile, signedIn: signedIn) else const _DownloadsOrb(),
                  ],
                ),
        ),
        const SizedBox(height: YqSpace.xxl),
        if (signedIn && profile != null) ...[
          BadgesStrip(badges: profile.recentBadges, count: profile.badgesCount),
          const SizedBox(height: YqSpace.l),
        ],
        if (signedIn) const JourneySection(),
        if (competitions) ...[
          YqHeading(t.pfCompetition),
          YqGroup(
            children: [
              if (config.isOn(Flags.leagues)) _row(t.pfWeeklyLeague, YqIcons.league, () => context.push('/profile/leagues')),
              if (config.isOn(Flags.tournaments)) _row(t.pfTournaments, YqIcons.trophy, () => context.push('/profile/tournaments')),
              if (config.isOn(Flags.leaderboard)) _row(t.pfLeaderboard, YqIcons.podium, () => context.push('/profile/leaderboard')),
              if (signedIn) _row(t.pfVisibility, YqIcons.profile, () => context.push('/profile/community')),
            ],
          ),
          const SizedBox(height: YqSpace.xl),
        ],
        if (config.isOn(Flags.publicCards)) ...[
          _CardRow(signedIn: signedIn),
          const SizedBox(height: YqSpace.xl),
        ],
        if (rewards) ...[
          YqHeading(t.pfRewards),
          YqGroup(
            children: [
              _row(t.profileLedger, YqIcons.streak, () => context.push('/profile/ledger')),
              _row(t.myCodes, YqIcons.bookmark, () => context.push('/challenge/redeem/codes')),
              _row(t.profileVisitStore, YqIcons.share, () {
                unawaited(ref.read(productAnalyticsProvider).track(ProductEvent.storeClick, {'from': 'profile'}));
                ref.read(deviceServicesProvider).openUrl(Uri.parse(Env.storeUrl));
              }),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(String title, YqIcons icon, VoidCallback onTap) => YqListRow(title: title, leading: YqIconTile(icon, size: 36), onTap: onTap);
}

/* ------------------------------------------------------------------ stage */

/// Cold start without a cached profile: a 120-pt circle and two lines.
class _StageSkeleton extends StatelessWidget {
  const _StageSkeleton();

  @override
  Widget build(BuildContext context) => const YqSkeleton(
        key: ValueKey('profile-stage-skeleton'),
        child: Column(
          children: [
            YqSkeletonBox.circle(120),
            SizedBox(height: YqSpace.m),
            YqSkeletonBox(width: 160, height: 24, radius: YqRadii.pill),
            SizedBox(height: YqSpace.s),
            YqSkeletonBox(width: 120, height: 12, radius: YqRadii.pill),
          ],
        ),
      );
}

class _Stage extends ConsumerWidget {
  const _Stage({super.key, required this.profile, required this.celebrating});
  final MeProfile profile;
  final bool celebrating;

  static const size = 120.0;

  /// How far the edit badge's 44-pt target hangs past the ring's end and bottom edges.
  static const _badgeOutset = 6.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final session = ref.watch(sessionProvider);
    final signedIn = session.canEarnPoints;
    final uploading = ref.watch(photoUploadingProvider);
    final pending = ref.watch(pendingSyncProvider).valueOrNull ?? 0;
    final rawName = profile.displayName ?? (signedIn ? session.displayName : null);
    final name = (rawName?.trim().isNotEmpty ?? false) ? rawName!.trim() : t.guestName;
    final avatar = profile.photoHidden && profile.avatar is PhotoAvatar ? const InitialAvatar() : profile.avatar;
    final level = profile.level;
    final achieved = signedIn && (level.isTop || celebrating);
    final caption = t.lvlCaption(YqFormat.number(level.level), level.name(locale)) +
        (signedIn && profile.handle != null ? t.pfHandleSuffix(profile.handle!) : '');

    // One ring for the screen's life: it draws in once, then eases; a new picture cross-fades
    // inside it (YqAvatarSwap) and a level just reached sweeps light round it.
    final picture = YqLevelAvatar(
      key: const ValueKey('profile-avatar'),
      avatar: avatar,
      level: level.level,
      progress: signedIn ? level.progress : 0,
      size: size,
      stroke: 4,
      achieved: achieved,
      glint: signedIn && celebrating,
      drawIn: Motion.ringDraw,
      name: profile.nameHidden ? null : name,
      levelName: level.name(locale),
    );

    // The edit badge hangs [badgeOutset] past the ring's end and bottom; the box grows by that
    // much (both sides across, below only) so its whole 44-pt target is hit-testable, and the gap
    // under it shrinks by the same amount, so nothing else moves.
    const outset = _badgeOutset;
    return Column(
      children: [
        SizedBox(
          width: size + 2 * outset,
          height: size + outset,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: GlassTap(
                  onTap: () => showAvatarSheet(context, ref),
                  semanticLabel: t.pfSemanticsJoin(
                    t.lvlRingSemantics(YqFormat.number(level.level), level.name(locale), YqFormat.number((level.progress * 100).round())),
                    t.pfEditPhoto,
                  ),
                  child: ExcludeSemantics(
                    child: SizedBox.square(
                      dimension: size,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          picture,
                          // Uploading a photo: the ring shimmers in lapis until it lands.
                          if (uploading)
                            const IgnorePointer(
                              key: ValueKey('profile-uploading'),
                              child: YqSkeleton(child: YqRing(value: 1, size: size, stroke: 4, color: YqColors.lapis)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // The edit badge pops on its own press (0.92, springing back) — a sibling above the
              // ring, not inside its tap, so the ring and picture stay still while it does. Same
              // action as the ring, already announced there.
              PositionedDirectional(
                end: 0,
                bottom: 0,
                child: ExcludeSemantics(
                  child: GlassTap(
                    key: const ValueKey('profile-edit-badge'),
                    onTap: () => showAvatarSheet(context, ref),
                    pressScale: 0.92,
                    child: const SizedBox.square(
                      dimension: YqSpace.touch,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 32,
                          child: LiquidGlass(
                            radius: YqRadii.pill,
                            padding: EdgeInsets.zero,
                            highlight: false,
                            opacity: 0.9,
                            child: Center(child: YqIcon(YqIcons.edit, size: 16)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m - outset),
        GlassTap(
          onTap: () => showEditNameSheet(context),
          semanticLabel: t.pfSemanticsJoin(profile.nameHidden ? t.avHiddenName : name, t.pfNameTitle),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: YqSpace.touch),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      profile.nameHidden ? t.avHiddenName : name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: YqMoment.display(context, size: 28).copyWith(color: profile.nameHidden ? YqColors.muted : YqColors.ink),
                    ),
                  ),
                  if (profile.nameHidden) ...[
                    const SizedBox(width: YqSpace.s),
                    const YqIcon(YqIcons.lock, size: 18, tone: YqIconTone.idle),
                  ],
                ],
              ),
            ),
          ),
        ),
        Text(caption, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, height: 1.4, color: YqColors.muted)),
        if (!signedIn) ...[
          const SizedBox(height: YqSpace.s),
          Text(t.pfGuestNote, textAlign: TextAlign.center, style: text.bodySmall),
          const SizedBox(height: YqSpace.m),
          GlassTap(
            onTap: () => showSignInSheet(context),
            semanticLabel: t.pfGuestCta,
            child: Container(
              constraints: const BoxConstraints(minHeight: YqSpace.touch),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.xl, vertical: YqSpace.s),
              decoration: BoxDecoration(color: YqColors.ink, borderRadius: BorderRadius.circular(YqRadii.pill)),
              child: Text(t.pfGuestCta, style: const TextStyle(color: YqColors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          ),
        ],
        if (pending > 0) ...[
          const SizedBox(height: YqSpace.s),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const YqIcon(YqIcons.sync, size: 14, tone: YqIconTone.idle),
              const SizedBox(width: 6),
              Flexible(child: Text(t.pfPendingSync, style: const TextStyle(fontSize: 12, color: YqColors.muted))),
            ],
          ),
        ],
      ],
    );
  }
}

/* ------------------------------------------------------------------- orbs */

class _LevelOrb extends StatelessWidget {
  const _LevelOrb({required this.profile});
  final MeProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final level = profile.level;
    final next = level.nextAt;
    final remaining = next == null ? null : (next - profile.lifetimePoints).clamp(0, next);
    final status = remaining == null ? t.pfTopLevel : t.pfToNext(YqFormat.number(remaining));
    return YqOrb(
      title: t.pfLevel,
      status: status,
      // The points still to go count into place, wrapped like the orb's status (two lines at most).
      statusChild: remaining == null
          ? null
          : CountUp(
              key: const ValueKey('level-orb-status'),
              value: remaining,
              builder: t.pfToNext,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: YqOrb.statusStyle(),
            ),
      onTap: () => showLevelLadderSheet(context, level),
      semanticLabel: t.pfSemanticsJoin(t.lvlNumeral(YqFormat.number(level.level)), status),
      disc: YqRing(
        value: level.progress,
        color: YqColors.lapis,
        track: YqColors.lapis100.withValues(alpha: 0.5),
        size: YqOrb.defaultSize - 12,
        stroke: 5,
        drawIn: Motion.ringDraw,
        child: YqRollingNumber(value: level.level, style: YqMoment.numeral(size: 30)),
      ),
    );
  }
}

/// «الرصيد»; a tap flips the disc about its vertical axis to «هذا الأسبوع» (self only), a long
/// press opens the ledger. Numbers roll into place.
class _PointsOrb extends ConsumerStatefulWidget {
  const _PointsOrb({required this.weekPoints});
  final int weekPoints;

  @override
  ConsumerState<_PointsOrb> createState() => _PointsOrbState();
}

class _PointsOrbState extends ConsumerState<_PointsOrb> {
  bool _week = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final challenge = ref.watch(challengeControllerProvider);
    final balance = challenge.valueOrNull?.balance;
    // No summary and nothing cached (offline on a fresh install, a server error): «—» and a tap
    // retries — never an endless shimmer. The skeleton is only for a first load on its way.
    final failed = challenge.hasError && !challenge.hasValue && !challenge.isLoading;
    final value = _week ? widget.weekPoints : balance;
    final title = _week ? t.pfThisWeek : t.pfBalance;
    final status = value == null ? (failed ? t.pfNoRank : '') : t.challengePointsLabel(YqFormat.number(value));
    final Widget balanceFace = YqFadeSwap(
      alignment: Alignment.center,
      child: balance == null && failed
          // A retry affordance: the tap fetches the summary again.
          ? const Center(key: ValueKey('points-failed'), child: YqIcon(YqIcons.sync, size: 26, tone: YqIconTone.idle))
          : balance == null
              ? const YqSkeleton(
                  key: ValueKey('points-loading'),
                  child: Center(child: YqSkeletonBox(width: 44, height: 18, radius: YqRadii.pill)),
                )
              : Center(
                  key: const ValueKey('points-false'),
                  child: YqRollingNumber(value: balance, style: _numeral),
                ),
    );
    final Widget weekFace = Center(
      key: const ValueKey('points-true'),
      child: YqRollingNumber(value: widget.weekPoints, style: _numeral),
    );
    return YqOrb(
      title: title,
      status: status,
      swapText: true,
      onTap: () => failed && !_week ? ref.invalidate(challengeControllerProvider) : setState(() => _week = !_week),
      onLongPress: () => context.push('/profile/ledger'),
      semanticLabel: t.pfSemanticsJoin(title, failed && value == null ? t.retry : status),
      disc: SizedBox.expand(child: YqFlip(showBack: _week, front: balanceFace, back: weekFace)),
    );
  }

  static final _numeral = YqText.numeral.copyWith(fontSize: 22, fontWeight: FontWeight.w500, color: YqColors.ink);
}

class _LanguageOrb extends ConsumerWidget {
  const _LanguageOrb();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final name = locale == 'ar' ? t.langArabic : t.langEnglish;
    return YqOrb(
      title: t.langApp,
      status: name,
      onTap: () => showLanguageSheet(context),
      semanticLabel: t.pfSemanticsJoin(t.langApp, name),
      disc: YqOrb.number(t.pfLangGlyph, size: 28),
    );
  }
}

/// The league place from the nightly snapshot, or an invitation to join. Monochrome: an ink tier
/// numeral on a hairline ring (the division «ذهب» never turns gold).
class _LeagueOrb extends StatelessWidget {
  const _LeagueOrb({required this.profile, required this.signedIn});
  final MeProfile profile;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final league = profile.league;
    final joined = signedIn && profile.community.leagues;
    final String title;
    final String status;
    final Widget disc;
    if (joined && league != null) {
      title = divisionName(league.division, t, custom: league.divisionName(locale));
      status = league.rank == null ? t.pfNoRank : t.pfRankOf(YqFormat.number(league.rank!), YqFormat.number(league.size));
      disc = Center(
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: YqColors.line, width: 2)),
          child: YqRollingNumber(value: league.division, style: YqMoment.numeral(size: 28)),
        ),
      );
    } else {
      title = t.pfLeague;
      status = joined ? t.pfNoRank : t.pfLeagueJoin;
      disc = Center(
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: YqColors.lapis, width: 1.5)),
          child: const YqIcon(YqIcons.league, size: 28),
        ),
      );
    }
    return YqOrb(
      title: title,
      status: status,
      statusColor: joined ? null : YqColors.lapis,
      onTap: () => context.push('/profile/leagues'),
      semanticLabel: t.pfSemanticsJoin(title, status),
      disc: disc,
    );
  }
}

class _DownloadsOrb extends ConsumerWidget {
  const _DownloadsOrb();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final bytes = ref.watch(downloadsBytesProvider);
    // A failed measurement reads as nothing on disk.
    final mb = bytes.isLoading && !bytes.hasValue ? null : megabytes(t, bytes.valueOrNull ?? 0);
    return YqOrb(
      title: t.profileDownloads,
      status: mb ?? '',
      onTap: () => context.push('/profile/downloads'),
      semanticLabel: mb == null ? t.profileDownloads : t.pfSemanticsJoin(t.profileDownloads, mb),
      disc: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const YqIcon(YqIcons.download, size: 30),
          if (mb == null) ...[
            const SizedBox(height: YqSpace.xs),
            const YqSkeleton(child: YqSkeletonBox(width: 36, height: 8, radius: YqRadii.pill)),
          ],
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------- card */

/// «بطاقة يقين»: the person's avatar, and whether the card is published (and how often opened).
class _CardRow extends ConsumerWidget {
  const _CardRow({required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final card = signedIn ? ref.watch(myCardProvider).valueOrNull : null;
    final subtitle = !signedIn
        ? t.cardTeaserBody
        : card == null
            ? null
            : card.published
                ? t.pfCardPublished(YqFormat.number(card.views))
                : t.pfCardUnpublished;
    return GlassTap(
      onTap: () => context.push('/profile/card'),
      semanticLabel: subtitle == null ? t.pfCardRow : t.pfSemanticsJoin(t.pfCardRow, subtitle),
      child: ExcludeSemantics(
        child: LiquidGlass(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
          child: Row(
            children: [
              const MeAvatar(size: 40),
              const SizedBox(width: YqSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.pfCardRow, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
                    if (subtitle != null) Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.5, color: YqColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: YqColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
