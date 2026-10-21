import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../data/challenge_repository.dart';
import '../domain/challenge_models.dart';

class ChallengeController extends AsyncNotifier<ChallengeSummary> {
  @override
  Future<ChallengeSummary> build() => ref.read(challengeRepositoryProvider).summary();

  /// Optimistic: the tick appears instantly; the outbox guarantees delivery. Returns the API error
  /// code when the server rejects it (the tick is then reverted), e.g. `day_closed`.
  Future<String?> complete(TaskKey task) async {
    final current = state.valueOrNull;
    final today = current?.today;
    if (current == null || today == null || today.completed.contains(task)) return null;
    state = AsyncData(current.completeLocally(task));
    final result = await ref.read(challengeRepositoryProvider).complete(task, today.date);
    if (result.outcome == TickOutcome.rejected) {
      state = AsyncData(current);
      return result.code ?? 'rejected';
    }

    final after = state.valueOrNull;
    if (after != null && after.today?.status == DayStatus.done) {
      // Marketing milestones only — never the worship action itself.
      if (after.streak + 1 == 7) await ref.read(analyticsProvider).log(AdEvent.streak7);
      if (after.streak + 1 == 30) await ref.read(analyticsProvider).log(AdEvent.streak30);
    }
    if (after != null && after.todayComplete) {
      // The server may have added a streak milestone bonus — pull the real balance.
      ref.invalidateSelf();
    }
    return null;
  }

  Future<void> enroll() async {
    await ref.read(challengeRepositoryProvider).enroll();
    await ref.read(analyticsProvider).log(AdEvent.challengeJoin);
    ref.invalidateSelf();
  }
}

final challengeControllerProvider = AsyncNotifierProvider<ChallengeController, ChallengeSummary>(ChallengeController.new);
