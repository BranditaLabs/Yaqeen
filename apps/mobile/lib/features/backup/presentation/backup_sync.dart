import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/settings/settings_controller.dart';
import '../../azkar/domain/azkar_progress.dart';
import '../../azkar/presentation/azkar_controller.dart';
import '../../duas/presentation/duas_screen.dart';
import '../../hifz/presentation/hifz_controller.dart';
import '../../home/data/tasbeeh_controller.dart';
import '../../notifications/presentation/reminders_controller.dart';
import '../../onboarding/data/consent_repository.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../quran/presentation/quran_index_screen.dart';
import '../../quran/presentation/quran_providers.dart';
import '../../quran/presentation/reader_screen.dart';
import '../../ramadan/presentation/ramadan_controller.dart';
import '../data/backup_adapters.dart';
import '../data/backup_engine.dart';
import '../data/backup_repository.dart';
import '../domain/backup_merge.dart';

final backupRepositoryProvider = Provider((ref) => BackupRepository(ref.watch(apiClientProvider)));

/// Every kind the cloud backup carries, each over the store that already keeps it.
final backupAdaptersProvider = Provider<List<BackupAdapter>>((ref) {
  final local = ref.watch(localStoreProvider);
  final kv = ref.watch(kvStoreProvider);
  final reading = ref.watch(readingRepositoryProvider);
  return [
    QuranReadingBackup(reading),
    QuranNotesBackup(reading),
    KhatmaBackup(reading),
    HifzBackup(local),
    AzkarBackup(local),
    ListenBackup(ref.watch(listenStoreProvider)),
    RoutineBackup(
      load: () async => ref.read(settingsProvider),
      apply: (quran, hifz, dhikr) =>
          ref.read(settingsProvider.notifier).update((s) => s.copyWith(quranSlot: quran, hifzSlot: hifz, dhikrSlot: dhikr), sync: false),
    ),
    RamadanBackup(kv),
    TasbeehBackup(
      kv,
      adopt: (n) => ref.exists(tasbeehProvider) ? ref.read(tasbeehProvider.notifier).adopt(n) : kv.write(TasbeehBackup.key, '$n').ignore(),
    ),
  ];
});

/// A merged copy landed in the stores: refresh whatever shows it (never while the user is typing —
/// these are all read-only views or controllers that take the merged state).
void _applyImported(Ref ref, BackupKind kind, Json doc) {
  switch (kind) {
    case BackupKind.quranReading:
      ref
        ..invalidate(bookmarksProvider)
        ..invalidate(lastReadProvider)
        ..invalidate(todayWirdProvider)
        ..invalidate(readingStatsProvider);
    case BackupKind.quranNotes:
      ref.invalidate(annotationsProvider);
    case BackupKind.khatma:
      ref
        ..invalidate(khatmaProvider)
        ..invalidate(khatmaHistoryProvider);
    case BackupKind.hifz:
      ref.invalidate(hifzControllerProvider);
      ref.read(remindersControllerProvider.notifier).replan().ignore();
    case BackupKind.azkar:
      if (ref.exists(azkarControllerProvider)) {
        if (AzkarDay.tryParse(doc['day']) case final day?) ref.read(azkarControllerProvider.notifier).adopt(day);
      }
      ref.invalidate(favouritesProvider);
    case BackupKind.ramadan:
      ref.invalidate(ramadanLogProvider);
    case BackupKind.listen || BackupKind.routine || BackupKind.tasbeeh:
      // Listen state is read when playback starts; routine and tasbeeh went through their controllers.
      break;
  }
}

final backupEngineProvider = Provider(
  (ref) => BackupEngine(
    repo: ref.watch(backupRepositoryProvider),
    adapters: ref.watch(backupAdaptersProvider),
    kv: ref.watch(kvStoreProvider),
    now: ref.watch(clockProvider),
    onImported: (kind, doc) => _applyImported(ref, kind, doc),
  ),
);

/// How long after a change a kind is uploaded (tests shorten it).
final backupDebounceProvider = Provider<Duration Function(BackupAdapter a)>((_) => (a) => a.debounce);

class BackupStatus {
  const BackupStatus({
    this.available = false,
    this.enabled = false,
    this.syncing = false,
    this.offline = false,
    this.lastBackupAt,
    this.restoreOffer,
  });

  /// Signed in with Google/Apple (guests can't back up — their data has no account to follow).
  final bool available;
  final bool enabled;
  final bool syncing;

  /// The last attempt couldn't reach the server; changes wait on the phone.
  final bool offline;
  final DateTime? lastBackupAt;

  /// A backup exists for this account but this phone hasn't joined it: offer to restore.
  final List<BackupEntry>? restoreOffer;

  BackupStatus copy({bool? available, bool? enabled, bool? syncing, bool? offline, DateTime? lastBackupAt, bool clearLast = false}) =>
      BackupStatus(
        available: available ?? this.available,
        enabled: enabled ?? this.enabled,
        syncing: syncing ?? this.syncing,
        offline: offline ?? this.offline,
        lastBackupAt: clearLast ? null : (lastBackupAt ?? this.lastBackupAt),
        restoreOffer: restoreOffer,
      );

  BackupStatus withOffer(List<BackupEntry>? offer) => BackupStatus(
        available: available,
        enabled: enabled,
        syncing: syncing,
        offline: offline,
        lastBackupAt: lastBackupAt,
        restoreOffer: offer,
      );
}

/// «نسخ احتياطي سحابي» — the opt-in, encrypted cloud backup of device-first progress (consent
/// `cloud_backup`, spec §6.13). Off by default and for guests. When on: pulls and merges after
/// start-up and sign-in, uploads a few seconds after each change, merges and retries once on a
/// conflict, and keeps changes on the phone while offline. Nothing here ever blocks a screen.
class BackupSync extends Notifier<BackupStatus> {
  Timer? _timer;
  DateTime? _deadline;
  StreamSubscription<String>? _changes;
  bool _disposed = false;
  static const _timeBox = Duration(seconds: 30);

  BackupEngine get _engine => ref.read(backupEngineProvider);
  ConsentRepository get _consents => ref.read(consentRepositoryProvider);
  bool get _available => ref.read(sessionProvider).canEarnPoints;
  bool get _enabled => _available && _consents.granted(ConsentKind.cloudBackup);

  @override
  BackupStatus build() {
    _changes = ref.read(kvChangesProvider).listen(_onKey);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _changes?.cancel();
    });
    ref.listen(sessionProvider, (prev, next) {
      if (prev?.userId != next.userId || prev?.provider != next.provider) onSessionChanged().ignore();
    });
    final engine = _engine;
    Future(() async {
      final last = await engine.lastBackupAt();
      if (!_disposed) state = state.copy(lastBackupAt: last);
    });
    return BackupStatus(available: _available, enabled: _enabled);
  }

  void _onKey(String key) {
    final engine = _engine;
    if (engine.importing || !_enabled) return;
    final hits = engine.adaptersFor(key);
    if (hits.isEmpty) return;
    engine.noteChange(hits.map((a) => a.kind)).ignore();
    final delayOf = ref.read(backupDebounceProvider);
    final delay = hits.map(delayOf).reduce((a, b) => a < b ? a : b);
    final due = ref.read(clockProvider)().add(delay);
    // A slow kind (playback position) never postpones an upload already due sooner.
    final shortest = engine.adapters.map(delayOf).reduce((a, b) => a < b ? a : b);
    if (_timer != null && _deadline != null && _deadline!.isBefore(due) && delay > shortest) return;
    _timer?.cancel();
    _deadline = due;
    _timer = Timer(delay, () {
      _timer = null;
      _deadline = null;
      _run(_engine.pushDirty).ignore();
    });
  }

  /// Runs one sync step: time-boxed, offline-tolerant, never throws.
  Future<void> _run(Future<void> Function() op) async {
    if (!_enabled) return;
    state = state.copy(available: true, enabled: true, syncing: true);
    var offline = false;
    try {
      await op().timeout(_timeBox);
    } on BackupOff {
      await _serverSaysOff();
    } on OfflineException {
      offline = true;
    } on TimeoutException {
      offline = true;
    } on Exception {
      // Anything else: the changes stay on the phone and the next start tries again.
    }
    final last = await _engine.lastBackupAt();
    state = state.copy(syncing: false, offline: offline, lastBackupAt: last);
  }

  Future<void> _serverSaysOff() async {
    // Our own "on" may still be queued (offline); only a settled answer turns the switch off.
    if (await _consents.pending(ConsentKind.cloudBackup)) return;
    await _consents.adopt(ConsentKind.cloudBackup, false);
    await _engine.forget();
    state = state.copy(enabled: false, clearLast: true);
  }

  /// After the first frame (AppGate) and on resume: sync, or see whether there is a backup to offer.
  Future<void> start() async {
    state = state.copy(available: _available, enabled: _enabled);
    if (_enabled) return _run(_engine.syncAll);
    return checkRestoreOffer();
  }

  Future<void> onSessionChanged() async {
    _timer?.cancel();
    state = BackupStatus(available: _available, enabled: _enabled, lastBackupAt: await _engine.lastBackupAt());
    await start();
  }

  /// The Privacy switch turned on: record the consent, then merge with any backup and upload.
  Future<void> enable() async {
    if (!_available) return;
    await _consents.set(ConsentKind.cloudBackup, true, ConsentSource.settings);
    state = state.copy(enabled: true).withOffer(null);
    await _run(_engine.syncAll);
  }

  /// The Privacy switch turned off (after the confirmation): the server deletes its copy when the
  /// withdrawn consent reaches it; this phone keeps all its data.
  Future<void> disable() async {
    _timer?.cancel();
    _timer = null;
    await _consents.set(ConsentKind.cloudBackup, false, ConsentSource.settings);
    await _engine.forget();
    state = state.copy(enabled: false, syncing: false, offline: false, clearLast: true);
  }

  Future<void> backUpNow() => _run(_engine.syncAll);

  /// First sign-in on this phone: the account already has a backup (turned on elsewhere).
  Future<void> checkRestoreOffer() async {
    final uid = ref.read(sessionProvider).userId;
    if (!_available || _enabled || uid == null || await _engine.wasOffered(uid)) return;
    try {
      final server = await _consents.fetchServer().timeout(_timeBox);
      if (server[ConsentKind.cloudBackup] != true) return;
      final kinds = await ref.read(backupRepositoryProvider).manifest().timeout(_timeBox);
      if (kinds.isEmpty || ref.read(sessionProvider).userId != uid) return;
      state = state.withOffer(kinds);
    } on Exception {
      // Offline or off: nothing to offer now; asked again on the next start.
    }
  }

  /// «استعادة»: join the account's backup — the consent was given on the other phone.
  Future<void> restore() async {
    final uid = ref.read(sessionProvider).userId;
    if (uid != null) await _engine.markOffered(uid);
    await _consents.adopt(ConsentKind.cloudBackup, true);
    state = state.copy(enabled: true).withOffer(null);
    await _run(_engine.syncAll);
  }

  /// «ليس الآن»: this phone stays off (the server copy is untouched); the switch is in Privacy.
  Future<void> dismissOffer() async {
    final uid = ref.read(sessionProvider).userId;
    if (uid != null) await _engine.markOffered(uid);
    state = state.withOffer(null);
  }
}

final backupSyncProvider = NotifierProvider<BackupSync, BackupStatus>(BackupSync.new);
