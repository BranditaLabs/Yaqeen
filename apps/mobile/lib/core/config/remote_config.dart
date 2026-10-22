import 'dart:convert';

import '../network/api_client.dart';
import '../storage/kv_store.dart';
import 'rollout.dart';

/// Flags the app reads (spec §6.15). A flag that is off hides its entry points entirely.
abstract final class Flags {
  static const challenge = 'challenge';
  static const rewards = 'rewards';
  static const hifz = 'hifz';
  static const listen = 'listen';
  static const bonuses = 'bonuses';
  static const recite = 'recite';
  static const ramadan = 'ramadan';
  static const tafsirFull = 'tafsirFull';
}

/// Mirror of `RemoteConfig` in packages/contracts/src/api.ts.
class RemoteConfig {
  const RemoteConfig({
    this.features = defaultFeatures,
    this.featureRollout = const {},
    this.minVersionIos = noMinimum,
    this.minVersionAndroid = noMinimum,
    this.maintenance = false,
    this.maintenanceAr = '',
    this.maintenanceEn = '',
    this.splashVerseAr = defaultSplashVerse,
    this.splashVerseRef = 'الحجر: 99',
    this.hijriOffsetDays = 0,
    this.dailyTotal = 100,
    this.qadaDayPoints = 80,
    this.qadaWindowDays = 7,
    this.challengeLengthDays = 365,
    this.cheapestRewardPoints,
  });

  /// No forced update. Only a minimum an admin sets explicitly may block the app — never a missing
  /// or default config (e.g. offline first launch, API not reachable).
  static const noMinimum = '0.0.0';

  static const defaultFeatures = {
    Flags.challenge: true,
    Flags.rewards: true,
    Flags.hifz: true,
    Flags.listen: true,
    Flags.bonuses: false,
    Flags.recite: false,
    Flags.ramadan: false,
    Flags.tafsirFull: false,
  };

  /// Bundled default (Quran 15:99) — replaced by the reviewed verse from remote config.
  static const defaultSplashVerse = 'وَٱعْبُدْ رَبَّكَ حَتَّىٰ يَأْتِيَكَ ٱلْيَقِينُ';

  final Map<String, bool> features;
  final Map<String, int> featureRollout;
  final String minVersionIos;
  final String minVersionAndroid;
  final bool maintenance;
  final String maintenanceAr;
  final String maintenanceEn;
  final String splashVerseAr;
  final String splashVerseRef;
  final int hijriOffsetDays;
  final int dailyTotal;
  final int qadaDayPoints;
  final int qadaWindowDays;
  final int challengeLengthDays;
  final int? cheapestRewardPoints;

  bool isOn(String flag, {String? userId}) => (features[flag] ?? false) && inRollout(userId, flag, featureRollout[flag]);

  bool needsUpdate({required bool ios, required String appVersion}) =>
      compareVersions(appVersion, ios ? minVersionIos : minVersionAndroid) < 0;

  factory RemoteConfig.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic> m(String k) => (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
    final points = m('points');
    return RemoteConfig(
      features: {...defaultFeatures, ...m('features').map((k, v) => MapEntry(k, v == true))},
      featureRollout: m('featureRollout').map((k, v) => MapEntry(k, (v as num).toInt())),
      minVersionIos: (m('minVersion')['ios'] as String?) ?? noMinimum,
      minVersionAndroid: (m('minVersion')['android'] as String?) ?? noMinimum,
      maintenance: m('maintenance')['enabled'] == true,
      maintenanceAr: (m('maintenance')['messageAr'] as String?) ?? '',
      maintenanceEn: (m('maintenance')['messageEn'] as String?) ?? '',
      splashVerseAr: (m('splashVerse')['textAr'] as String?) ?? defaultSplashVerse,
      splashVerseRef: (m('splashVerse')['reference'] as String?) ?? 'الحجر: 99',
      hijriOffsetDays: (m('hijri')['offsetDays'] as num?)?.toInt() ?? 0,
      dailyTotal: (points['dailyTotal'] as num?)?.toInt() ?? 100,
      qadaDayPoints: (points['qadaDayPoints'] as num?)?.toInt() ?? 80,
      qadaWindowDays: (points['qadaWindowDays'] as num?)?.toInt() ?? 7,
      challengeLengthDays: (points['challengeLengthDays'] as num?)?.toInt() ?? 365,
      cheapestRewardPoints: (points['cheapestRewardPoints'] as num?)?.toInt(),
    );
  }
}

/// `GET /v1/config`, cached for an hour and kept for offline starts (spec §6.15).
class RemoteConfigRepository {
  RemoteConfigRepository({required this.api, required this.cache, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ApiClient api;
  final KvStore cache;
  final DateTime Function() _now;
  static const _key = 'cache.config';
  static const maxAge = Duration(hours: 1);

  Future<RemoteConfig> cached() async {
    final raw = await cache.read(_key);
    if (raw == null) return const RemoteConfig();
    try {
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return RemoteConfig.fromJson((j['config'] as Map).cast<String, dynamic>());
    } catch (_) {
      // A corrupt cache must never block start-up: defaults now, a fresh copy on the next refresh.
      await cache.delete(_key);
      return const RemoteConfig();
    }
  }

  /// Fresh config when the cache is older than [maxAge] (or [force]); otherwise the cache.
  /// Never throws: offline or server errors fall back to the last known config.
  Future<RemoteConfig> refresh({bool force = false}) async {
    final raw = await cache.read(_key);
    DateTime? fetchedAt;
    try {
      fetchedAt = raw == null ? null : DateTime.tryParse(((jsonDecode(raw) as Map)['fetchedAt'] as String?) ?? '');
    } catch (_) {
      fetchedAt = null;
    }
    if (!force && fetchedAt != null && _now().difference(fetchedAt) < maxAge) return cached();
    try {
      final json = (await api.get('/v1/config') as Map).cast<String, dynamic>();
      await cache.write(_key, jsonEncode({'fetchedAt': _now().toIso8601String(), 'config': json}));
      return RemoteConfig.fromJson(json);
    } on OfflineException {
      return cached();
    } on ApiException {
      return cached();
    }
  }
}
