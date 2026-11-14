import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/network/download_queue.dart';
import 'package:yaqeen/core/network/resumable_download.dart';
import 'package:yaqeen/core/platform/asr/asr_model.dart';
import 'package:yaqeen/core/platform/asr/asr_model_store.dart';
import 'package:yaqeen/core/platform/asr/live_support.dart';
import 'package:yaqeen/core/platform/asr/live_transcriber.dart';
import 'package:yaqeen/core/platform/asr/pcm.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/core/storage/kv_store.dart';

/// Test speech: each word is a burst of a constant level that names it (0.1 + 0.02·k), words
/// 0.15 s apart inside a phrase, phrases ended by a longer pause.
class Speech {
  Speech(this.vocab);
  final List<String> vocab;
  final _out = <double>[];
  static const word = Duration(milliseconds: 400);

  static int _n(Duration d) => d.inMicroseconds * asrSampleRate ~/ 1000000;
  void silence(Duration d) => _out.addAll(List.filled(_n(d), 0));
  void say(List<String> words, {Duration gap = const Duration(milliseconds: 150)}) {
    for (final w in words) {
      _out.addAll(List.filled(_n(word), 0.1 + 0.02 * vocab.indexOf(w)));
      silence(gap);
    }
  }

  Float32List get samples => Float32List.fromList(_out);
}

/// Decodes [Speech]: a complete burst is its word; a burst cut by the buffer's end is a guess that
/// changes as it grows (so agreement never commits a half-heard word). Times are real.
class BurstDecoder implements SpeechDecoder {
  BurstDecoder(this.vocab);
  final List<String> vocab;
  int calls = 0;
  int longest = 0;
  int overWindow = 0;

  @override
  Future<List<RecognizedWord>> decode(Float32List s) async {
    calls++;
    if (s.length > longest) longest = s.length;
    if (s.length > Speech._n(const Duration(seconds: 12))) overWindow++;
    final out = <RecognizedWord>[];
    var i = 0;
    while (i < s.length) {
      if (s[i] == 0) {
        i++;
        continue;
      }
      final start = i;
      final level = s[i];
      while (i < s.length && s[i] == level) {
        i++;
      }
      final k = ((level - 0.1) / 0.02).round();
      final full = i - start >= Speech._n(Speech.word) - 1;
      final cutAtStart = start == 0 && s.isNotEmpty;
      if (!full && cutAtStart) continue; // the tail of a word committed before
      out.add(RecognizedWord(full ? vocab[k] : '${vocab[k]}~${i - start}', start: start / asrSampleRate, end: i / asrSampleRate));
    }
    return out;
  }

  @override
  Future<void> dispose() async {}
}

Future<List<RecognitionUpdate>> run(LiveTranscriber t, Float32List samples) async {
  final updates = <RecognitionUpdate>[];
  final done = t.updates.forEach(updates.add);
  for (var i = 0; i < samples.length; i += 1600) {
    t.add(Float32List.sublistView(samples, i, i + 1600 > samples.length ? samples.length : i + 1600));
    await Future<void>.delayed(Duration.zero);
  }
  await t.finish();
  await done;
  return updates;
}

void main() {
  const vocab = ['قل', 'هو', 'الله', 'احد', 'الصمد', 'لم', 'يلد', 'ولم', 'يولد', 'يكن', 'له', 'كفوا'];

  group('live loop (fake PCM pipeline)', () {
    test('words show live as tentative; each phrase is committed whole when it ends, and never changes', () async {
      final speech = Speech(vocab)
        ..silence(const Duration(milliseconds: 500))
        ..say(['قل', 'هو', 'الله', 'احد'])
        ..silence(const Duration(milliseconds: 900))
        ..say(['الله', 'الصمد'])
        ..silence(const Duration(milliseconds: 900));
      final decoder = BurstDecoder(vocab);
      final t = LiveTranscriber(decoder: decoder, activity: EnergyActivity());
      final updates = await run(t, speech.samples);

      expect(updates.last.isFinal, isTrue);
      expect(updates.last.committed.map((w) => w.text), ['قل', 'هو', 'الله', 'احد', 'الله', 'الصمد']);
      // Committed words only ever grow: each update starts with the previous one's.
      for (var i = 1; i < updates.length; i++) {
        final prev = updates[i - 1].committed.map((w) => w.text).toList();
        final next = updates[i].committed.map((w) => w.text).toList();
        expect(next.take(prev.length), prev);
      }
      // While a phrase is said its words arrive as tentative (they reveal, they don't judge)...
      expect(updates.any((u) => u.committed.isEmpty && u.tentative.length >= 2), isTrue);
      // ...and the phrase is committed whole once it ends.
      expect(updates.map((u) => u.committed.length).toSet(), {0, 4, 6});
      // Word times are session times.
      expect(updates.last.committed.first.start, closeTo(0.5, 0.05));
    });

    test('a long stretch without a pause: live decodes read at most the window, cuts at 25 s', () async {
      final speech = Speech(vocab)..say([for (var i = 0; i < 30; i++) vocab[i % vocab.length]], gap: const Duration(milliseconds: 100));
      speech.silence(const Duration(seconds: 1));
      final decoder = BurstDecoder(vocab);
      final t = LiveTranscriber(decoder: decoder, activity: EnergyActivity());
      final updates = await run(t, speech.samples);
      expect(updates.last.committed.length, inInclusiveRange(29, 30), reason: 'a cut at 25 s may split one word');
      expect(decoder.longest, lessThanOrEqualTo(Speech._n(const Duration(seconds: 25))));
      expect(decoder.overWindow, 1, reason: 'only the segment-end decode reads more than the 12 s window');
    });

    test('«سمّع ثم تحقّق»: nothing until the end, then every word at once', () async {
      final speech = Speech(vocab)
        ..say(['قل', 'هو', 'الله'])
        ..silence(const Duration(milliseconds: 900))
        ..say(['احد'])
        ..silence(const Duration(milliseconds: 300));
      final decoder = BurstDecoder(vocab);
      final t = LiveTranscriber(decoder: decoder, activity: EnergyActivity(), live: false);
      final updates = await run(t, speech.samples);
      expect(updates, hasLength(1));
      expect(updates.single.isFinal, isTrue);
      expect(updates.single.committed.map((w) => w.text), ['قل', 'هو', 'الله', 'احد']);
      expect(decoder.calls, 2); // one decode per speech segment
    });

    test('PCM bytes, levels, WAV round trip', () {
      final bytes = Uint8List.fromList([0x00, 0x40, 0x00, 0xC0, 0xFF]);
      final dec = Pcm16Decoder();
      expect(dec.convert(bytes), [0.5, -0.5]);
      expect(dec.convert(Uint8List.fromList([0x7F])), [32767 / 32768]); // the carried byte joins the next chunk
      expect(levelOf(Float32List(160)), 0);
      expect(levelOf(Float32List.fromList(List.filled(160, 0.3))), greaterThan(0.5));
      final wav = readWav(wavBytes(Float32List.fromList([0, 0.5, -0.5])));
      expect(wav.sampleRate, asrSampleRate);
      expect(wav.samples[1], closeTo(0.5, 1e-3));
    });

    test('token times become word times only when the tokens spell the text', () {
      final w = wordsFromTokens(' قل هو', [' ق', 'ل', ' هو'], [0.1, 0.3, 0.6], 1.2);
      expect(w.map((x) => x.text), ['قل', 'هو']);
      expect([w[0].start, w[0].end, w[1].start, w[1].end], [0.1, 0.6, 0.6, 1.2]);
      final spread = wordsFromTokens('قل هو', ['?'], [0.1], 1.0);
      expect(spread.map((x) => x.text), ['قل', 'هو']);
      expect(spread.last.end, closeTo(1.0, 1e-9));
    });
  });

  group('live support (real-time factor)', () {
    test('slow phones check after reciting; the answer is remembered per model', () async {
      final kv = MemoryKvStore();
      var measured = 0;
      Future<SpeechDecoder> decoder() async {
        measured++;
        return _Silent();
      }

      Stopwatch slow() => _FakeStopwatch(const Duration(milliseconds: 2700)); // RTF 0.9
      final probe = _Silent();
      final s = await LiveSupportProbe.measure(probe, stopwatch: slow);
      expect(s.live, isFalse);
      expect(s.rtf, closeTo(0.9, 1e-9));
      expect(probe.calls, 2, reason: 'a warm-up, then the measured run');
      final fast = await LiveSupportProbe.measure(_Silent(), stopwatch: () => _FakeStopwatch(const Duration(milliseconds: 600)));
      expect(fast.live, isTrue);

      await LiveSupportProbe.remember(kv, 'm1', s);
      expect((await LiveSupportProbe.resolve(kv, 'm1', decoder)).live, isFalse);
      expect(measured, 0, reason: 'remembered: not measured again');
      expect(await LiveSupportProbe.remembered(kv, 'm2'), isNull, reason: 'a new model is measured again');
    });
  });

  group('model store (download, verify, delete)', () {
    late Directory dir;
    final served = <String>[];
    setUp(() async {
      served.clear();
      dir = await Directory.systemTemp.createTemp('asr');
    });
    tearDown(() async => dir.delete(recursive: true));

    final enc = utf8.encode('encoder-bytes' * 50);
    final decB = utf8.encode('decoder-bytes' * 80);
    final tok = utf8.encode('tokens');
    final vad = utf8.encode('vad');
    AsrModelManifest manifest({String? badSha}) => AsrModelManifest(
          id: 'test-model',
          upstream: 'x@1',
          licence: 'Apache-2.0',
          baseUrl: 'https://cdn.test/asr/',
          files: [
            AsrModelFile(AsrFileRole.encoder, 'e.onnx', bytes: enc.length, sha256: sha256.convert(enc).toString()),
            AsrModelFile(AsrFileRole.decoder, 'd.onnx', bytes: decB.length, sha256: badSha ?? sha256.convert(decB).toString()),
            AsrModelFile(AsrFileRole.tokens, 't.txt', bytes: tok.length, sha256: sha256.convert(tok).toString()),
            AsrModelFile(AsrFileRole.vad, 'v.onnx', bytes: vad.length, sha256: sha256.convert(vad).toString(), url: 'https://other.test/v.onnx'),
          ],
        );
    MockClient client() => MockClient((req) async {
          served.add(req.url.toString());
          final body = switch (req.url.path.split('/').last) {
            'e.onnx' => enc,
            'd.onnx' => decB,
            't.txt' => tok,
            'v.onnx' => vad,
            _ => <int>[],
          };
          return http.Response.bytes(body, body.isEmpty ? 404 : 200);
        });

    AsrModelStore store(KvStore kv, {AsrModelManifest? m, bool unmetered = true}) => AsrModelStore(
          root: () async => dir,
          kv: kv,
          isUnmetered: () async => unmetered,
          queue: DownloadQueue(),
          manifest: m ?? manifest(),
          client: client(),
        );

    test('downloads every file through the queue, verifies it, then is ready; delete reclaims it', () async {
      final kv = MemoryKvStore();
      final s = store(kv);
      expect(await s.isReady(), isFalse);
      var last = 0;
      await s.download(onProgress: (got, total) => last = got);
      expect(await s.isReady(), isTrue);
      expect(last, manifest().bytes);
      expect(served, contains('https://other.test/v.onnx'));
      expect(await s.wasDownloading(), isFalse);
      expect(await s.bytesOnDisk(), greaterThanOrEqualTo(manifest().bytes));
      await s.delete();
      expect(await s.isReady(), isFalse);
      expect(await s.bytesOnDisk(), 0);
    });

    test('a file that does not match its SHA-256 is thrown away; the model is not ready', () async {
      final kv = MemoryKvStore();
      final s = store(kv, m: manifest(badSha: 'f' * 64));
      await expectLater(s.download(), throwsA(isA<AsrChecksumMismatch>()));
      expect(await s.isReady(), isFalse);
      expect(File('${(await s.dir()).path}/d.onnx').existsSync(), isFalse);
      expect(await s.wasDownloading(), isTrue, reason: 'resumable at the next launch');
    });

    test('never on mobile data without the user saying so', () async {
      final kv = MemoryKvStore();
      final s = store(kv, unmetered: false);
      await expectLater(s.download(), throwsA(isA<WifiRequired>()));
      expect(served, isEmpty);
      await s.download(allowMetered: true);
      expect(await s.isReady(), isTrue);
      expect(await s.allowedMetered(), isTrue);
    });

    test('nothing is offered when a build has no published model', () async {
      const unpublished = AsrModelManifest(
        id: 'x',
        upstream: 'x',
        licence: 'x',
        baseUrl: '',
        files: [AsrModelFile(AsrFileRole.encoder, 'e', bytes: 1, sha256: '')],
      );
      expect(unpublished.published, isFalse);
      expect(AsrModelManifest.interim.published, isTrue);
      expect(AsrModelManifest.interim.bytes, greaterThan(100 * 1000 * 1000));
      // Ours: 44.5 MB in all (tools/asr/manifest.json).
      expect(AsrModelManifest.yaqeen.files.where((f) => f.role != AsrFileRole.vad).every((f) => f.sha256.length == 64), isTrue);
      expect(AsrModelManifest.yaqeen.bytes, inInclusiveRange(40 * 1000 * 1000, 46 * 1000 * 1000));
    });

    test('the pinned manifest in the app matches tools/asr/manifest.json', () {
      final m = jsonDecode(File('../../tools/asr/manifest.json').readAsStringSync()) as Map<String, dynamic>;
      final files = {for (final f in (m['files'] as List).cast<Map<String, dynamic>>()) f['name']: f};
      for (final f in AsrModelManifest.yaqeen.files) {
        expect(files[f.name]?['sha256'], f.sha256, reason: f.name);
        expect(files[f.name]?['bytes'], f.bytes, reason: f.name);
      }
    });
  });
}

class _Silent implements SpeechDecoder {
  int calls = 0;
  @override
  Future<List<RecognizedWord>> decode(Float32List samples) async {
    calls++;
    return const [];
  }

  @override
  Future<void> dispose() async {}
}

class _FakeStopwatch implements Stopwatch {
  _FakeStopwatch(this.elapsed);
  @override
  final Duration elapsed;
  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
