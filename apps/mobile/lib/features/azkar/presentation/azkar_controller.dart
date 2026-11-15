import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/time/zoned.dart';
import '../../challenge/domain/challenge_models.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../content/domain/content_item.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../domain/azkar_progress.dart';

/// Counts are applied synchronously (10 taps/s without drops) and written behind a short debounce;
/// a completed morning/evening set ticks its challenge task once a day (spec §5.19).
class AzkarController extends Notifier<AzkarDay> {
  Timer? _save;
  late final _store = ref.read(azkarStoreProvider);

  String get _today {
    final s = ref.read(settingsProvider);
    return Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.read(clockProvider)()));
  }

  @override
  AzkarDay build() {
    ref.onDispose(() {
      _save?.cancel();
      _store.saveDay(state).ignore();
    });
    final today = _today;
    _store.day().then((d) {
      final loaded = AzkarDay.forToday(d, today);
      // Taps made before the load finished are kept on top of the stored counts.
      final merged = AzkarDay(
        date: today,
        counts: {...loaded.counts, for (final e in state.counts.entries) e.key: e.value + (loaded.counts[e.key] ?? 0)},
        ticked: {...loaded.ticked, ...state.ticked},
      );
      state = merged;
    });
    return AzkarDay(date: today);
  }

  /// The provider lives as long as the app, so a screen resumed after midnight would still hold
  /// yesterday's counts: start the new day (the store keeps only the current one). Returns true when
  /// it rolled over.
  bool ensureToday() {
    final today = _today;
    if (state.date == today) return false;
    _save?.cancel();
    state = AzkarDay(date: today);
    return true;
  }

  /// Returns true when this tap finished the item.
  bool tap(ContentItem item, {required List<ContentItem> set, required ZikrSet kind}) {
    var day = state;
    if (day.date != _today) day = AzkarDay(date: _today);
    if (day.doneItem(item)) return false;
    day = day.tap(item);
    final settings = ref.read(settingsProvider);
    if (settings.haptics) HapticFeedback.lightImpact();
    if (settings.azkarSound) SystemSound.play(SystemSoundType.click);
    final finished = day.doneItem(item);
    if (day.doneSet(set) && !day.ticked.contains(kind.key)) {
      final wire = taskWireFor(kind);
      day = day.markTicked(kind);
      if (wire != null) _tick(TaskKey.fromWire(wire), day.date);
    }
    state = day;
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 400), () => _store.saveDay(state));
    return finished;
  }

  /// Cloud backup merged today's counts from another phone (never fewer than shown here).
  void adopt(AzkarDay day) {
    if (day.date != state.date) return;
    _save?.cancel();
    state = day;
    _store.saveDay(state).ignore();
  }

  void reset(ContentItem item) {
    state = state.reset(item);
    _store.saveDay(state).ignore();
  }

  Future<void> _tick(TaskKey task, String date) async {
    if (!ref.read(sessionProvider).canEarnPoints) return;
    await ref.read(challengeRepositoryProvider).complete(task, date);
    ref.invalidate(challengeControllerProvider);
  }
}

final azkarControllerProvider = NotifierProvider<AzkarController, AzkarDay>(AzkarController.new);
