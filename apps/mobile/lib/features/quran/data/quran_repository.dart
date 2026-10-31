import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/mushaf_layout.dart';
import '../domain/quran_data.dart';

/// Loads the bundled mushaf once (parsed off the UI thread). Works in airplane mode on day one.
///
/// The text (quran.json) and the printed line layout (layout_v2.json) are parsed together; the page
/// boundaries come from the layout, so what the reader draws and what the app counts are the same pages.
/// Without a readable layout the text still loads with its own (Tanzil) boundaries.
class QuranRepository {
  QuranRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  Future<_Parsed>? _parsed;

  Future<_Parsed> _load() => _parsed ??= () async {
        final raw = await _bundle.loadString('assets/quran/quran.json', cache: false);
        String? layout;
        try {
          layout = await _bundle.loadString(layoutAsset, cache: false);
        } on Object {
          layout = null;
        }
        // Decode *and* build the models on a background isolate; the result moves back without a copy.
        return compute(_parse, (raw, layout));
      }()
          .catchError((Object e) {
        _parsed = null; // a later watch retries instead of caching the failure
        throw e;
      });

  static const layoutAsset = 'assets/quran/layout_v2.json';

  Future<QuranData> load() async => (await _load()).quran;

  /// The printed page layout, or null when it could not be read (the reader then sets text pages).
  Future<MushafLayout?> layout() async => (await _load()).layout;

  static _Parsed _parse((String, String?) raw) {
    MushafLayout? layout;
    if (raw.$2 != null) {
      try {
        layout = MushafLayout.fromJson(jsonDecode(raw.$2!) as Map<String, dynamic>);
      } on Object {
        layout = null;
      }
    }
    final quran = QuranData.fromJson(jsonDecode(raw.$1) as Map<String, dynamic>, pageStarts: layout?.starts);
    return _Parsed(quran, layout);
  }
}

class _Parsed {
  const _Parsed(this.quran, this.layout);
  final QuranData quran;
  final MushafLayout? layout;
}
