import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';

/// `/profile/leaderboard` (APP_SPEC §5.31.3): the level board (world and country).
///
/// Stub registered by the contracts stream (design §14); the owning stream fills it in.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.cmLeaderboardTitle)),
      ),
    );
  }
}
