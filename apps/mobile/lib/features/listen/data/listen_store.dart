import '../../../core/storage/local_store.dart';
import '../domain/audio_models.dart';

/// Player state, chosen reciter and today's listening time — device only.
class ListenStore {
  ListenStore(this.store);
  final LocalStore store;
  static const _doc = 'listen';

  Future<Map<String, dynamic>> _read() => store.readMap(_doc);
  Future<void> _put(String k, Object? v) async {
    final d = await _read();
    d[k] = v;
    await store.write(_doc, d);
  }

  Future<String?> reciterId() async => (await _read())['reciter'] as String?;
  Future<void> setReciter(String id) => _put('reciter', id);

  Future<PlaybackSnapshot?> snapshot() async => PlaybackSnapshot.tryParse((await _read())['snapshot']);
  Future<void> saveSnapshot(PlaybackSnapshot s) => _put('snapshot', s.toJson());

  Future<ListenDay?> day() async => ListenDay.tryParse((await _read())['day']);
  Future<void> saveDay(ListenDay d) => _put('day', d.toJson());

  Future<bool> allowMetered() async => ((await _read())['metered'] as bool?) ?? false;
  Future<void> setAllowMetered(bool v) => _put('metered', v);
}
