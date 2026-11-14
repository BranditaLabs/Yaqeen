import 'dart:async';
import 'dart:typed_data';

/// One recognised word with its time in the session (seconds from the start of listening).
class RecognizedWord {
  const RecognizedWord(this.text, {this.start = 0, this.end = 0});
  final String text;
  final double start;
  final double end;

  @override
  bool operator ==(Object other) => other is RecognizedWord && other.text == text && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(text, start, end);
  @override
  String toString() => '$text@${start.toStringAsFixed(2)}';
}

/// What has been heard so far. [committed] words are stable (two decodes agreed, or the speech
/// segment ended) and never change again; [tentative] is the current guess for the words after them.
/// [isFinal]: the last update of a session (after `stop`, or a whole recording checked at once).
class RecognitionUpdate {
  const RecognitionUpdate({this.committed = const [], this.tentative = const [], this.isFinal = false});

  /// A plain transcript (a scripted engine, a test): all of it committed.
  factory RecognitionUpdate.text(String text, {bool isFinal = false}) => RecognitionUpdate(
        committed: [for (final w in text.split(RegExp(r'\s+'))) if (w.isNotEmpty) RecognizedWord(w)],
        isFinal: isFinal,
      );

  final List<RecognizedWord> committed;
  final List<RecognizedWord> tentative;
  final bool isFinal;

  List<RecognizedWord> get words => [...committed, ...tentative];

  /// The running transcript (committed, then tentative).
  String get text => words.map((w) => w.text).join(' ');
}

/// The on-device model: which one, how big, and whether it is on the phone.
class AsrModelInfo {
  const AsrModelInfo({required this.id, required this.bytes, required this.licence, required this.upstream});
  final String id;
  final int bytes;
  final String licence;

  /// `repo@revision` it was converted from (docs/MODELS.md).
  final String upstream;
}

/// Whether this phone follows a recitation live, measured once on first use (real-time factor of a
/// short clip). Slow phones «سمّع ثم تحقّق»: record the passage, then check it all at once.
class LiveSupport {
  const LiveSupport({required this.live, this.rtf});
  final bool live;
  final double? rtf;

  static const unknown = LiveSupport(live: true);
}

/// On-device speech recognition for «التسميع» and «التحفيظ» (spec §6.8). Audio stays in memory on the
/// device and nothing is uploaded, ever; results never leave the phone either (no backup, export,
/// profile, competition, admin or analytics). Emits what was heard while listening; alignment
/// against the expected ayat happens in `RecitationAligner` / `ReciteProgress`.
abstract class RecitationEngine {
  const RecitationEngine();

  /// The model is on the device and this phone runs it: listening can start now.
  Future<bool> isAvailable();

  /// This phone can run on-device recognition and a model is published for it (it may still need
  /// downloading — the «تسميع» entries then open the download sheet). Defaults to [isAvailable].
  Future<bool> isSupported() => isAvailable();

  /// The model this engine runs (null: none).
  AsrModelInfo? get modelInfo => null;

  /// Microphone level 0…1 while listening (for the strip's breathing ring); empty when idle.
  Stream<double> get level => const Stream.empty();

  /// Starts the microphone (asks the OS permission the first time; throws [MicrophoneDenied] when
  /// refused). [live]: updates while reciting; otherwise the recording is checked once, after
  /// [stop], in a single final update (slow phones).
  Stream<RecognitionUpdate> listen({bool live = true});

  /// The running transcript as plain text (the first interface; kept for simple callers).
  Stream<String> start() => listen().map((u) => u.text);

  /// The same pipeline over PCM that someone else records (16 kHz mono, −1…1).
  Stream<RecognitionUpdate> startFromPcm(Stream<Float32List> pcm, {bool live = true}) => const Stream.empty();

  /// A whole clip at once (a 16 kHz mono WAV on the device).
  Future<RecognitionUpdate> transcribeFile(String path) async => const RecognitionUpdate(isFinal: true);

  /// Whether this phone keeps up live (measured once, then remembered).
  Future<LiveSupport> liveSupport() async => LiveSupport.unknown;

  /// Stops any session and frees the loaded model now (the model was deleted); the next session
  /// loads it again.
  Future<void> release() => stop();

  /// Stops the microphone; a non-live session then delivers its final update.
  Future<void> stop();
}

class MicrophoneDenied implements Exception {
  const MicrophoneDenied();
}

/// Default (and on platforms without the runtime): nothing on this device.
class UnavailableRecitationEngine extends RecitationEngine {
  const UnavailableRecitationEngine();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<bool> isSupported() async => false;
  @override
  Stream<RecognitionUpdate> listen({bool live = true}) => const Stream.empty();
  @override
  Future<void> stop() async {}
}

/// Test/dev engine driven by [emit] / [emitUpdate].
class ScriptedRecitationEngine extends RecitationEngine {
  ScriptedRecitationEngine({this.available = true, this.supported = true, this.live = true, this.info});

  /// The model is on the phone ([isAvailable]); flip it to model a download finishing.
  bool available;
  bool supported;

  /// What [liveSupport] answers.
  bool live;
  final AsrModelInfo? info;

  StreamController<RecognitionUpdate>? _c;
  final _level = StreamController<double>.broadcast();
  bool listening = false;

  /// The `live` argument of the last [listen].
  bool? lastLive;
  int starts = 0;

  /// Delivered as the final update when a non-live session stops.
  RecognitionUpdate? finalUpdate;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> isSupported() async => supported || available;
  @override
  AsrModelInfo? get modelInfo => info;
  @override
  Stream<double> get level => _level.stream;
  @override
  Future<LiveSupport> liveSupport() async => LiveSupport(live: live, rtf: live ? 0.3 : 1.4);

  @override
  Stream<RecognitionUpdate> listen({bool live = true}) {
    _c?.close();
    _c = StreamController<RecognitionUpdate>();
    listening = true;
    lastLive = live;
    starts++;
    return _c!.stream;
  }

  void emit(String transcript) => _c?.add(RecognitionUpdate.text(transcript));
  void emitUpdate(RecognitionUpdate u) => _c?.add(u);
  void emitLevel(double v) => _level.add(v);

  @override
  Future<void> stop() async {
    listening = false;
    final c = _c;
    _c = null;
    if (c == null) return;
    if (lastLive == false && finalUpdate != null) c.add(finalUpdate!);
    // Not awaited: a listener that already cancelled never completes `close`.
    c.close().ignore();
  }
}
