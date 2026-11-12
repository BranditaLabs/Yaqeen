import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import '../../calendar/data/hijri_today.dart';
import '../data/ramadan_repository.dart';
import '../domain/ramadan.dart';

final ramadanRepositoryProvider = Provider(
  (ref) => RamadanRepository(calendar: ref.watch(calendarRepositoryProvider), store: ref.watch(kvStoreProvider)),
);

/// Ramadan, Sha'ban (countdown) or nothing — from today's Hijri date and the admin flag.
final ramadanStatusProvider = Provider.autoDispose<RamadanStatus>((ref) {
  final flag = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.ramadan)));
  return RamadanStatus.of(ref.watch(hijriTodayProvider).valueOrNull, flag: flag);
});

/// The imsakiyya's days for the Ramadan being shown (empty when none).
final ramadanDaysProvider = FutureProvider.autoDispose<List<RamadanDay>>((ref) async {
  final status = ref.watch(ramadanStatusProvider);
  if (!status.visible) return const [];
  final s = ref.watch(settingsProvider);
  final regional = ref.watch(remoteConfigProvider.select((c) => c.hijriOffsetDays));
  final today = ref.read(prayerRepositoryProvider).today(s, ref.read(clockProvider)());
  return ref.read(ramadanRepositoryProvider).month(status.ramadanYear, today, personalOffset: s.hijriOffsetDays, regionalOffset: regional);
});

/// The month's tracker (fasts, taraweeh, khatma) — device first; optional encrypted cloud backup
/// (consent `cloud_backup`). Ticking today's fast or taraweeh,
/// or a juz, also claims the matching bonus when the admin has enabled it; un-ticking never takes
/// points back (the ledger is append-only).
class RamadanLogController extends AutoDisposeAsyncNotifier<RamadanLog> {
  @override
  Future<RamadanLog> build() async {
    final status = ref.watch(ramadanStatusProvider);
    if (!status.visible) return const RamadanLog();
    return ref.read(ramadanRepositoryProvider).log(status.ramadanYear);
  }

  Future<void> toggle(RamadanTrack track, int value) async {
    final status = ref.read(ramadanStatusProvider);
    final current = state.valueOrNull;
    if (current == null || !status.active) return;
    final next = current.toggle(track, value);
    state = AsyncData(next);
    await ref.read(ramadanRepositoryProvider).save(status.ramadanYear, next);
    final ticked = next.has(track, value);
    final today = track == RamadanTrack.juz || value == status.hijriDay;
    if (ticked && today && bonusPointsFor(ref.read(remoteConfigProvider), track) != null) {
      final s = ref.read(settingsProvider);
      final date = Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.read(clockProvider)()));
      await ref.read(challengeRepositoryProvider).claimBonus(track.bonusWire, date);
    }
  }
}

/// Points a tick earns when the admin has switched bonuses and this one on; null otherwise.
int? bonusPointsFor(RemoteConfig c, RamadanTrack track) => c.isOn(Flags.bonuses) ? c.bonusPoints[track.bonusWire] : null;

final ramadanLogProvider = AsyncNotifierProvider.autoDispose<RamadanLogController, RamadanLog>(RamadanLogController.new);
