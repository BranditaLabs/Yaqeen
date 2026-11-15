import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
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

/// `/profile/community` «الظهور في المنافسات» (APP_SPEC §5.31.5, design §6.9): one switch per
/// competition (each hidden while its flag is off; on = a direct join with the attestation, off =
/// a queued leave), live tournament entries with leave, the name, and the blocked list.
class CommunitySettingsScreen extends ConsumerStatefulWidget {
  const CommunitySettingsScreen({super.key});

  @override
  ConsumerState<CommunitySettingsScreen> createState() => _CommunitySettingsScreenState();
}

enum _Switch { league, board, country }

class _CommunitySettingsScreenState extends ConsumerState<CommunitySettingsScreen> {
  _Switch? _busy;
  String? _error;

  Future<void> _turnOn(_Switch s, bool attested) async {
    setState(() => _error = null);
    if (s == _Switch.league) {
      await showJoinLeagueSheet(context);
      return;
    }
    // The attestation or a shown name is still missing: the sheet asks for it.
    if (!attested || needsDisplayName(ref.read(meProfileProvider).valueOrNull)) {
      await showJoinBoardSheet(context, country: s == _Switch.country);
      return;
    }
    setState(() => _busy = s);
    final t = AppLocalizations.of(context);
    final f = await joinBoard(ref, country: s == _Switch.country);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = f == null ? null : communityFailureText(t, f);
    });
  }

  Future<void> _turnOff(_Switch s) async {
    setState(() => _error = null);
    switch (s) {
      case _Switch.league:
        await leaveLeague(ref);
      case _Switch.board:
        await ref.read(meProfileProvider.notifier).leave(leaderboard: true);
      case _Switch.country:
        await ref.read(meProfileProvider.notifier).leave(leaderboardCountry: true);
    }
    if (s != _Switch.league) {
      ref
        ..invalidate(leaderboardProvider(LeaderboardScope.global))
        ..invalidate(leaderboardProvider(LeaderboardScope.country));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final config = ref.watch(remoteConfigProvider);
    final leaguesOn = config.isOn(Flags.leagues);
    final boardOn = config.isOn(Flags.leaderboard);
    final tournamentsOn = config.isOn(Flags.tournaments);
    final account = ref.watch(sessionProvider.select((s) => s.canEarnPoints));

    Widget canvas(List<Widget> children) => Scaffold(
          backgroundColor: YqColors.porcelain,
          body: YqCanvas(
            onRefresh: account
                ? () async {
                    ref
                      ..invalidate(blocksProvider)
                      ..invalidate(tournamentsProvider);
                    await ref.read(meProfileProvider.notifier).refresh();
                  }
                : null,
            stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.cmVisibilityTitle)),
            children: children,
          ),
        );

    if (!account) {
      return canvas([
        CommunityNote(icon: YqIcons.profile, title: t.cmGuest, actionLabel: t.cmJoin, onAction: () => showSignInSheet(context)),
        const CommunityFooter(),
      ]);
    }
    final profile = ref.watch(meProfileProvider).valueOrNull;
    final c = profile?.community ?? CommunitySettings.off;

    Widget switchRow(_Switch s, String title, bool value, {String? subtitle, bool canTurnOn = true}) => YqListRow(
          title: title,
          subtitle: subtitle,
          trailing: _busy == s
              ? const YqSkeleton(child: YqSkeletonBox(width: 46, height: 28, radius: YqRadii.pill))
              : Semantics(
                  enabled: value || canTurnOn,
                  child: IgnorePointer(
                    // Disabled (dimmed) while it cannot be turned on; turning off always works.
                    ignoring: !value && !canTurnOn,
                    child: Opacity(
                      opacity: !value && !canTurnOn ? 0.4 : 1,
                      child: YqSwitch(
                        value: value,
                        label: title,
                        onChanged: (v) {
                          if (_busy != null) return;
                          if (v && !canTurnOn) return;
                          v ? _turnOn(s, c.attestedAdult) : _turnOff(s);
                        },
                      ),
                    ),
                  ),
                ),
        );

    final switches = <Widget>[
      if (leaguesOn) switchRow(_Switch.league, t.cmSwitchLeague, c.leagues),
      if (boardOn) switchRow(_Switch.board, t.cmSwitchLeaderboard, c.leaderboard),
      if (boardOn)
        switchRow(
          _Switch.country,
          t.cmSwitchCountry,
          c.leaderboardCountry,
          // Only on top of the level board: turning it on never publishes the person worldwide.
          subtitle: c.country == null ? t.cmCountryUnknown : (!c.leaderboard ? t.cmCountryNeedsBoard : null),
          canTurnOn: c.country != null && c.leaderboard,
        ),
    ];

    return canvas([
      if (c.banned) ...[CommunityNote(icon: YqIcons.lock, title: t.cmBanned), const SizedBox(height: YqSpace.l)],
      if (!c.banned && switches.isNotEmpty) ...[YqGroup(children: switches), InlineFailure(_error), const SizedBox(height: YqSpace.l)],
      if (tournamentsOn && !c.banned) const _ActiveTournaments(),
      YqGroup(
        children: [
          YqListRow(
            title: t.cmDisplayName,
            subtitle: (profile?.nameHidden ?? false) ? t.avHiddenName : (profile?.displayName?.trim().isNotEmpty ?? false) ? profile!.displayName : null,
            onTap: () => context.push('/profile/settings'),
          ),
        ],
      ),
      const SizedBox(height: YqSpace.l),
      YqHeading(t.cmBlocked),
      const _Blocked(),
      const CommunityFooter(),
    ]);
  }
}

/// «بطولاتك الجارية»: the live (or upcoming) tournaments the person joined, each with leave.
class _ActiveTournaments extends ConsumerWidget {
  const _ActiveTournaments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final list = ref.watch(tournamentsProvider).valueOrNull?.value ?? const <Tournament>[];
    final active = list.where((x) => x.joined && !x.closed && x.phase != TournamentPhase.ended).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: YqSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YqHeading(t.cmActiveTournaments),
          YqGroup(
            children: [
              for (final x in active)
                YqListRow(
                  title: x.title(locale),
                  onTap: () => context.push('/profile/tournaments/${x.id}'),
                  trailing: YqButton.text(
                    label: t.cmLeaveTournament,
                    onPressed: () async {
                      final ok = await confirmLeave(context, title: t.cmLeaveTournament, body: t.cmLeaveTournamentBody);
                      if (ok) await leaveTournament(ref, x.id);
                    },
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// «المحظورون» with «إلغاء الحظر».
class _Blocked extends ConsumerWidget {
  const _Blocked();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(blocksProvider);
    final list = async.valueOrNull?.value;
    if (list == null) {
      if (async.hasError) return YqErrorState(onRetry: () => ref.invalidate(blocksProvider));
      return const YqSkeleton(child: YqSkeletonRows(rows: 2, leading: 36));
    }
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: YqSpace.s),
        child: Text(t.cmBlockedEmpty, style: const TextStyle(color: YqColors.muted)),
      );
    }
    return YqGroup(
      children: [
        for (final b in list)
          YqListRow(
            leading: YqAvatar(avatar: b.avatar, size: 36, name: b.name ?? t.avHiddenName),
            title: (b.name?.trim().isNotEmpty ?? false) ? b.name! : t.avHiddenName,
            subtitle: '@${b.handle}',
            trailing: YqButton.text(
              label: t.cmUnblock,
              onPressed: () async {
                final r = await ref.read(communityRepositoryProvider).unblock(b.handle);
                if (!context.mounted) return;
                if (r.isOk) {
                  ref.read(hiddenHandlesProvider.notifier).unhide(b.handle);
                  ref.invalidate(blocksProvider);
                } else {
                  YqToast.show(context, t.errorGeneric);
                }
              },
            ),
          ),
      ],
    );
  }
}
