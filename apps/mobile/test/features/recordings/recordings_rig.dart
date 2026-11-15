import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/platform/audio_engine.dart';
import 'package:yaqeen/core/platform/audio_recorder.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/features/recite/domain/recitation.dart';
import 'package:yaqeen/features/recordings/presentation/recordings_providers.dart';

/// Shared rig for the «تلاواتي» tests: a MockClient API routed by `METHOD /path`, the real mushaf
/// text, an in-memory KV store, a temp files dir, a scripted microphone and recogniser, the flag on.

http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Response errorResponse(int status, String code, {Map<String, Object?>? details}) => jsonResponse(
      {
        'error': {'code': code, 'message': code, if (details != null) 'details': details},
      },
      status,
    );

Map<String, dynamic> recFixture(String name) =>
    (jsonDecode(File('test/fixtures/recordings/$name').readAsStringSync()) as Map).cast<String, dynamic>();

QuranData? _quran;

/// The bundled mushaf text (parsed once for the whole test file).
QuranData quranData() =>
    _quran ??= QuranData.fromJson(jsonDecode(File('assets/quran/quran.json').readAsStringSync()) as Map<String, dynamic>);

/// A fixture recording list where every avatar is a preset (no network images).
Map<String, dynamic> memberRecordingsFixture() {
  final j = recFixture('member_recordings.json');
  Map<String, dynamic> preset(Object? o) => {...(o as Map).cast<String, dynamic>(), 'avatar': {'kind': 'preset', 'id': 'm03'}};
  j['owner'] = preset(j['owner']);
  j['items'] = [
    for (final r in j['items'] as List) {...(r as Map).cast<String, dynamic>(), 'owner': preset(r['owner'])},
  ];
  return j;
}

typedef ApiRoute = FutureOr<http.Response> Function(http.Request req);

class RecordingsRig {
  RecordingsRig({Map<String, ApiRoute>? routes, this.signedIn = true, Map<String, bool>? flags}) : routes = {...?routes} {
    features = {
      ...RemoteConfig.defaultFeatures,
      Flags.recordings: true,
      Flags.leaderboard: true,
      Flags.leagues: true,
      ...?flags,
    };
    api = ApiClient(
      baseUrl: 'https://api.test',
      tokens: TokenStore(MemoryKvStore()),
      client: MockClient((req) async {
        final key = '${req.method} ${req.url.path}';
        calls.add(req.url.query.isEmpty ? key : '$key?${req.url.query}');
        requests[key] = req;
        if (offlineAll) throw http.ClientException('offline');
        final route = this.routes[key];
        if (route == null) return errorResponse(404, 'not_found');
        return route(req);
      }),
    );
  }

  final Map<String, ApiRoute> routes;
  final bool signedIn;
  bool offlineAll = false;
  late final Map<String, bool> features;
  final kv = MemoryKvStore();
  late final ApiClient api;
  final calls = <String>[];
  final requests = <String, http.Request>{};
  final device = FakeDeviceServices();
  final dir = Directory.systemTemp.createTempSync('yq_recordings_test');
  final audio = FakeAudioEngine();
  DateTime now = DateTime.utc(2026, 11, 14, 10);

  late final recorder = FakeVoiceRecorder(writeFile: (path, bytes) async => File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes),);
  RecitationEngine engine = const UnavailableRecitationEngine();

  List<Override> get overrides => [
        apiClientProvider.overrideWithValue(api),
        filesDirProvider.overrideWithValue(() async => dir),
        deviceServicesProvider.overrideWithValue(device),
        clockProvider.overrideWithValue(() => now),
        audioEngineProvider.overrideWithValue(audio),
        quranDataProvider.overrideWith((_) async => quranData()),
        voiceRecorderProvider.overrideWithValue(recorder),
        recitationEngineProvider.overrideWithValue(engine),
        initialConfigProvider.overrideWithValue(RemoteConfig(features: features)),
        initialSessionProvider.overrideWithValue(
          signedIn
              ? const Session(provider: SignInProvider.google, userId: 'u1', displayName: 'أحمد محمود')
              : const Session(provider: SignInProvider.guest, userId: 'g1'),
        ),
      ];

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [kvStoreProvider.overrideWithValue(kv), secureStoreProvider.overrideWithValue(MemoryKvStore()), ...overrides]);
    return c;
  }
}

/// A recogniser fed by the recorder's PCM: [emit] sends what was heard; when the PCM stream ends it
/// sends [finalWords] (or the last update) as the final, whole-take result.
class PcmFakeEngine extends RecitationEngine {
  PcmFakeEngine({this.live = true, this.available = true});
  bool live;
  bool available;
  StreamController<RecognitionUpdate>? _out;
  StreamSubscription<Float32List>? _pcm;
  RecognitionUpdate? _last;
  List<RecognizedWord>? finalWords;
  int pcmChunks = 0;
  bool? startedLive;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<LiveSupport> liveSupport() async => LiveSupport(live: live, rtf: live ? 0.3 : 1.4);
  @override
  Stream<RecognitionUpdate> listen({bool live = true}) => const Stream.empty();

  @override
  Stream<RecognitionUpdate> startFromPcm(Stream<Float32List> pcm, {bool live = true}) {
    startedLive = live;
    final out = _out = StreamController<RecognitionUpdate>();
    _pcm = pcm.listen((_) => pcmChunks++, onDone: () {
      final words = finalWords ?? _last?.words ?? const <RecognizedWord>[];
      out.add(RecognitionUpdate(committed: words, isFinal: true));
      out.close();
    },);
    return out.stream;
  }

  /// Words heard so far (committed), with times (seconds).
  void emit(List<(String, double, double)> words) {
    final u = RecognitionUpdate(committed: [for (final (w, s, e) in words) RecognizedWord(w, start: s, end: e)]);
    _last = u;
    _out?.add(u);
  }

  @override
  Future<void> stop() async {
    await _pcm?.cancel();
  }
}

/// `(word, start, end)` triples for the first [n] words of [text], 0.4 s each.
List<(String, double, double)> spoken(String text, {int? n, double from = 0.5}) {
  final words = RecitationAligner.words(text);
  final take = n == null ? words : words.take(n).toList();
  return [for (final (i, w) in take.indexed) (w, from + i * 0.4, from + i * 0.4 + 0.35)];
}
