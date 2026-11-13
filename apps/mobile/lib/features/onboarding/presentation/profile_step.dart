import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Onboarding step 05·ج «ملفّك» at `/onboarding/profile` (APP_SPEC §5.7·ج).
///
/// Stub registered by the contracts stream; the home-onboarding stream builds the step. Until then
/// it only continues to the download step.
class ProfileStep extends StatelessWidget {
  const ProfileStep({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(title: t.obProfileTitle)),
        children: [
          Text(t.obProfileSub),
          const SizedBox(height: YqSpace.l),
          FilledButton(onPressed: () => context.go('/onboarding/download'), child: Text(t.obContinue)),
        ],
      ),
    );
  }
}
