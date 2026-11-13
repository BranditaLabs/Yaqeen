import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/photo_picker.dart';
import '../../community/domain/community_models.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../data/profile_repository.dart';
import '../domain/avatar.dart';
import '../domain/level.dart';
import '../domain/me_profile.dart';

/// The caller's profile for every screen (Home chip, Profile tab, onboarding, competitions).
///
/// It never waits on the network: the cached profile (or a guest value) is the first state, and a
/// signed-in account refreshes it in the background. Writes go through [ProfileRepository]
/// (local first; joins direct, leaves queued) and update this state at once.
class MeProfileController extends AsyncNotifier<MeProfile> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<MeProfile> build() async {
    final session = ref.watch(sessionProvider);
    final repo = ref.watch(profileRepositoryProvider);
    final cached = await repo.cached();
    final value = cached ?? MeProfile.guest(displayName: session.canEarnPoints ? session.displayName : null);
    if (session.canEarnPoints) {
      // After this build has published the cached value.
      Future.microtask(() => _backgroundRefresh());
    }
    return value;
  }

  Future<void> _backgroundRefresh() async {
    try {
      await _repo.retryPendingUpload();
      final fresh = await _repo.refresh();
      state = AsyncData(fresh);
    } on Object {
      // Offline / server trouble: keep showing the cached value.
    }
  }

  void _flush() {
    if (_repo.isAccount) ref.read(outboxSyncProvider).flush(force: true).ignore();
  }

  Future<void> _reload() async {
    final p = await _repo.cached();
    if (p != null) state = AsyncData(p);
  }

  /// Pull-to-refresh. Keeps the cached value on failure; errors only when there is nothing to show.
  Future<void> refresh() async {
    if (!_repo.isAccount) return;
    try {
      state = AsyncData(await _repo.refresh());
    } on Object catch (e, st) {
      if (!state.hasValue) state = AsyncError(e, st);
    }
  }

  Future<void> setName(String name) async {
    state = AsyncData(await _repo.saveName(name));
    _flush();
  }

  /// The initial or a preset (offline-safe).
  Future<void> setAvatar(AvatarRef avatar) async {
    state = AsyncData(await _repo.saveAvatar(avatar));
    _flush();
  }

  /// Picks and sets a photo. Null when the picker is unavailable or the person cancelled.
  Future<Result<AvatarRef, CommunityFailure>?> pickPhoto(PhotoSource source) async {
    final picker = ref.read(photoPickerProvider);
    if (!picker.available) return null;
    final photo = await picker.pick(source);
    if (photo == null) return null;
    final pending = _repo.uploadPhoto(photo);
    // The local copy is cached before the upload starts: show it at once.
    unawaited(Future<void>.delayed(Duration.zero, _reload));
    final result = await pending;
    await _reload();
    return result;
  }

  Future<void> removePhoto() async {
    state = AsyncData(await _repo.removePhoto());
    _flush();
  }

  /// Joins a competition with a direct call; the failure is for the UI to show inline.
  Future<Result<CommunitySettings, CommunityFailure>> join(CommunityUpdate update) async {
    final r = await _repo.joinCommunity(update);
    await _reload();
    if (r.isOk && (update.leagues ?? false)) unawaited(_backgroundRefresh()); // placement, division
    return r;
  }

  /// Leaves at once on this phone; the server hears through the Outbox.
  Future<void> leave({bool leagues = false, bool leaderboard = false, bool leaderboardCountry = false}) async {
    state = AsyncData(await _repo.leaveCommunity(leagues: leagues, leaderboard: leaderboard, leaderboardCountry: leaderboardCountry));
    _flush();
  }

  Future<Result<CommunitySettings, CommunityFailure>> attest() async {
    final r = await _repo.attest();
    await _reload();
    return r;
  }
}

final meProfileProvider = AsyncNotifierProvider<MeProfileController, MeProfile>(MeProfileController.new);

/// Whether a level-up moment is owed: the live level is above the last one the person saw
/// (KV `profile.lastSeenLevel`). Whichever screen shows the moment first calls [LevelUpController.markSeen].
class LevelUp {
  const LevelUp({this.pending = false, this.level});
  final bool pending;
  final CardLevel? level;

  static const none = LevelUp();
}

class LevelUpController extends Notifier<LevelUp> {
  int? _lastSeen;
  bool _loaded = false;
  bool _loading = false;

  @override
  LevelUp build() {
    final profile = ref.watch(meProfileProvider).valueOrNull;
    final account = ref.watch(sessionProvider).canEarnPoints;
    if (!_loaded) {
      if (!_loading) {
        _loading = true;
        Future.microtask(_load);
      }
      return LevelUp.none;
    }
    return _compute(profile, account);
  }

  Future<void> _load() async {
    final raw = await ref.read(kvStoreProvider).read(ProfileRepository.lastSeenLevelKey);
    _lastSeen = int.tryParse(raw ?? '');
    _loaded = true;
    state = _compute(ref.read(meProfileProvider).valueOrNull, ref.read(sessionProvider).canEarnPoints);
  }

  LevelUp _compute(MeProfile? p, bool account) {
    if (p == null || !account) return LevelUp.none;
    final level = p.level.level;
    if (_lastSeen == null) {
      // First time this phone sees the level: remember it quietly, no moment.
      _lastSeen = level;
      ref.read(kvStoreProvider).write(ProfileRepository.lastSeenLevelKey, '$level').ignore();
      return LevelUp.none;
    }
    return level > _lastSeen! ? LevelUp(pending: true, level: p.level) : LevelUp.none;
  }

  bool get pending => state.pending;

  Future<void> markSeen() async {
    final level = ref.read(meProfileProvider).valueOrNull?.level.level;
    if (level == null) return;
    _lastSeen = level;
    state = LevelUp.none;
    await ref.read(kvStoreProvider).write(ProfileRepository.lastSeenLevelKey, '$level');
  }
}

final levelUpProvider = NotifierProvider<LevelUpController, LevelUp>(LevelUpController.new);
