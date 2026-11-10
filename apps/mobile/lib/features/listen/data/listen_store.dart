import '../../../core/storage/local_store.dart';
import '../domain/audio_models.dart';

/// Player state, chosen reciter and today's listening time — device first, with an optional encrypted
/// cloud backup (consent `cloud_backup`); downloads and the metered switch stay on this phone.
class ListenStore {
  ListenStore(this.store);
  final LocalStore store;
  static const _doc = 'listen';

  Future<Map<String, dynamic>> _read() => store.readMap(_doc);

  /// Every write is a read-modify-write of one document, and a pause fires two at once (today's
  /// listening time and the resume snapshot): run them one after another so none is lost.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _put(String k, Object? v) => _serial(() async {
        final d = await _read();
        d[k] = v;
        await store.write(_doc, d);
      });

  /// Cloud backup: the fields that follow the user to a new phone (not downloads, not the metered switch).
  static const backupKeys = ['reciter', 'snapshot', 'day'];
  Future<Map<String, dynamic>> backupFields() async {
    final d = await _read();
    return {for (final k in backupKeys) k: d[k]};
  }

  Future<void> restoreFields(Map<String, dynamic> fields) => _serial(() async {
        final d = await _read();
        for (final k in backupKeys) {
          if (fields.containsKey(k)) d[k] = fields[k];
        }
        await store.write(_doc, d);
      });

  Future<String?> reciterId() async => (await _read())['reciter'] as String?;
  Future<void> setReciter(String id) => _put('reciter', id);

  Future<PlaybackSnapshot?> snapshot() async => PlaybackSnapshot.tryParse((await _read())['snapshot']);
  Future<void> saveSnapshot(PlaybackSnapshot s) => _put('snapshot', s.toJson());

  Future<ListenDay?> day() async => ListenDay.tryParse((await _read())['day']);
  Future<void> saveDay(ListenDay d) => _put('day', d.toJson());

  Future<bool> allowMetered() async => ((await _read())['metered'] as bool?) ?? false;
  Future<void> setAllowMetered(bool v) => _put('metered', v);

  /// Reciters whose full download was started and not yet finished or cancelled — resumed on the
  /// next launch after a kill or restart.
  Future<Set<String>> downloading() async => _ids((await _read())['downloading']);
  Future<void> setDownloading(String reciterId, bool on) => _serial(() async {
        final d = await _read();
        final ids = _ids(d['downloading']);
        on ? ids.add(reciterId) : ids.remove(reciterId);
        d['downloading'] = ids.toList();
        await store.write(_doc, d);
      });

  static Set<String> _ids(Object? raw) => {...(raw as List? ?? const []).cast<String>()};
}
