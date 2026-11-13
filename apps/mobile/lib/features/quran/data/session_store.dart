import '../../../core/storage/kv_store.dart';

/// Device-only store of the «صفحة واحدة» session (passage, mode, stage, reveals, raw recite
/// results) — never in backup, export, profile, competitions, admin, analytics or ads.
/// Wiped on account deletion; kept on sign-out like other on-device Quran data.
///
/// Created by the contracts stream; the quran stream owns and fills it (keep [kvKey] and [wipe]).
abstract final class QuranSessionStore {
  static const kvKey = 'quran.session.v1';

  static Future<void> wipe(KvStore store) => store.delete(kvKey);
}
