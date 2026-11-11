import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../core/storage/kv_store.dart';

/// The consent buckets (Egypt PDPL 151/2020: explicit, specific, revocable). `cloudBackup` is the
/// opt-in encrypted copy of personal progress — signed-in accounts only, set from Privacy (never in
/// onboarding), and withdrawing it deletes the server copy.
enum ConsentKind {
  worshipReminders('worship_reminders'),
  challengeRewards('challenge_rewards'),
  storeOffers('store_offers'),
  adsMeasurement('ads_measurement'),
  productAnalytics('product_analytics'),
  cloudBackup('cloud_backup');

  const ConsentKind(this.wire);
  final String wire;
}

enum ConsentSource { onboarding, settings, systemPrompt }

/// Defaults shown on the consent step (spec §5.6): reminders and challenge on; offers and ads off.
const consentDefaults = {
  ConsentKind.worshipReminders: true,
  ConsentKind.challengeRewards: true,
  ConsentKind.storeOffers: false,
  ConsentKind.adsMeasurement: false,
  ConsentKind.productAnalytics: false,
  ConsentKind.cloudBackup: false,
};

/// The kinds the onboarding consent step asks about (cloud backup needs an account, so it lives in Privacy).
const onboardingConsents = [
  ConsentKind.worshipReminders,
  ConsentKind.challengeRewards,
  ConsentKind.storeOffers,
  ConsentKind.adsMeasurement,
  ConsentKind.productAnalytics,
];

/// Consents are stored locally first (they gate analytics immediately, even offline) and synced
/// to the server, which keeps the legal record. Every change is an event; events that could not
/// be sent yet (offline, or a guest not yet created on the server) are replayed in order with
/// their original source.
class ConsentRepository {
  ConsentRepository({required this.api, required this.store});

  final ApiClient api;
  final KvStore store;
  static const _key = 'consents.v1';
  static const _pendingKey = 'consents.pending.v1';
  static const _decidedKey = 'consents.decided';

  Map<ConsentKind, bool> _cache = {for (final k in ConsentKind.values) k: false};
  bool _decided = false;

  bool granted(ConsentKind k) => _cache[k] ?? false;
  Map<ConsentKind, bool> get all => Map.unmodifiable(_cache);

  /// The user has passed the consent step (until then, install events wait — spec §5.3).
  bool get decided => _decided;

  Future<void> load() async {
    _decided = await store.read(_decidedKey) == '1';
    final raw = await store.read(_key);
    if (raw == null) return;
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      _cache = {for (final k in ConsentKind.values) k: m[k.wire] == true};
    } catch (_) {
      // Unreadable: everything stays off (the privacy-safe default) until the user decides again.
    }
  }

  static String _sourceWire(ConsentSource s) => switch (s) {
        ConsentSource.onboarding => 'onboarding',
        ConsentSource.settings => 'settings',
        ConsentSource.systemPrompt => 'system_prompt',
      };

  Future<void> set(ConsentKind kind, bool value, ConsentSource source) async {
    await record(kind, value, source);
    await syncAll();
  }

  /// Applies the choice on this phone and queues its event, without waiting for the network —
  /// a switch flips at once; [syncAll] delivers the event.
  Future<void> record(ConsentKind kind, bool value, ConsentSource source) async {
    _cache = {..._cache, kind: value};
    await store.write(_key, jsonEncode({for (final e in _cache.entries) e.key.wire: e.value}));
    final pending = await _pending();
    await store.write(
      _pendingKey,
      jsonEncode([
        ...pending,
        {'kind': kind.wire, 'granted': value, 'source': _sourceWire(source)},
      ]),
    );
  }

  /// Takes the server's answer without recording a new event — the decision was already recorded
  /// (on another phone, or the server refused it). Used by the cloud backup only.
  Future<void> adopt(ConsentKind kind, bool value) async {
    _cache = {..._cache, kind: value};
    await store.write(_key, jsonEncode({for (final e in _cache.entries) e.key.wire: e.value}));
  }

  /// A change of [kind] is still waiting to reach the server (offline).
  Future<bool> pending(ConsentKind kind) async => (await _pending()).any((e) => e['kind'] == kind.wire);

  /// The server's current answers (`GET /v1/me/consents`); throws when offline.
  Future<Map<ConsentKind, bool>> fetchServer() async {
    final m = ((await api.get('/v1/me/consents')) as Map).cast<String, dynamic>();
    return {for (final k in ConsentKind.values) k: m[k.wire] == true};
  }

  Future<void> markDecided() async {
    _decided = true;
    await store.write(_decidedKey, '1');
  }

  Future<List<Map<String, dynamic>>> _pending() async {
    final raw = await store.read(_pendingKey);
    return raw == null ? [] : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void>? _syncing;

  /// Sends queued consent events in order; stops (keeping the rest) when offline, signed out or
  /// the server is failing. Calls run one after another, so quick taps never send an event twice.
  Future<void> syncAll() {
    final run = (_syncing ?? Future<void>.value()).catchError((Object _) {}).then((_) => _syncOnce());
    _syncing = run;
    return run.whenComplete(() {
      if (identical(_syncing, run)) _syncing = null;
    });
  }

  Future<void> _syncOnce() async {
    final pending = await _pending();
    var sent = 0;
    for (final e in pending) {
      try {
        await api.put('/v1/me/consents', e);
        sent++;
      } on OfflineException {
        break;
      } on ApiException catch (err) {
        // 401: no server account yet — retried after sign-in. 5xx/429: retried later.
        if (err.status == 401 || !err.isPermanent) break;
        sent++; // invalid payloads won't succeed later
      }
    }
    // Events recorded while this ran were appended: drop only the ones sent.
    if (sent == 0) return;
    final now = await _pending();
    await store.write(_pendingKey, jsonEncode(now.length > sent ? now.sublist(sent) : const []));
  }
}
