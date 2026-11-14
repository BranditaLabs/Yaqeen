import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../text/arabic.dart';
import '../recitation_engine.dart';
import 'pcm.dart';

/// Recognises one buffer of speech (16 kHz mono). Word times are seconds from the buffer's first
/// sample; an implementation without real timestamps spreads the words over the buffer.
abstract interface class SpeechDecoder {
  Future<List<RecognizedWord>> decode(Float32List samples);
  Future<void> dispose();
}

/// Voice activity: is someone speaking at the end of these samples? (Silero VAD on the phone; an
/// energy gate in tests and as the fallback.)
abstract interface class SpeechActivity {
  bool accept(Float32List samples);
  void reset();
  void dispose();
}

/// A plain energy gate with a short hangover — enough for clean test audio and as a fallback.
class EnergyActivity implements SpeechActivity {
  EnergyActivity({this.threshold = 0.02, this.hangover = const Duration(milliseconds: 200)});
  final double threshold;
  final Duration hangover;
  int _quiet = 1 << 30;

  @override
  bool accept(Float32List samples) {
    var peak = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    if (peak >= threshold) {
      _quiet = 0;
    } else {
      _quiet += samples.length;
    }
    return _quiet <= hangover.inMicroseconds * asrSampleRate ~/ 1000000;
  }

  @override
  void reset() => _quiet = 1 << 30;
  @override
  void dispose() {}
}

/// Spreads [text]'s words over [seconds] by letter count — for decoders without token times.
List<RecognizedWord> spreadWords(String text, double seconds, {double offset = 0}) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  final letters = words.fold<int>(0, (s, w) => s + w.length);
  var t = offset;
  return [
    for (final w in words)
      () {
        final d = seconds * w.length / letters;
        final r = RecognizedWord(w, start: t, end: t + d);
        t += d;
        return r;
      }(),
  ];
}

class _Segment {
  _Segment(this.start);

  /// Global sample index of the first sample still held.
  int start;
  final chunks = <Float32List>[];
  int length = 0;
  bool ended = false;

  /// The last decode's words after the committed ones (absolute times), for agreement.
  List<RecognizedWord> pending = const [];

  void add(Float32List s) {
    chunks.add(s);
    length += s.length;
  }

  Float32List snapshot() {
    final out = Float32List(length);
    var at = 0;
    for (final c in chunks) {
      out.setAll(at, c);
      at += c.length;
    }
    return out;
  }

  /// Drops samples before global index [to].
  void trimTo(int to) {
    var drop = to - start;
    if (drop <= 0) return;
    drop = math.min(drop, length);
    final all = snapshot();
    chunks
      ..clear()
      ..add(Float32List.sublistView(all, drop));
    length -= drop;
    start += drop;
  }
}

/// The live recognition loop (spec §6.8), pure Dart so it is tested with a fake decoder:
///
/// 16 kHz mono PCM → voice activity cuts speech segments (a pause of [endSilence] ends one) → while a
/// segment runs, the audio since the last committed word is decoded every [decodeEvery] (never two
/// decodes at once: a slow phone simply decodes less often), and the words two decodes in a row agree
/// on are committed (they never change again); the buffer then starts after the last committed word,
/// and it never grows past [window] (the oldest words are committed when it would). A segment that
/// ends is decoded once more and committed whole. Long sessions (a page or more) are just many
/// segments. With `live: false` nothing is decoded until [finish] («سمّع ثم تحقّق»): the speech
/// segments are kept (in memory only) and checked at once.
class LiveTranscriber {
  LiveTranscriber({
    required this.decoder,
    required this.activity,
    this.live = true,
    this.decodeEvery = const Duration(milliseconds: 1200),
    this.window = const Duration(seconds: 8),
    this.endSilence = const Duration(milliseconds: 600),
    this.preRoll = const Duration(milliseconds: 300),
    this.maxSegment = const Duration(seconds: 25),
  });

  final SpeechDecoder decoder;
  final SpeechActivity activity;
  final bool live;
  final Duration decodeEvery;
  final Duration window;
  final Duration endSilence;
  final Duration preRoll;

  /// Whisper reads at most 30 s at a time: a longer stretch without a pause is cut here.
  final Duration maxSegment;

  final _updates = StreamController<RecognitionUpdate>();
  Stream<RecognitionUpdate> get updates => _updates.stream;

  static int _samples(Duration d) => d.inMicroseconds * asrSampleRate ~/ 1000000;
  static double _seconds(int samples) => samples / asrSampleRate;

  int _total = 0;
  final _pre = <Float32List>[];
  int _preLength = 0;
  _Segment? _current;
  final _segments = <_Segment>[];
  int _silence = 0;
  int _sinceDecode = 0;
  bool _busy = false;
  bool _finished = false;
  Future<void> _chain = Future.value();
  final _committed = <RecognizedWord>[];

  /// Seconds of audio received.
  double get elapsed => _seconds(_total);

  List<RecognizedWord> get committed => List.unmodifiable(_committed);

  void add(Float32List samples) {
    if (_finished || samples.isEmpty) return;
    final speaking = activity.accept(samples);
    _total += samples.length;
    final seg = _current;
    if (seg == null) {
      _pre.add(samples);
      _preLength += samples.length;
      while (_pre.isNotEmpty && _preLength - _pre.first.length >= _samples(preRoll)) {
        _preLength -= _pre.removeAt(0).length;
      }
      if (!speaking) return;
      final s = _Segment(_total - _preLength);
      for (final c in _pre) {
        s.add(c);
      }
      _pre.clear();
      _preLength = 0;
      _current = s;
      _segments.add(s);
      _silence = 0;
      _sinceDecode = s.length;
      return;
    }
    seg.add(samples);
    _sinceDecode += samples.length;
    _silence = speaking ? 0 : _silence + samples.length;
    if (_silence >= _samples(endSilence) || seg.length >= _samples(maxSegment)) {
      _endSegment(seg);
    } else if (live && !_busy && _sinceDecode >= _samples(decodeEvery)) {
      _sinceDecode = 0;
      _busy = true;
      _run(() => _decodeTentative(seg)).whenComplete(() => _busy = false).ignore();
    }
  }

  void _endSegment(_Segment seg) {
    seg.ended = true;
    _current = null;
    _silence = 0;
    if (live) _run(() => _decodeFinal(seg)).ignore();
  }

  Future<void> _run(Future<void> Function() job) => _chain = _chain.then((_) => job()).catchError((Object _) {});

  List<RecognizedWord> _absolute(List<RecognizedWord> words, int start) {
    final at = _seconds(start);
    return [for (final w in words) RecognizedWord(w.text, start: w.start + at, end: w.end + at)];
  }

  static String _key(String w) => ArabicText.normalize(w).replaceAll(RegExp(r'[^ء-ي]'), '');

  Future<void> _decodeTentative(_Segment seg) async {
    if (seg.ended) return;
    // The buffer never grows past the window: the oldest pending words are committed first.
    if (seg.length > _samples(window) && seg.pending.length > 1) {
      final keep = seg.pending.last;
      _commit(seg, seg.pending.sublist(0, seg.pending.length - 1));
      seg.pending = [keep];
    }
    if (seg.length > _samples(window)) seg.trimTo(seg.start + seg.length - _samples(window));
    if (seg.length < _samples(const Duration(milliseconds: 500))) return;
    final start = seg.start;
    final hyp = _absolute(await decoder.decode(seg.snapshot()), start);
    if (seg.ended) return;
    // Local agreement: what this decode and the last one both say, from the start, is stable.
    var k = 0;
    while (k < hyp.length && k < seg.pending.length && _key(hyp[k].text) == _key(seg.pending[k].text)) {
      k++;
    }
    if (k > 0) _commit(seg, hyp.sublist(0, k));
    seg.pending = hyp.sublist(k);
    _emit(seg.pending);
  }

  void _commit(_Segment seg, List<RecognizedWord> words) {
    if (words.isEmpty) return;
    _committed.addAll(words);
    seg.trimTo((words.last.end * asrSampleRate).round());
  }

  Future<void> _decodeFinal(_Segment seg) async {
    final words = seg.length < _samples(const Duration(milliseconds: 250))
        ? const <RecognizedWord>[]
        : _absolute(await decoder.decode(seg.snapshot()), seg.start);
    _committed.addAll(words);
    seg
      ..pending = const []
      ..chunks.clear()
      ..length = 0;
    _segments.remove(seg);
    // A recording checked at once shows its marks together, with the final update.
    if (live) _emit(const []);
  }

  void _emit(List<RecognizedWord> tentative, {bool isFinal = false}) {
    if (_updates.isClosed) return;
    _updates.add(RecognitionUpdate(committed: List.unmodifiable(_committed), tentative: List.unmodifiable(tentative), isFinal: isFinal));
  }

  /// The end of listening: what is still pending is decoded and committed, a final update follows,
  /// and the stream closes. Non-live sessions are checked here, segment by segment.
  Future<void> finish() async {
    if (_finished) return _chain;
    _finished = true;
    final seg = _current;
    if (seg != null) {
      seg.ended = true;
      _current = null;
      if (live) _run(() => _decodeFinal(seg)).ignore();
    }
    if (!live) {
      for (final s in [..._segments]) {
        _run(() => _decodeFinal(s)).ignore();
      }
    }
    await _chain;
    _emit(const [], isFinal: true);
    await _updates.close();
  }

  /// Leaves without a final decode (the app went to the background mid-way).
  Future<void> cancel() async {
    _finished = true;
    await _updates.close();
  }
}

/// Words with times from a decoder's [text] and its tokens' start times (seconds into a buffer of
/// [seconds]). Tokens only count when they spell the text exactly (a BPE token may split a letter's
/// bytes); otherwise the words are spread over the buffer ([spreadWords]).
List<RecognizedWord> wordsFromTokens(String text, List<String> tokens, List<double> timestamps, double seconds) {
  final clean = text.trim();
  if (clean.isEmpty) return const [];
  if (tokens.isEmpty || tokens.length != timestamps.length || tokens.join().trim() != clean) return spreadWords(clean, seconds);
  final joined = tokens.join();
  final lead = joined.length - joined.trimLeft().length;
  // Token index for each character of the trimmed text.
  final owner = List<int>.filled(clean.length, 0);
  var at = -lead;
  for (var i = 0; i < tokens.length; i++) {
    for (var k = 0; k < tokens[i].length; k++, at++) {
      if (at >= 0 && at < clean.length) owner[at] = i;
    }
  }
  final starts = <(String, double)>[
    for (final m in RegExp(r'\S+').allMatches(clean)) (m.group(0)!, timestamps[owner[m.start]].clamp(0.0, seconds)),
  ];
  final out = <RecognizedWord>[];
  for (var i = 0; i < starts.length; i++) {
    final s = i == 0 ? starts[i].$2 : math.max(starts[i].$2, out.last.start);
    final e = i + 1 < starts.length ? math.max(s, starts[i + 1].$2) : seconds;
    out.add(RecognizedWord(starts[i].$1, start: s, end: math.max(s, e)));
  }
  return out;
}
