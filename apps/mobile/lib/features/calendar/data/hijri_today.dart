import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import '../domain/hijri_day.dart';

/// Today's Hijri date from the cached Umm al-Qura month (instant; refreshed in the background) (+ Egypt and personal offsets); null when
/// neither the network nor the cache has it — Home then simply hides the line.
final hijriTodayProvider = FutureProvider.autoDispose<HijriDay?>((ref) async {
  final s = ref.watch(settingsProvider);
  final regional = ref.watch(remoteConfigProvider).hijriOffsetDays;
  final today = Zoned.today(s.placeOrDefault.timezone, ref.watch(clockProvider)());
  try {
    final days = await ref
        .read(calendarRepositoryProvider)
        .month(today.year, today.month, personalOffset: s.hijriOffsetDays, regionalOffset: regional, preferCache: true);
    final iso = Zoned.isoDate(today);
    return days.where((d) => d.gregorian == iso).firstOrNull;
  } on Exception {
    return null;
  }
});
