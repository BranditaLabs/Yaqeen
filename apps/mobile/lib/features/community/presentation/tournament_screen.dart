import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';

/// `/profile/tournaments/:id` (APP_SPEC §5.31.2): one tournament and its standings.
///
/// Stub registered by the contracts stream (design §14); the owning stream fills it in.
class TournamentScreen extends StatelessWidget {
  const TournamentScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.cmTournaments)),
      ),
    );
  }
}
