import 'dart:async';

/// On-device speech recognition for «التسميع» (spec §6.8). Audio stays in memory on the device;
/// nothing is uploaded. Emits the running transcript (Arabic words) while listening; alignment
/// against the expected ayat happens in `RecitationAligner`.
abstract interface class RecitationEngine {
  /// The model is downloaded and the device supports it.
  Future<bool> isAvailable();

  /// Starts the microphone (asks the OS permission the first time). Throws when denied.
  Stream<String> start();
  Future<void> stop();
}

/// Default until a model that passes the ship gate (≥ 90 % word accuracy) is integrated.
class UnavailableRecitationEngine implements RecitationEngine {
  const UnavailableRecitationEngine();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Stream<String> start() => const Stream.empty();
  @override
  Future<void> stop() async {}
}

/// Test/dev engine driven by [emit].
class ScriptedRecitationEngine implements RecitationEngine {
  StreamController<String>? _c;
  bool listening = false;

  @override
  Future<bool> isAvailable() async => true;
  @override
  Stream<String> start() {
    _c = StreamController<String>();
    listening = true;
    return _c!.stream;
  }

  void emit(String transcript) => _c?.add(transcript);

  @override
  Future<void> stop() async {
    listening = false;
    await _c?.close();
    _c = null;
  }
}
