import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../rewards/domain/reward.dart';
import '../../rewards/presentation/ledger_providers.dart';

/// «سجل النقاط» (`/profile/ledger`) — the user's own ledger (amounts and reasons; never which
/// worship act).
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final ledger = ref.watch(ledgerProvider);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    String reason(LedgerReason r) => switch (r) {
          LedgerReason.task => t.ledgerTask,
          LedgerReason.bonus => t.ledgerBonus,
          LedgerReason.milestone => t.ledgerMilestone,
          LedgerReason.grant => t.ledgerGrant,
          LedgerReason.qada => t.ledgerQada,
          LedgerReason.redemption => t.ledgerRedemption,
          LedgerReason.adminAdjustment => t.ledgerAdjust,
          LedgerReason.reversal => t.ledgerReversal,
        };
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.profileLedger)),
        children: ledger.when(
          loading: () => [const YqSkeleton(child: YqSkeletonRows(rows: 4, leading: 0, trailing: true))],
          error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(ledgerProvider))],
          data: (list) => list.isEmpty
              ? [LiquidGlass(child: YqEmptyState(icon: YqIcons.challenge, title: t.ledgerEmpty))]
              : [
                  LiquidGlass(
                    padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                    child: Column(
                      children: [
                        for (final e in list)
                          YqListRow(
                            dense: true,
                            title: reason(e.reason),
                            subtitle: YqFormat.fullDate(e.createdAt.toLocal(), locale),
                            trailing: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                '${e.delta > 0 ? '+' : '−'}${YqFormat.number(e.delta.abs())}',
                                style: YqText.numberSmall.copyWith(color: e.delta > 0 ? YqColors.success : YqColors.muted),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}
