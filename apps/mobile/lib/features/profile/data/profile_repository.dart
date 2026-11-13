import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../../core/platform/photo_picker.dart';
import '../../../core/storage/kv_store.dart';
import '../../community/domain/community_models.dart';
import '../../onboarding/data/consent_repository.dart';
import '../domain/avatar.dart';
import '../domain/me_profile.dart';

/// The caller's profile (APP_SPEC §5.24, design §6.0): name and avatar are written on this phone
/// first and synced (Outbox), so they work offline and for guests; competitions are joined with a
/// **direct** online call (typed failures shown inline) and left through the Outbox (hidden here at
/// once).
///
/// Guests stay local: nothing reaches the network, and `profile.dirty.v1` remembers which fields
/// the person changed so [pushAfterSignIn] sends only those once they link an account.
class ProfileRepository {
  ProfileRepository({
    required this.api,
    required this.store,
    required this.outbox,
    required this.docsDir,
    this.consents,
    bool Function()? isAccount,
  }) : _isAccount = isAccount ?? (() => true);

  final ApiClient api;
  final KvStore store;
  final Outbox outbox;

  /// App-private files directory; photos live in `<dir>/profile/`.
  final Future<Directory> Function() docsDir;
  final ConsentRepository? consents;

  /// Whether the session can sync (a signed-in, non-guest account with a server id).
  final bool Function() _isAccount;

  static const meKey = 'profile.me.v1';
  static const dirtyKey = 'profile.dirty.v1';
  static const pendingUploadKey = 'profile.pendingUpload.v1';
  static const lastPresetKey = 'profile.lastPreset.v1';
  static const lastSeenLevelKey = 'profile.lastSeenLevel';

  /// Every key [wipe] removes: the profile's and the community screens' caches.
  static const wipedKeys = [
    meKey,
    dirtyKey,
    pendingUploadKey,
    lastPresetKey,
    lastSeenLevelKey,
    'community.league.v1',
    'community.league.history.v1',
    'community.tournaments.v1',
    'community.leaderboard.global.v1',
    'community.leaderboard.country.v1',
    'community.blocks.v1',
    'community.seenWeek',
  ];

  static const profilePath = '/v1/me/profile';
  static const communityPath = '/v1/me/community';
  static const photoPath = '/v1/me/avatar/photo';
  static const ownPhotoLarge = '/v1/me/avatar/photo/256';

  bool get isAccount => _isAccount();

  /* ------------------------------------------------------------------ read */

  Future<MeProfile?> cached() async {
    final raw = await store.read(meKey);
    if (raw == null) return null;
    try {
      return MeProfile.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null; // corrupt cache: refetch
    }
  }

  Future<void> _save(MeProfile p) => store.write(meKey, jsonEncode(p.toJson()));

  /// GET /v1/me/profile. Local changes still on their way (a queued PATCH, a pending photo upload)
  /// stay on top of the server's answer until they are delivered.
  Future<MeProfile> refresh() async {
    final local = await cached();
    final json = await api.get(profilePath);
    var p = MeProfile.fromJson((json as Map).cast<String, dynamic>());
    p = await _overlayPending(p, local);
    await _save(p);
    return p;
  }

  Future<MeProfile> _overlayPending(MeProfile server, MeProfile? local) async {
    var p = server;
    // Support removed the photo: drop this phone's copies too.
    if (p.photoHidden) {
      await _deletePhotoFiles();
      await store.delete(pendingUploadKey);
    }
    final queued = await _queuedProfilePatch();
    if (queued != null) {
      final name = queued['displayName'];
      if (name is String) p = p.copyWith(displayName: name);
      if (queued['avatar'] is Map) p = p.copyWith(avatar: AvatarRef.fromJson(queued['avatar']));
    }
    final localAvatar = local?.avatar;
    if (!p.photoHidden && localAvatar is PhotoAvatar) {
      final server = p.avatar;
      if (await store.read(pendingUploadKey) != null && localAvatar.isLocalOnly) {
        p = p.copyWith(avatar: localAvatar); // not uploaded yet: keep showing it
      } else if (server is PhotoAvatar && server.id == localAvatar.id && localAvatar.localPath != null) {
        p = p.copyWith(avatar: server.withLocalPath(localAvatar.localPath)); // same photo: keep the file
      }
    }
    if (p.avatar is! PhotoAvatar) await _deletePhotoFiles();
    return p;
  }

  Future<Map<String, dynamic>?> _queuedProfilePatch() async {
    final items = await outbox.items();
    final mine = items.where((i) => i.method == 'PATCH' && i.path == profilePath);
    return mine.isEmpty ? null : mine.last.body;
  }

  /// The profile to start from for a local change: the cache, or a fresh guest profile.
  Future<MeProfile> _base({String? fallbackName}) async => await cached() ?? MeProfile.guest(displayName: fallbackName);

  /* ------------------------------------------------------- name and avatar */

  /// Local first; signed in → one queued PATCH (replacing any older one); guest → dirty flag.
  Future<MeProfile> saveName(String name) async {
    final trimmed = name.trim();
    final p = (await _base()).copyWith(displayName: trimmed);
    await _save(p);
    if (isAccount) {
      await _queuePatch({'displayName': trimmed});
    } else {
      await _markDirty(name: true);
    }
    return p;
  }

  /// The initial or a preset (photos go through [uploadPhoto]). Local first, as [saveName].
  Future<MeProfile> saveAvatar(AvatarRef avatar) async {
    if (avatar is PhotoAvatar) throw ArgumentError('Use uploadPhoto for photos');
    final p = (await _base()).copyWith(avatar: avatar);
    await _save(p);
    if (avatar is PresetAvatar) await store.write(lastPresetKey, avatar.id);
    await _deletePhotoFiles();
    await store.delete(pendingUploadKey);
    if (isAccount) {
      await _queuePatch({'avatar': avatar.toJson()});
    } else {
      await _markDirty(avatar: true, photo: false);
    }
    return p;
  }

  /// Merges [fields] into the queued PATCH /v1/me/profile (only the latest value matters).
  Future<void> _queuePatch(Map<String, dynamic> fields) async {
    final previous = await _queuedProfilePatch() ?? const {};
    await outbox.removeWhere((i) => i.method == 'PATCH' && i.path == profilePath);
    await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'PATCH', path: profilePath, body: {...previous, ...fields}));
  }

  /* ------------------------------------------------------------------ photo */

  Future<Directory> _profileDir() async {
    final dir = Directory('${(await docsDir()).path}${Platform.pathSeparator}profile');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _deletePhotoFiles({String? keep}) async {
    final root = await docsDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}profile');
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      if (keep != null && f.path == keep) continue;
      if (f.uri.pathSegments.last.startsWith('avatar_')) {
        try {
          await f.delete();
        } on FileSystemException {
          // already gone
        }
      }
    }
  }

  /// Shows [photo] at once (written to `profile/avatar_local.*`). Signed in, it uploads directly
  /// (not the Outbox): a transient failure keeps the file and retries later
  /// ([retryPendingUpload]); a permanent one (too large, wrong type, unreadable, locked) restores
  /// the previous picture. Guests keep it on the phone until they link an account.
  Future<Result<AvatarRef, CommunityFailure>> uploadPhoto(PickedPhoto photo) async {
    final before = await _base();
    final ext = switch (photo.mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final dir = await _profileDir();
    final file = File('${dir.path}${Platform.pathSeparator}avatar_local.$ext');
    await _deletePhotoFiles();
    await file.writeAsBytes(photo.bytes, flush: true);
    final local = PhotoAvatar.local(file.path);
    await _save(before.copyWith(avatar: local));
    if (!isAccount) {
      await _markDirty(photo: true, avatar: false);
      return Ok(local);
    }
    await store.write(pendingUploadKey, jsonEncode({'path': file.path, 'mime': photo.mime}));
    // A queued preset change would undo the photo when it replays.
    await _dropQueuedAvatar();
    return _upload(file, photo.mime, before.avatar);
  }

  Future<void> _dropQueuedAvatar() async {
    final queued = await _queuedProfilePatch();
    if (queued == null || !queued.containsKey('avatar')) return;
    await outbox.removeWhere((i) => i.method == 'PATCH' && i.path == profilePath);
    final rest = {...queued}..remove('avatar');
    if (rest.isNotEmpty) await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'PATCH', path: profilePath, body: rest));
  }

  Future<Result<AvatarRef, CommunityFailure>> _upload(File file, String mime, AvatarRef previous) async {
    try {
      final json = await api.putBytes(photoPath, await file.readAsBytes(), mime);
      final server = AvatarRef.fromJson(json);
      AvatarRef shown = server;
      if (server is PhotoAvatar) {
        String? path;
        try {
          final bytes = await api.getBytes(ownPhotoLarge);
          final dir = await _profileDir();
          final out = File('${dir.path}${Platform.pathSeparator}avatar_${server.id}.webp');
          await out.writeAsBytes(bytes, flush: true);
          path = out.path;
        } on Object {
          path = null; // shown from the network until the next refresh
        }
        shown = server.withLocalPath(path);
        await _deletePhotoFiles(keep: path);
      }
      await store.delete(pendingUploadKey);
      final p = await _base();
      await _save(p.copyWith(avatar: shown, photoHidden: false));
      return Ok(shown);
    } on OfflineException {
      return const Err(CommunityFailure.offline);
    } on ApiException catch (e) {
      final failure = _failureOf(e);
      final transient = !e.isPermanent || e.status == 401 || failure == CommunityFailure.rateLimited;
      if (!transient) {
        // Retrying can't help: restore the previous picture.
        await store.delete(pendingUploadKey);
        await _deletePhotoFiles(keep: previous is PhotoAvatar ? previous.localPath : null);
        await _save((await _base()).copyWith(avatar: previous));
      } else if (failure == CommunityFailure.rateLimited) {
        // Not this hour: drop the attempt (the user is told to try again later).
        await store.delete(pendingUploadKey);
        await _deletePhotoFiles(keep: previous is PhotoAvatar ? previous.localPath : null);
        await _save((await _base()).copyWith(avatar: previous));
      }
      return Err(failure);
    }
  }

  /// Retries a photo whose upload failed for a transient reason (call on resume / when online).
  Future<Result<AvatarRef, CommunityFailure>?> retryPendingUpload() async {
    if (!isAccount) return null;
    final raw = await store.read(pendingUploadKey);
    if (raw == null) return null;
    final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
    final file = File(j['path'] as String);
    if (!file.existsSync()) {
      await store.delete(pendingUploadKey);
      return null;
    }
    return _upload(file, j['mime'] as String? ?? 'image/jpeg', const InitialAvatar());
  }

  /// Back to the last preset (or the initial) at once; signed in, DELETE /v1/me/avatar/photo
  /// directly, queued when offline.
  Future<MeProfile> removePhoto() async {
    final lastPreset = await store.read(lastPresetKey);
    final fallback = lastPreset == null ? const InitialAvatar() : PresetAvatar(lastPreset) as AvatarRef;
    final p = (await _base()).copyWith(avatar: fallback, photoHidden: false);
    await _save(p);
    await _deletePhotoFiles();
    await store.delete(pendingUploadKey);
    if (!isAccount) {
      await _markDirty(photo: false, avatar: true);
      return p;
    }
    try {
      final json = await api.delete(photoPath);
      final server = AvatarRef.fromJson(json);
      final saved = p.copyWith(avatar: server);
      await _save(saved);
      return saved;
    } on OfflineException {
      await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'DELETE', path: photoPath));
      return p;
    } on ApiException catch (e) {
      if (!e.isPermanent) await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'DELETE', path: photoPath));
      return p;
    }
  }

  /* -------------------------------------------------------------- community */

  /// Turning a competition on: a **direct** PUT /v1/me/community (never the Outbox). Offline →
  /// [CommunityFailure.offline]; every server code maps to its own failure. On success the
  /// `community` consent is adopted from the server's answer.
  Future<Result<CommunitySettings, CommunityFailure>> joinCommunity(CommunityUpdate update) async {
    if (!isAccount) return const Err(CommunityFailure.accountRequired);
    try {
      final json = await api.put(communityPath, update.toJson());
      final settings = CommunitySettings.fromJson((json as Map).cast<String, dynamic>());
      var p = (await _base()).copyWith(community: settings);
      if (update.displayName != null && update.displayName!.trim().isNotEmpty) p = p.copyWith(displayName: update.displayName!.trim());
      if (!settings.leagues) p = p.copyWith(clearLeague: true);
      await _save(p);
      final granted = settings.anyOn || (consents?.granted(ConsentKind.community) ?? false);
      await consents?.adopt(ConsentKind.community, granted);
      return Ok(settings);
    } on OfflineException {
      return const Err(CommunityFailure.offline);
    } on ApiException catch (e) {
      return Err(_failureOf(e));
    }
  }

  /// Turning competitions off (each true flag leaves that one): queued in the Outbox and applied
  /// here at once, so the person disappears from their own views immediately, offline too.
  Future<MeProfile> leaveCommunity({bool leagues = false, bool leaderboard = false, bool leaderboardCountry = false}) async {
    final base = await _base();
    var c = base.community;
    final body = <String, dynamic>{};
    if (leagues) {
      c = c.copyWith(leagues: false);
      body['leagues'] = false;
    }
    if (leaderboard) {
      c = c.copyWith(leaderboard: false, leaderboardCountry: false);
      body['leaderboard'] = false;
      body['leaderboardCountry'] = false;
    }
    if (leaderboardCountry) {
      c = c.copyWith(leaderboardCountry: false);
      body['leaderboardCountry'] = false;
    }
    var p = base.copyWith(community: c);
    if (leagues) p = p.copyWith(clearLeague: true);
    await _save(p);
    if (body.isEmpty || !isAccount) return p;
    // Merge with a leave still waiting, so one PUT carries every switch turned off.
    final queued = (await outbox.items()).where((i) => i.method == 'PUT' && i.path == communityPath).map((i) => i.body ?? const {});
    final merged = <String, dynamic>{for (final q in queued) ...q, ...body, 'source': 'settings'};
    await outbox.removeWhere((i) => i.method == 'PUT' && i.path == communityPath);
    await outbox.add(OutboxItem(id: Outbox.newEventId(), method: 'PUT', path: communityPath, body: merged));
    return p;
  }

  /// POST /v1/me/attestation (direct): «عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري».
  Future<Result<CommunitySettings, CommunityFailure>> attest() async {
    if (!isAccount) return const Err(CommunityFailure.accountRequired);
    try {
      final json = await api.post('/v1/me/attestation', {'attestAdult': true});
      final settings = CommunitySettings.fromJson((json as Map).cast<String, dynamic>());
      await _save((await _base()).copyWith(community: settings));
      return Ok(settings);
    } on OfflineException {
      return const Err(CommunityFailure.offline);
    } on ApiException catch (e) {
      return Err(_failureOf(e));
    }
  }

  static CommunityFailure _failureOf(ApiException e) {
    final byCode = CommunityFailure.fromCode(e.code);
    if (byCode != CommunityFailure.unknown) return byCode;
    return switch (e.status) {
      413 => CommunityFailure.photoTooLarge,
      415 => CommunityFailure.photoType,
      422 => CommunityFailure.photoUnreadable,
      429 => CommunityFailure.rateLimited,
      404 => CommunityFailure.notFound,
      _ => CommunityFailure.unknown,
    };
  }

  /* -------------------------------------------------------- guest → account */

  Future<Map<String, bool>> _dirty() async {
    final raw = await store.read(dirtyKey);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v == true));
    } catch (_) {
      return const {};
    }
  }

  Future<void> _markDirty({bool? name, bool? avatar, bool? photo}) async {
    final d = {...await _dirty()};
    if (name != null) d['name'] = name;
    if (avatar != null) d['avatar'] = avatar;
    if (photo != null) d['photo'] = photo;
    await store.write(dirtyKey, jsonEncode(d));
  }

  /// After a guest links an account: fetch the server's profile first, then push only the fields
  /// the person changed on this phone (server values win for everything else), upload a local
  /// photo only when the photo itself was changed, and clear the dirty flags.
  Future<MeProfile?> pushAfterSignIn() async {
    if (!isAccount) return null;
    final local = await cached();
    final dirty = await _dirty();
    MeProfile server;
    try {
      server = await refresh();
    } on Object {
      return null; // offline: the flags stay for the next sign-in push
    }
    var p = server;
    final patch = <String, dynamic>{};
    if (dirty['name'] == true && (local?.displayName?.trim().isNotEmpty ?? false)) {
      patch['displayName'] = local!.displayName!.trim();
      p = p.copyWith(displayName: patch['displayName'] as String);
    }
    final localAvatar = local?.avatar;
    if (dirty['avatar'] == true && localAvatar != null && localAvatar is! PhotoAvatar) {
      patch['avatar'] = localAvatar.toJson();
      p = p.copyWith(avatar: localAvatar);
    }
    await _save(p);
    if (patch.isNotEmpty) {
      try {
        final json = await api.patch(profilePath, patch);
        if (json is Map) p = await _overlayPending(MeProfile.fromJson(json.cast<String, dynamic>()), p);
        await _save(p);
      } on Object {
        await _queuePatch(patch);
      }
    }
    if (dirty['photo'] == true && localAvatar is PhotoAvatar && localAvatar.localPath != null) {
      final file = File(localAvatar.localPath!);
      if (file.existsSync()) {
        final mime = file.path.endsWith('.png') ? 'image/png' : (file.path.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
        await store.write(pendingUploadKey, jsonEncode({'path': file.path, 'mime': mime}));
        await _save((await _base()).copyWith(avatar: localAvatar));
        await _upload(file, mime, server.avatar);
      }
    }
    await store.delete(dirtyKey);
    return cached();
  }

  /* ------------------------------------------------------------------ wipe */

  /// Account deletion / forgetting the account: profile and community caches and photo files.
  Future<void> wipe() async {
    for (final k in wipedKeys) {
      await store.delete(k);
    }
    final root = await docsDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}profile');
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // best effort
      }
    }
  }
}
