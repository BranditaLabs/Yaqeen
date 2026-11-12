import 'quran_data.dart';

/// Colours for bookmarks and highlights — brand tokens only (gold, lapis, sky, success).
enum MarkColor { gold, lapis, sky, green }

/// A private note on an ayah — device first; optional encrypted cloud backup (consent `cloud_backup`,
/// spec §6.13).
class AyahNote {
  const AyahNote({required this.ref, required this.text, required this.at});
  final AyahRef ref;
  final String text;
  final DateTime at;

  static const maxLength = 2000;

  Map<String, dynamic> toJson() => {'s': ref.surah, 'a': ref.ayah, 't': text, 'at': at.toIso8601String()};
  factory AyahNote.fromJson(Map<String, dynamic> j) => AyahNote(
        ref: AyahRef(j['s'] as int, j['a'] as int),
        text: j['t'] as String,
        at: DateTime.tryParse((j['at'] as String?) ?? '') ?? DateTime(2000),
      );
}

/// Everything the reader paints on top of the text: highlights and which ayat carry a note.
class Annotations {
  const Annotations({this.highlights = const {}, this.notes = const {}});
  final Map<AyahRef, MarkColor> highlights;
  final Map<AyahRef, AyahNote> notes;

  static const empty = Annotations();
}
