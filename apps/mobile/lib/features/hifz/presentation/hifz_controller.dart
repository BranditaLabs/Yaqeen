import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../notifications/presentation/reminders_controller.dart';
import '../domain/hifz_plan.dart';
import '../domain/review_scheduler.dart';

/// Hifz state, device first; optional encrypted cloud backup (consent `cloud_backup`, spec §5.25).
/// Every change re-plans the «مراجعة مستحقة» local reminders.
class HifzController extends AsyncNotifier<HifzPlan?> {
  @override
  Future<HifzPlan?> build() => ref.read(hifzRepositoryProvider).load();

  DateTime get _today {
    final n = ref.read(clockProvider)().toLocal();
    return DateTime(n.year, n.month, n.day);
  }

  Future<void> _commit(HifzPlan plan) async {
    state = AsyncData(plan);
    await ref.read(hifzRepositoryProvider).save(plan);
    ref.invalidate(reminderInputsProvider);
    ref.read(remindersControllerProvider.notifier).replan().ignore();
  }

  Future<void> savePlan(HifzGoal goal, int perDay) async {
    final current = state.valueOrNull;
    // Changing the goal keeps memorised portions — they still need review.
    await _commit(current == null ? HifzPlan(goal: goal, perDay: perDay) : current.copyWith(goal: goal, perDay: perDay));
  }

  Future<void> memoriseToday() async {
    final plan = state.valueOrNull;
    if (plan == null) return;
    final q = await ref.read(quranDataProvider.future);
    await _commit(plan.memorise(q, _today));
  }

  Future<void> rate(String portionId, ReviewGrade grade) async {
    final plan = state.valueOrNull;
    if (plan == null) return;
    await _commit(plan.rate(portionId, grade, _today));
  }
}

final hifzControllerProvider = AsyncNotifierProvider<HifzController, HifzPlan?>(HifzController.new);
