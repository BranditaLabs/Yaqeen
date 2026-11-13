import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/outbox.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../data/profile_repository.dart';
import '../domain/avatar.dart';
import 'me_profile_controller.dart';

/// Queued writes; re-read whenever the outbox changes (a tick queued, a flush sent them).
final pendingSyncProvider = FutureProvider.autoDispose((ref) {
  final outbox = ref.watch(outboxProvider);
  final sub = outbox.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return outbox.length;
});

/// Bytes of audio and packs on disk; re-measured when the download queue drains.
final downloadsBytesProvider = FutureProvider.autoDispose((ref) async {
  final sub = ref.watch(downloadQueueProvider).idle.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return await ref.watch(audioDownloadsProvider).bytesOnDisk() + await ref.watch(packRepositoryProvider).bytesOnDisk();
});

/// A profile photo is uploading: the stage avatar's ring shimmers until it lands.
final photoUploadingProvider = StateProvider<bool>((_) => false);

/// Whether the profile [meProfileProvider] holds is really the account's (cached on this phone or
/// fetched). A signed-in account with nothing cached (a reinstall that kept the session, a sign-in
/// after sign-out) first gets a level-1 placeholder; the Profile tab waits for the real profile
/// instead of drawing level 1, and never lets the level-up moment record the placeholder as seen.
/// Guests' profiles are always their own.
final meProfileReadyProvider = FutureProvider.autoDispose<bool>((ref) async {
  if (!ref.watch(sessionProvider.select((s) => s.canEarnPoints))) return true;
  ref.watch(meProfileProvider); // re-checked whenever the profile changes (fetched, saved)
  return await ref.watch(profileRepositoryProvider).cached() != null;
});

/// Names the server refused when the queued PATCH /v1/me/profile replayed (`invalid_name`, design
/// §6.4: «a server `invalid_name` on replay reverts to the server name with a toast»). The profile
/// is re-read from the server, so the name goes back to the one it holds; a preset that travelled
/// in the same PATCH is queued again on its own. The count rises once per revert: the screen on
/// show listens and says «لم يُقبل الاسم، فأعدناه كما كان.».
final nameRevertsProvider = NotifierProvider<NameRevertsController, int>(NameRevertsController.new);

class NameRevertsController extends Notifier<int> {
  @override
  int build() {
    final sub = ref.watch(outboxSyncProvider).rejected.listen((r) => _onRejected(r.$1, r.$2).ignore());
    ref.onDispose(sub.cancel);
    return 0;
  }

  Future<void> _onRejected(OutboxItem item, ApiException e) async {
    if (item.method != 'PATCH' || item.path != ProfileRepository.profilePath || e.code != 'invalid_name') return;
    // The flush drops the refused PATCH when it ends; until then a refresh would lay its name back on top.
    await ref.read(outboxSyncProvider).flush();
    final profile = ref.read(meProfileProvider.notifier);
    await profile.refresh();
    final avatar = item.body?['avatar'];
    if (avatar is Map) {
      final kept = AvatarRef.fromJson(avatar);
      if (kept is! PhotoAvatar) await profile.setAvatar(kept);
    }
    state = state + 1;
  }
}
