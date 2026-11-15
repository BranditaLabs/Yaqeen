import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import 'asr_model_controller.dart';

/// «تسميع» entry points (reader dock, ayah sheet, hifz test) show only when the `recite` flag is on
/// (the ship gate, remote-controlled, spec §6.8) *and* this phone runs the on-device model and one
/// is published for this build — never a button that leads to «not available on this device».
/// Before the model is downloaded, the first entry opens the download sheet; hifz then offers
/// «استماع» / the self-check test until it is.
final reciteEntryProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(remoteConfigProvider).isOn(Flags.recite)) return false;
  return ref.watch(asrModelControllerProvider.select((s) => s.supported)) ?? false;
});

/// The model is on the phone and listening can start now (voice-aware «تحفيظ», the recite layer).
final reciteReadyProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(remoteConfigProvider).isOn(Flags.recite)) return false;
  return ref.watch(asrModelControllerProvider.select((s) => s.ready));
});
