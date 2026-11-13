import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

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
