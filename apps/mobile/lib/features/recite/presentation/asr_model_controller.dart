import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/network/resumable_download.dart';
import '../../../core/platform/asr/asr_model_store.dart';

/// Where the on-device recitation model stands on this phone.
@immutable
class AsrModelState {
  const AsrModelState({this.supported, this.ready = false, this.progress, this.bytes = 0, this.failed = false});

  /// null while asking; false: this phone (or build) can't run it — nothing is offered.
  final bool? supported;
  final bool ready;

  /// 0…1 while downloading.
  final double? progress;

  /// Download size (the whole model).
  final int bytes;

  /// The last download failed (offline, checksum): the row offers it again.
  final bool failed;

  bool get downloading => progress != null;

  AsrModelState copyWith({bool? supported, bool? ready, double? Function()? progress, int? bytes, bool? failed}) => AsrModelState(
        supported: supported ?? this.supported,
        ready: ready ?? this.ready,
        progress: progress == null ? this.progress : progress(),
        bytes: bytes ?? this.bytes,
        failed: failed ?? this.failed,
      );
}

/// Downloads / deletes the model (spec §6.8): one download, on request only, through the app-wide
/// queue; never on mobile data unless the user said so in the sheet. Lives for the whole session
/// so leaving a screen never stops a download.
class AsrModelController extends Notifier<AsrModelState> {
  @override
  AsrModelState build() {
    final engine = ref.watch(recitationEngineProvider);
    _check(engine.isSupported, engine.isAvailable);
    return AsrModelState(bytes: engine.modelInfo?.bytes ?? 0);
  }

  Future<void> _check(Future<bool> Function() supported, Future<bool> Function() available) async {
    final s = await supported();
    final a = s && await available();
    state = state.copyWith(supported: s, ready: a);
  }

  /// Asks the engine again (after a download, a delete).
  Future<void> refresh() {
    final e = ref.read(recitationEngineProvider);
    return _check(e.isSupported, e.isAvailable);
  }

  /// Starts (or resumes) the download. Throws [WifiRequired] on mobile data without [allowMetered];
  /// other failures leave `failed` set.
  Future<void> download({bool allowMetered = false}) async {
    if (state.downloading || state.ready) return;
    final store = ref.read(asrModelStoreProvider);
    state = state.copyWith(progress: () => 0, failed: false);
    try {
      await store.download(
        allowMetered: allowMetered,
        onProgress: (got, total) {
          if (total > 0) state = state.copyWith(progress: () => (got / total).clamp(0.0, 1.0));
        },
      );
      state = state.copyWith(progress: () => null);
      await refresh();
    } on WifiRequired {
      state = state.copyWith(progress: () => null);
      rethrow;
    } on DownloadCancelled {
      state = state.copyWith(progress: () => null);
    } on Object {
      state = state.copyWith(progress: () => null, failed: true);
    }
  }

  Future<void> cancel() async {
    await ref.read(asrModelStoreProvider).cancel();
    state = state.copyWith(progress: () => null);
  }

  Future<void> delete() async {
    await ref.read(asrModelStoreProvider).delete();
    await refresh();
  }

  /// At start-up: a download the user started and a kill interrupted carries on — on Wi-Fi, or on
  /// mobile data only if they allowed it then.
  Future<void> resumeInterrupted() async {
    final store = ref.read(asrModelStoreProvider);
    if (!await store.wasDownloading()) return;
    try {
      await download(allowMetered: await store.allowedMetered());
    } on WifiRequired {
      // Waits for Wi-Fi (the next launch tries again); the partial files stay.
    }
  }
}

final asrModelControllerProvider = NotifierProvider<AsrModelController, AsrModelState>(AsrModelController.new);

/// The model's bytes on disk (Settings, Downloads).
final asrModelBytesProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(asrModelControllerProvider.select((s) => s.ready));
  return ref.watch(asrModelStoreProvider).bytesOnDisk();
});

/// Exposed for tests that drive a store directly.
typedef AsrStore = AsrModelStore;
