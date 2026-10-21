import 'dart:convert';
import 'dart:io';

import '../domain/quran_data.dart';

/// Tafsir text for an ayah — from an installed, checksum-verified pack only (spec §6.6, §10).
/// Until a licensed pack is installed this returns null and the UI shows the bracketed placeholder.
class TafsirRepository {
  TafsirRepository({this.packFile});

  /// `tafsir_<id>.json` downloaded by the pack manager: {"<surah>:<ayah>": "<text>"}.
  final Future<File?> Function()? packFile;
  Map<String, String>? _cache;

  Future<String?> forAyah(AyahRef r) async {
    if (_cache == null) {
      final f = await packFile?.call();
      if (f == null || !f.existsSync()) return null;
      _cache = (jsonDecode(await f.readAsString()) as Map).cast<String, String>();
    }
    return _cache!['${r.surah}:${r.ayah}'];
  }
}
