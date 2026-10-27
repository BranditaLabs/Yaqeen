import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/data/consent_repository.dart';
import '../../calendar/domain/hijri_day.dart';
import '../../home/data/widget_snapshot.dart';
import '../../ramadan/domain/ramadan.dart';
import '../../ramadan/presentation/ramadan_controller.dart';
import '../data/reminder_service.dart';

/// Inputs from other features that change the reminder schedule.
class ReminderInputs {
  const ReminderInputs({
    this.wirdDoneToday = false,
    this.wirdPages = 0,
    this.hifzDue = const {},
    this.ramadanDates = const {},
    this.hijriToday,
  });
  final bool wirdDoneToday;
  final int wirdPages;

  /// Today's Hijri date from the cached calendar (for the home-screen widget), null if unknown.
  final HijriDay? hijriToday;
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
  HijriDay? hijri;
  try {
    final d = Zoned.today(s.placeOrDefault.timezone, ref.read(clockProvider)());
    final month = await ref
        .read(calendarRepositoryProvider)
        .month(d.year, d.month, personalOffset: s.hijriOffsetDays, regionalOffset: config.hijriOffsetDays, preferCache: true);
    hijri = month.where((h) => h.gregorian == today).firstOrNull;
  } on Exception {
    hijri = null; // offline and never cached: the widget simply shows no Hijri line
  }
  final pagesToday = wird != null && wird.date == today ? wird.count : 0;
  return ReminderInputs(
    wirdDoneToday: wird != null && wird.date == today && wird.count >= s.wirdGoalPages,
    wirdPages: pagesToday,
    hijriToday: hijri,
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
    await _publishWidget(s, now, inputs);
  }

  /// The home-screen widgets follow the same inputs (spec §5.28). Never fails a re-plan.
  Future<void> _publishWidget(AppSettings s, DateTime now, ReminderInputs inputs) async {
    try {
      final h = inputs.hijriToday;
      final todayDate = Zoned.today(s.placeOrDefault.timezone, now);
      final json = WidgetSnapshot.build(
        settings: s,
        prayers: ref.read(prayerRepositoryProvider),
        now: now,
        t: lookupAppLocalizations(Locale(s.locale)),
        hijri: h == null ? null : '${h.hijriDay} ${h.monthNameAr} ${h.hijriYear}',
        wirdPages: inputs.wirdPages,
        ramadanDay: inputs.ramadanDates.contains(todayDate) && h != null && h.hijriMonth == ramadanMonth ? h.hijriDay : null,
        ramadanDates: inputs.ramadanDates,
      );
      await ref.read(homeWidgetPublisherProvider).publish(json);
    } catch (_) {
      // No widget on this platform / plugin unavailable: the app is unaffected.
    }
  }
}

final remindersControllerProvider = NotifierProvider<RemindersController, DateTime?>(RemindersController.new);
