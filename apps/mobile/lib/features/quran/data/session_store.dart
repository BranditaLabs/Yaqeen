import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/storage/kv_store.dart';
import '../domain/quran_session.dart';

/// Device-only store of the «صفحة واحدة» session (passage, mode, stage, reveals, raw recite
/// results) — never in backup, export, profile, competitions, admin, analytics or ads.
/// Wiped on account deletion; kept on sign-out like other on-device Quran data.
class QuranSessionStore {
  QuranSessionStore(this._kv);
  final KvStore _kv;

  static const kvKey = 'quran.session.v1';

  /// Account deletion (`session_controller.deleteAccount`) removes the session.
  static Future<void> wipe(KvStore store) => store.delete(kvKey);

  Future<QuranSession?> load() async {
    final raw = await _kv.read(kvKey);
    if (raw == null) return null;
    try {
      return QuranSession.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(QuranSession s) => _kv.write(kvKey, jsonEncode(s.toJson()));

  Future<void> clear() => wipe(_kv);
}

final quranSessionStoreProvider = Provider<QuranSessionStore>((ref) => QuranSessionStore(ref.watch(kvStoreProvider)));
