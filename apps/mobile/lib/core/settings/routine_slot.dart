import '../../features/prayer/domain/prayer_calculator.dart';

enum SlotKind { afterPrayer, at, off }

/// When a daily habit happens (spec §5.2 routine step): a few minutes after a prayer, at a set
/// time, or not at all. Kept on the device only — never synced (worship timing is private).
class RoutineSlot {
  const RoutineSlot._(this.kind, this.prayer, this.minutes);

  /// [minutes] after [prayer]'s adhan.
  const RoutineSlot.afterPrayer(PrayerName prayer, [int minutes = 15]) : this._(SlotKind.afterPrayer, prayer, minutes);

  /// At [minutesOfDay] (local time at the user's place).
  const RoutineSlot.at(int minutesOfDay) : this._(SlotKind.at, null, minutesOfDay);

  static const off = RoutineSlot._(SlotKind.off, null, 0);

  final SlotKind kind;
  final PrayerName? prayer;
  final int minutes;

  bool get isOff => kind == SlotKind.off;

  Map<String, dynamic> toJson() => switch (kind) {
        SlotKind.afterPrayer => {'k': 'after', 'p': prayer!.name, 'm': minutes},
        SlotKind.at => {'k': 'at', 'm': minutes},
        SlotKind.off => {'k': 'off'},
      };

  /// Tolerant: anything unreadable gives [fallback].
  static RoutineSlot fromJson(Object? j, RoutineSlot fallback) {
    if (j is! Map) return fallback;
    final m = j['m'];
    switch (j['k']) {
      case 'after':
        final p = PrayerName.values.where((x) => x.name == j['p']).firstOrNull;
        return p == null || m is! int ? fallback : RoutineSlot.afterPrayer(p, m.clamp(0, 180));
      case 'at':
        return m is int && m >= 0 && m < 24 * 60 ? RoutineSlot.at(m) : fallback;
      case 'off':
        return off;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) => other is RoutineSlot && other.kind == kind && other.prayer == prayer && other.minutes == minutes;

  @override
  int get hashCode => Object.hash(kind, prayer, minutes);
}
