import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../storage/kv_store.dart';
import '../recitation_engine.dart';
import 'asr_model.dart';
import 'asr_model_store.dart';
import 'live_support.dart';
import 'live_transcriber.dart';
import 'pcm.dart';

/// The real «تسميع» engine (spec §6.8): the microphone through `record` (16 kHz mono PCM, in memory
/// only), Silero VAD on this isolate, and Whisper (sherpa-onnx, ONNX int8) on a background isolate,
/// tied together by [LiveTranscriber]. Nothing is written to disk and nothing leaves the phone.
class SherpaRecitationEngine extends RecitationEngine {
  SherpaRecitationEngine({required this.store, required this.kv});

  final AsrModelStore store;
  final KvStore kv;

  static bool? _bound;

  /// Loads the native library once per isolate; false where the runtime isn't shipped.
  static bool _bind() {
    if (_bound != null) return _bound!;
    try {
      sherpa.initBindings();
      _bound = true;
    } on Object {
      _bound = false;
    }
    return _bound!;
  }

  static bool get _platform => Platform.isAndroid || Platform.isIOS;

  _WhisperWorker? _worker;
  SpeechActivity? _vad;
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _mic;
  StreamSubscription<Float32List>? _external;
  LiveTranscriber? _session;
  final _level = StreamController<double>.broadcast();

  @override
  AsrModelInfo? get modelInfo => store.manifest.info;

  @override
  Stream<double> get level => _level.stream;

  @override
  Future<bool> isSupported() async => _platform && store.manifest.published;

  @override
  Future<bool> isAvailable() async => await isSupported() && await store.isReady() && _bind();

  Future<_WhisperWorker> _decoder() async {
    final w = _worker;
    if (w != null) return w;
    return _worker = await _WhisperWorker.spawn(
      encoder: await store.pathOf(AsrFileRole.encoder),
      decoder: await store.pathOf(AsrFileRole.decoder),
      tokens: await store.pathOf(AsrFileRole.tokens),
    );
  }

  Future<SpeechActivity> _activity() async {
    final v = _vad;
    if (v != null) {
      v.reset();
      return v;
    }
    return _vad = _SileroActivity(await store.pathOf(AsrFileRole.vad));
  }

  @override
  Future<LiveSupport> liveSupport() async {
    if (!await isAvailable()) return LiveSupport.unknown;
    return LiveSupportProbe.resolve(kv, store.manifest.id, _decoder);
  }

  Future<LiveTranscriber> _begin(bool live) async {
    await _end(cancel: true);
    if (!await isAvailable()) throw StateError('recitation model not ready');
    return _session = LiveTranscriber(decoder: await _decoder(), activity: await _activity(), live: live);
  }

  @override
  Stream<RecognitionUpdate> listen({bool live = true}) {
    final out = StreamController<RecognitionUpdate>();
    () async {
      try {
        final recorder = _recorder ??= AudioRecorder();
        if (!await recorder.hasPermission()) throw const MicrophoneDenied();
        final t = await _begin(live);
        t.updates.listen(out.add, onError: out.addError, onDone: out.close);
        final pcm = Pcm16Decoder();
        final bytes = await recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: asrSampleRate,
            numChannels: 1,
            autoGain: true,
            noiseSuppress: true,
            androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
          ),
        );
        _mic = bytes.listen((chunk) {
          final s = pcm.convert(chunk);
          _level.add(levelOf(s));
          t.add(s);
        });
      } on Object catch (e, st) {
        out.addError(e, st);
        await out.close();
      }
    }();
    return out.stream;
  }

  @override
  Stream<RecognitionUpdate> startFromPcm(Stream<Float32List> pcm, {bool live = true}) {
    final out = StreamController<RecognitionUpdate>();
    () async {
      try {
        final t = await _begin(live);
        t.updates.listen(out.add, onError: out.addError, onDone: out.close);
        _external = pcm.listen(
          (s) {
            _level.add(levelOf(s));
            t.add(s);
          },
          onDone: () => stop(),
        );
      } on Object catch (e, st) {
        out.addError(e, st);
        await out.close();
      }
    }();
    return out.stream;
  }

  @override
  Future<RecognitionUpdate> transcribeFile(String path) async {
    final wav = readWav(await File(path).readAsBytes());
    final samples = wav.sampleRate == asrSampleRate ? wav.samples : _resample(wav.samples, wav.sampleRate);
    final t = await _begin(false);
    final last = t.updates.last;
    const step = asrSampleRate ~/ 10;
    for (var i = 0; i < samples.length; i += step) {
      t.add(Float32List.sublistView(samples, i, i + step > samples.length ? samples.length : i + step));
    }
    await t.finish();
    _session = null;
    return last;
  }

  static Float32List _resample(Float32List s, int rate) {
    final n = (s.length * asrSampleRate / rate).floor();
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      final x = i * rate / asrSampleRate;
      final j = x.floor();
      final f = x - j;
      final a = s[j.clamp(0, s.length - 1)];
      final b = s[(j + 1).clamp(0, s.length - 1)];
      out[i] = a + (b - a) * f;
    }
    return out;
  }

  Future<void> _end({bool cancel = false}) async {
    await _mic?.cancel();
    _mic = null;
    await _external?.cancel();
    _external = null;
    final r = _recorder;
    if (r != null && await r.isRecording()) await r.stop();
    final s = _session;
    _session = null;
    if (s != null) await (cancel ? s.cancel() : s.finish());
  }

  @override
  Future<void> stop() => _end();

  /// Frees the model (the app is leaving; the next session loads it again).
  Future<void> dispose() async {
    await _end(cancel: true);
    await _recorder?.dispose();
    _recorder = null;
    _vad?.dispose();
    _vad = null;
    await _worker?.dispose();
    _worker = null;
  }
}

/// Silero VAD through sherpa-onnx (this isolate; ~1 ms per 32 ms window).
class _SileroActivity implements SpeechActivity {
  _SileroActivity(String model)
      : _vad = sherpa.VoiceActivityDetector(
          config: sherpa.VadModelConfig(
            sileroVad: sherpa.SileroVadModelConfig(model: model, minSilenceDuration: 0.4, minSpeechDuration: 0.2, maxSpeechDuration: 25),
            numThreads: 1,
            debug: false,
          ),
          bufferSizeInSeconds: 30,
        );

  final sherpa.VoiceActivityDetector _vad;

  @override
  bool accept(Float32List samples) {
    _vad.acceptWaveform(samples);
    final speaking = _vad.isDetected();
    // Segments are not used (the transcriber keeps its own audio): drop them as they complete.
    while (!_vad.isEmpty()) {
      _vad.pop();
    }
    return speaking;
  }

  @override
  void reset() => _vad.reset();

  @override
  void dispose() => _vad.free();
}

/// Whisper on its own isolate: the UI never waits for a decode.
class _WhisperWorker implements SpeechDecoder {
  _WhisperWorker._(this._isolate, this._send, this._replies);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _replies;
  final _waiting = <int, Completer<List<RecognizedWord>>>{};
  int _next = 0;

  static Future<_WhisperWorker> spawn({required String encoder, required String decoder, required String tokens}) async {
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    late _WhisperWorker worker;
    replies.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is List && m.length == 2) {
        final c = worker._waiting.remove(m[0] as int);
        final r = m[1];
        if (r is String) {
          c?.completeError(StateError(r));
        } else {
          c?.complete(r as List<RecognizedWord>);
        }
      }
    });
    final isolate = await Isolate.spawn(_main, (replies.sendPort, encoder, decoder, tokens));
    worker = _WhisperWorker._(isolate, await ready.future, replies);
    return worker;
  }

  @override
  Future<List<RecognizedWord>> decode(Float32List samples) {
    final id = _next++;
    final c = _waiting[id] = Completer<List<RecognizedWord>>();
    _send.send((id, TransferableTypedData.fromList([samples])));
    return c.future;
  }

  @override
  Future<void> dispose() async {
    _send.send(null);
    _replies.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
    for (final c in _waiting.values) {
      c.completeError(StateError('disposed'));
    }
    _waiting.clear();
  }

  static void _main((SendPort, String, String, String) args) {
    final (reply, encoder, decoder, tokens) = args;
    sherpa.initBindings();
    final recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: encoder,
            decoder: decoder,
            language: 'ar',
            task: 'transcribe',
            enableTokenTimestamps: true,
          ),
          tokens: tokens,
          numThreads: 2,
          debug: false,
        ),
      ),
    );
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    inbox.listen((m) {
      if (m == null) {
        recognizer.free();
        inbox.close();
        return;
      }
      final (id, data) = m as (int, TransferableTypedData);
      try {
        final samples = data.materialize().asFloat32List();
        final stream = recognizer.createStream()..acceptWaveform(samples: samples, sampleRate: asrSampleRate);
        recognizer.decode(stream);
        final r = recognizer.getResult(stream);
        stream.free();
        reply.send([id, wordsFromTokens(r.text, r.tokens, r.timestamps, samples.length / asrSampleRate)]);
      } on Object catch (e) {
        reply.send([id, '$e']);
      }
    });
  }
}
