import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import '../../card/presentation/journey_widgets.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../data/challenge_repository.dart';
import '../domain/challenge_models.dart';

class ChallengeController extends AsyncNotifier<ChallengeSummary> {
  /// The place's date now (YYYY-MM-DD) — the day a tick belongs to.
  String _localToday() {
    final zone = ref.read(settingsProvider).placeOrDefault.timezone;
    return Zoned.isoDate(Zoned.today(zone, ref.read(clockProvider)()));
  }

  /// Cache first, so Home paints the card instantly; the server's summary replaces it when it
  /// answers. With nothing cached, waits for the network as before. Rebuilds at the next local
  /// midnight, so a screen left open never keeps yesterday's ticks as today's.
  @override
  Future<ChallengeSummary> build() async {
    // Another account (sign-in, sign-out, ended session) never sees this one's summary.
    ref.watch(sessionProvider.select((s) => s.userId));
    final repo = ref.read(challengeRepositoryProvider);
    final today = _localToday();
    final zone = ref.read(settingsProvider).placeOrDefault.timezone;
    final now = ref.read(clockProvider)();
    final midnight = Timer(Zoned.nextMidnight(zone, now).difference(now.toUtc()) + const Duration(seconds: 1), ref.invalidateSelf);
    ref.onDispose(midnight.cancel);
    final cached = await repo.cachedSummary(today: today).catchError((Object _) => null);
    if (cached == null) return repo.summary(today: today);
    var alive = true;
    ref.onDispose(() => alive = false);
    Future(() async {
      try {
        final fresh = await repo.summary(today: today);
        if (alive) state = AsyncData(fresh);
      } catch (_) {
        // Offline or server error: the cached summary stays.
      }
    });
    return cached;
  }

  /// On resume: the day changed while the app was away (timers don't run in the background).
  void refreshIfNewDay() {
    final date = state.valueOrNull?.today?.date;
    if (date != null && date != _localToday()) ref.invalidateSelf();
  }

  /// Optimistic: the tick appears instantly; the outbox guarantees delivery. Returns the API error
  /// code when the server rejects it (the tick is then reverted), e.g. `day_closed`.
  Future<String?> complete(TaskKey task) async {
    var current = state.valueOrNull;
    if (current?.today case final shown? when shown.date != _localToday()) {
      // Past local midnight on a summary from an earlier day: never tick yesterday (the server
      // would file it as qada). The server's summary, or offline the cached one moved on to today.
      final date = _localToday();
      try {
        current = await ref.read(challengeRepositoryProvider).summary(today: date);
      } catch (_) {
        current = current?.rolledTo(date);
      }
      if (current != null) state = AsyncData(current);
    }
    final today = current?.today;
    if (current == null || today == null || today.completed.contains(task)) return null;
    state = AsyncData(current.completeLocally(task));
    final result = await ref.read(challengeRepositoryProvider).complete(task, today.date);
    if (result.outcome == TickOutcome.rejected) {
      state = AsyncData(current);
      return result.code ?? 'rejected';
    }
    // The server counted the points: the level and lifetime points on Profile move with them.
    if (result.outcome == TickOutcome.synced) ref.invalidate(myJourneyProvider);

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
