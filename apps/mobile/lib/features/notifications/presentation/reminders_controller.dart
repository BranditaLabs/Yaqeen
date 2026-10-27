import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/data/consent_repository.dart';
import '../../ramadan/presentation/ramadan_controller.dart';
import '../data/reminder_service.dart';

/// Inputs from other features that change the reminder schedule.
class ReminderInputs {
  const ReminderInputs({this.wirdDoneToday = false, this.hifzDue = const {}, this.ramadanDates = const {}});
  final bool wirdDoneToday;
  final Set<DateTime> hifzDue;

  /// Ramadan days in the planning window — only while the admin's `ramadan` flag is on.
  final Set<DateTime> ramadanDates;
}

/// Today's wird and the hifz review days, both read from the device stores.
final reminderInputsProvider = FutureProvider<ReminderInputs>((ref) async {
  final s = ref.read(settingsProvider);
  final today = Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.read(clockProvider)()));
  final wird = await ref.read(readingRepositoryProvider).wird();
  final hifz = await ref.read(hifzRepositoryProvider).load();
  final config = ref.read(remoteConfigProvider);
  final ramadan = config.isOn(Flags.ramadan)
      ? await ref.read(ramadanRepositoryProvider).ramadanDatesAhead(
            Zoned.today(s.placeOrDefault.timezone, ref.read(clockProvider)()),
            ReminderService.daysAhead,
            personalOffset: s.hijriOffsetDays,
            regionalOffset: config.hijriOffsetDays,
          )
      : const <DateTime>{};
  return ReminderInputs(
    wirdDoneToday: wird != null && wird.date == today && wird.count >= s.wirdGoalPages,
    hifzDue: hifz?.dueDates() ?? const {},
    ramadanDates: ramadan,
  );
});

/// Keeps the local notification schedule in sync (spec §6.5): re-plans when settings change and on
/// demand (start, resume, wird done, hifz rated). Also moves delivered reminders into the inbox.
class RemindersController extends Notifier<DateTime?> {
  Timer? _next;

  @override
  DateTime? build() {
    ref.listen(settingsProvider, (prev, next) {
      if (prev != next) replan();
    });
    ref.onDispose(() => _next?.cancel());
    return null;
  }

  /// While the app stays open, re-plan when the window runs out or just after local midnight
  /// (a new day: new prayer times, wird reset), whichever comes first (spec §6.5).
  void _scheduleNext(DateTime? replanBefore) {
    _next?.cancel();
    final s = ref.read(settingsProvider);
    final now = ref.read(clockProvider)();
    final today = Zoned.today(s.placeOrDefault.timezone, now);
    final next = DateTime(today.year, today.month, today.day + 1);
    // 00:01 tomorrow in the place's zone, as an instant.
    final tomorrow = tz.TZDateTime(Zoned.location(s.placeOrDefault.timezone), next.year, next.month, next.day, 0, 1).toUtc();
    DateTime at = tomorrow;
    if (replanBefore != null && replanBefore.isBefore(at)) at = replanBefore;
    final wait = at.difference(now.toUtc());
    _next = Timer(wait.isNegative ? const Duration(minutes: 1) : wait, () => replan().ignore());
  }

  Future<void> replan() async {
    final s = ref.read(settingsProvider);
    final now = ref.read(clockProvider)();
    ref.invalidate(reminderInputsProvider);
    final inputs = await ref.read(reminderInputsProvider.future);
    final consents = ref.read(consentRepositoryProvider);
    final service = ref.read(reminderServiceProvider);
    await service.collectDelivered(s, now, lookupAppLocalizations(Locale(s.locale)));
    final plan = await service.replan(
      s,
      now: now,
      worshipConsent: consents.granted(ConsentKind.worshipReminders),
      wirdDone: inputs.wirdDoneToday,
      hifzDue: inputs.hifzDue,
      ramadanDates: inputs.ramadanDates,
    );
    state = plan.replanBefore;
    _scheduleNext(plan.replanBefore);
  }
}

final remindersControllerProvider = NotifierProvider<RemindersController, DateTime?>(RemindersController.new);
