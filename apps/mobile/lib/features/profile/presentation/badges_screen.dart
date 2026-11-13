import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../community/domain/community_models.dart';
import '../../onboarding/presentation/session_controller.dart';
import 'badges_strip.dart';

/// Every badge the caller has earned (GET /v1/me/badges), newest first. Guests have none.
final myBadgesProvider = FutureProvider.autoDispose<List<Badge>>((ref) async {
  if (!ref.watch(sessionProvider).canEarnPoints) return const [];
  return ref.watch(cardRepositoryProvider).badges();
});

/// `/profile/badges` (APP_SPEC §5.31.4): the earned badges in three sections — league, tournaments,
/// journey — as gold medals with their date. Only earned badges are drawn (no locked placeholders).
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  static const columns = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final badges = ref.watch(myBadgesProvider);
    final list = badges.valueOrNull;
    // Shimmer only while the first load is on its way; a failed load ends on «—» (the body retries).
    final Widget moment = badges.isLoading && !badges.hasValue
        ? const YqSkeleton(
            child: Column(
              children: [
                YqSkeletonBox(width: 64, height: 44, radius: YqRadii.chip),
                SizedBox(height: YqSpace.s),
                YqSkeletonBox(width: 48, height: 12, radius: YqRadii.pill),
              ],
            ),
          )
        : YqMoment(
            value: Text(list == null ? t.pfNoRank : YqFormat.number(list.length), style: YqMoment.numeral()),
            caption: Text(t.pfBadgeUnit),
          );

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        onRefresh: () async {
          ref.invalidate(myBadgesProvider);
          try {
            await ref.read(myBadgesProvider.future);
          } on Object {
            // The error state offers a retry.
          }
        },
        stage: YqStage(
          compact: true,
          child: Column(
            children: [
              YqStageBar(back: true, title: t.pfBadges),
              const SizedBox(height: YqSpace.l),
              moment,
            ],
          ),
        ),
        children: switch (badges) {
          AsyncValue(:final valueOrNull?) => _sections(t, valueOrNull),
          AsyncError() => [
              LiquidGlass(child: YqErrorState(message: t.pfBadgesError, onRetry: () => ref.invalidate(myBadgesProvider))),
            ],
          _ => [
              YqSkeleton(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const YqSkeletonBox(width: 72, height: 14, radius: YqRadii.pill),
                    const SizedBox(height: YqSpace.l),
                    for (var r = 0; r < 2; r++) ...[
                      Row(
                        children: [
                          for (var c = 0; c < columns; c++)
                            const Expanded(
                              child: Column(
                                children: [
                                  YqSkeletonBox.circle(64),
                                  SizedBox(height: YqSpace.s),
                                  YqSkeletonBox(width: 60, height: 10, radius: YqRadii.pill),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: YqSpace.xl),
                    ],
                  ],
                ),
              ),
            ],
        },
      ),
    );
  }

  List<Widget> _sections(AppLocalizations t, List<Badge> list) {
    if (list.isEmpty) return [LiquidGlass(child: YqEmptyState(icon: YqIcons.badge, title: t.pfBadgesEmpty))];
    final sections = [
      (t.pfBadgesLeague, list.where((b) => b.kind.isLeague).toList()),
      (t.pfBadgesTournaments, list.where((b) => b.kind.isTournament).toList()),
      (t.pfBadgesJourney, list.where((b) => !b.kind.isLeague && !b.kind.isTournament).toList()),
    ];
    return [
      for (final (title, items) in sections)
        if (items.isNotEmpty) ...[
          YqHeading(title),
          for (var i = 0; i < items.length; i += columns) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++)
                  Expanded(
                    child: i + c < items.length
                        ? Center(child: BadgeMedal(badge: items[i + c], size: 64, showDate: true, width: 104))
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
            const SizedBox(height: YqSpace.l),
          ],
          const SizedBox(height: YqSpace.s),
        ],
    ];
  }
}
