import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';

/// `/profile/leagues` (APP_SPEC §5.31.1): the weekly league.
///
/// Stub registered by the contracts stream (design §14); the owning stream fills it in.
class LeagueScreen extends StatelessWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.cmLeagueTitle)),
      ),
    );
  }
}
