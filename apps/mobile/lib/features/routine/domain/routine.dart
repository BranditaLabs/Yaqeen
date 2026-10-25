import 'package:timezone/timezone.dart' as tz;

import '../../../core/settings/routine_slot.dart';
import '../../../core/time/zoned.dart';
import '../../prayer/domain/prayer_calculator.dart';

export '../../../core/settings/routine_slot.dart';

/// The user's daily habits, in the order the routine step and settings show them.
enum Habit { quran, hifz, dhikr }

/// Today's instant (UTC) for [slot] given that day's prayer [times] at a place in [timezone];
/// null when the habit is off.
DateTime? resolveSlot(RoutineSlot slot, PrayerDayTimes times, String timezone) => switch (slot.kind) {
      SlotKind.off => null,
      SlotKind.afterPrayer => times.of(slot.prayer!).add(Duration(minutes: slot.minutes)),
      SlotKind.at =>
        tz.TZDateTime(Zoned.location(timezone), times.year, times.month, times.day).add(Duration(minutes: slot.minutes)).toUtc(),
    };
