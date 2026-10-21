import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';

/// The four consent buckets (Egypt PDPL 151/2020: explicit, specific, revocable).
enum ConsentKind {
  worshipReminders('worship_reminders'),
  challengeRewards('challenge_rewards'),
  storeOffers('store_offers'),
  adsMeasurement('ads_measurement');

  const ConsentKind(this.wire);
  final String wire;
}

enum ConsentSource { onboarding, settings, systemPrompt }

/// Consents are stored locally first (they gate analytics immediately, even offline)
/// and synced to the server, which keeps the legal record.
class ConsentRepository {
  ConsentRepository({required this.api, required this.store});

  final ApiClient api;
  final KvStore store;
  static const _key = 'consents.v1';

  Map<ConsentKind, bool> _cache = {for (final k in ConsentKind.values) k: false};

  bool granted(ConsentKind k) => _cache[k] ?? false;

  Future<void> load() async {
    final raw = await store.read(_key);
    if (raw == null) return;
    final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
    _cache = {for (final k in ConsentKind.values) k: m[k.wire] == true};
  }

  Future<void> set(ConsentKind kind, bool value, ConsentSource source) async {
    _cache = {..._cache, kind: value};
    await store.write(_key, jsonEncode({for (final e in _cache.entries) e.key.wire: e.value}));
    try {
      await api.put('/v1/me/consents', {
        'kind': kind.wire,
        'granted': value,
        'source': switch (source) {
          ConsentSource.onboarding => 'onboarding',
          ConsentSource.settings => 'settings',
          ConsentSource.systemPrompt => 'system_prompt',
        },
      });
    } on OfflineException {
      // Local state already applied; synced on next launch by [syncAll].
    }
  }

  Future<void> syncAll() async {
    for (final k in ConsentKind.values) {
      try {
        await api.put('/v1/me/consents', {'kind': k.wire, 'granted': granted(k), 'source': 'settings'});
      } on OfflineException {
        return;
      }
    }
  }
}
