import 'dart:convert';

import '../offline/outbox.dart';
import '../storage/kv_store.dart';
import 'app_settings.dart';

/// Local source of truth for [AppSettings]; mirrors the server subset through the Outbox
/// (`PATCH /v1/me/settings`) so changes made offline still reach the API (spec §6.2).
class SettingsRepository {
  SettingsRepository({required this.store, required this.outbox});

  final KvStore store;
  final Outbox outbox;
  static const _key = 'settings.v1';

  Future<AppSettings> load() async {
    final raw = await store.read(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } on FormatException {
      return const AppSettings();
    }
  }

  /// Saves locally and, when a server-side field changed and [syncToServer], queues one PATCH.
  Future<void> save(AppSettings next, {AppSettings? previous, bool syncToServer = true}) async {
    await store.write(_key, jsonEncode(next.toJson()));
    if (!syncToServer) return;
    final before = previous?.serverPatch();
    final after = next.serverPatch();
    final changed = {
      for (final e in after.entries)
        if (before == null || before[e.key] != e.value) e.key: e.value,
    };
    if (changed.isEmpty) return;
    // Only the latest value matters: drop older queued settings patches.
    await outbox.removeWhere((i) => i.path == '/v1/me/settings');
    await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'PATCH', path: '/v1/me/settings', body: after));
  }
}
