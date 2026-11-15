import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../community/presentation/community_widgets.dart';
import '../../community/presentation/join_sheets.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../profile/presentation/me_profile_controller.dart';
import '../domain/recording_models.dart';

/// Sharing a recording with members (or on the public card), reacting, commenting and reporting
/// need an account, the 18+ attestation and the community opt-in (design doc §16.3). The server is
/// the judge: the app asks for sign-in up front, then tries, and answers `attestation_required` /
/// `community_required` with the competitions' own join sheets ([showShareGate]) — the same switch
/// «عمري 18 عاماً أو أكثر…», privacy line and terms.

/// Signed in (asks with the sign-in sheet when not) and not banned from the competitions. False
/// when the person cannot share now.
Future<bool> ensureAccountForSharing(BuildContext context, WidgetRef ref) async {
  final t = AppLocalizations.of(context);
  if (!ref.read(sessionProvider).canEarnPoints) {
    final ok = await showSignInSheet(context, title: t.recSignInToShare);
    if (!ok || !context.mounted) return false;
  }
  if (ref.read(meProfileProvider).valueOrNull?.community.banned ?? false) {
    YqToast.show(context, t.recGateBanned);
    return false;
  }
  return true;
}

/// Whether [f] is a gate the join sheets can open.
bool isShareGate(RecordingFailure f) => f == RecordingFailure.attestationRequired || f == RecordingFailure.communityRequired;

/// The sheet after a gate refusal: join the level board or the weekly league (whichever is on),
/// each with its own attestation switch. True when the person joined (retry the action).
Future<bool> showShareGate(BuildContext context) async => await showYqSheet<bool>(context, scrollable: true, builder: (_) => const ShareGateSheet()) ?? false;

class ShareGateSheet extends ConsumerWidget {
  const ShareGateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final config = ref.watch(remoteConfigProvider);
    final board = config.isOn(Flags.leaderboard);
    final league = config.isOn(Flags.leagues);
    final banned = ref.watch(meProfileProvider).valueOrNull?.community.banned ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.recGateTitle, style: text.titleLarge)),
        const SizedBox(height: YqSpace.s),
        Text(t.recGateBody, style: text.bodyMedium?.copyWith(color: YqColors.muted, height: 1.6)),
        const SizedBox(height: YqSpace.l),
        if (banned)
          InlineFailure(t.recGateBanned)
        else if (!board && !league)
          InlineFailure(t.recGateUnavailable)
        else ...[
          if (board)
            YqButton(
              key: const ValueKey('rec-gate-board'),
              label: t.recGateJoinBoard,
              onPressed: () async {
                final ok = await showJoinBoardSheet(context);
                if (context.mounted && ok) Navigator.of(context).pop(true);
              },
            ),
          if (board && league) const SizedBox(height: YqSpace.s),
          if (league)
            YqButton.secondary(
              key: const ValueKey('rec-gate-league'),
              label: t.recGateJoinLeague,
              onPressed: () async {
                final ok = await showJoinLeagueSheet(context);
                if (context.mounted && ok) Navigator.of(context).pop(true);
              },
            ),
        ],
        const SizedBox(height: YqSpace.m),
        const CommunityTermsLink(),
      ],
    );
  }
}
