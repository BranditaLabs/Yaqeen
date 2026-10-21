import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import 'app_settings.dart';

/// App-wide settings. Every change is saved immediately (kill-safe, spec §6.2).
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings s) change, {bool sync = true}) async {
    final previous = state;
    final next = change(previous);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next, previous: previous, syncToServer: sync);
    if (sync) ref.read(outboxSyncProvider).flush().ignore();
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
