import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';

final _modelReady = FutureProvider.autoDispose((ref) => ref.watch(recitationEngineProvider).isAvailable());

/// «تسميع» entry points (reader, ayah menu, hifz) show only when the `recite` flag is on *and* an
/// on-device model is ready (spec §6.8 ship gate) — never a button that leads to «not available
/// on this device». Hifz then offers «استماع» instead.
final reciteEntryProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(remoteConfigProvider).isOn(Flags.recite)) return false;
  return ref.watch(_modelReady).valueOrNull ?? false;
});
