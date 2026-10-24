import '../../quran/domain/quran_data.dart';

enum RecitationStyle { murattal, mujawwad }

/// A licensed recitation from `GET /v1/content/reciters` (spec §5.14). Surah files live at
/// `<baseUrl>/<sss>.mp3` (zero-padded surah number); `timingUrl` is a JSON map of per-ayah timings.
class Reciter {
  const Reciter({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.style,
    required this.riwaya,
    required this.baseUrl,
    this.timingUrl,
    this.sampleUrl,
    this.sizeBytes = 0,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final RecitationStyle style;
  final String riwaya;
  final String baseUrl;
  final String? timingUrl;
  final String? sampleUrl;
  final int sizeBytes;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;

  /// Initial for the avatar (first letter after a leading «ال»/article-free).
  String initial(String locale) {
    final n = name(locale).trim();
    return n.isEmpty ? '' : String.fromCharCode(n.runes.first);
  }

  Uri surahUrl(int surah) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/${surah.toString().padLeft(3, '0')}.mp3');

  /// Rough per-surah share of the full download (by ayah count) — for progress before headers arrive.
  int estimatedSurahBytes(Surah s) => (sizeBytes * s.ayahCount / QuranData.totalAyat).round();

  static Reciter? tryParse(Object? j) {
    if (j is! Map) return null;
    try {
      return Reciter(
        id: j['id'] as String,
        nameAr: j['nameAr'] as String,
        nameEn: j['nameEn'] as String,
        style: j['style'] == 'mujawwad' ? RecitationStyle.mujawwad : RecitationStyle.murattal,
        riwaya: (j['riwaya'] as String?) ?? 'hafs',
        baseUrl: j['baseUrl'] as String,
        timingUrl: j['timingUrl'] as String?,
        sampleUrl: j['sampleUrl'] as String?,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'style': style.name,
        'riwaya': riwaya,
        'baseUrl': baseUrl,
        'timingUrl': timingUrl,
        'sampleUrl': sampleUrl,
        'sizeBytes': sizeBytes,
      };
}

/// Per-ayah [start, end) in milliseconds for one surah of one reciter (spec §6.7).
/// File format: `{"<surah>": [[startMs, endMs], …]}` — index 0 is ayah 1.
class AyahTimings {
  AyahTimings(this.spans) : assert(spans.isNotEmpty);
  final List<(int, int)> spans;

  int get ayahCount => spans.length;

  static AyahTimings? fromJson(Object? j) {
    if (j is! List || j.isEmpty) return null;
    final spans = <(int, int)>[];
    for (final e in j) {
      if (e is! List || e.length < 2) return null;
      spans.add(((e[0] as num).toInt(), (e[1] as num).toInt()));
    }
    return AyahTimings(spans);
  }

  Duration startOf(int ayah) => Duration(milliseconds: spans[(ayah - 1).clamp(0, spans.length - 1)].$1);
  Duration endOf(int ayah) => Duration(milliseconds: spans[(ayah - 1).clamp(0, spans.length - 1)].$2);

  /// Ayah playing at [position] (binary search; positions before the first ayah map to 1 —
  /// the opening isti'adha/basmala belongs to the first ayah's highlight).
  int ayahAt(Duration position) {
    final ms = position.inMilliseconds;
    var lo = 0, hi = spans.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (spans[mid].$1 <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }
}

enum ListenRepeat { off, ayah, surah }

/// Persisted player state so playback resumes after an app kill (spec §5.13 acceptance).
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.reciterId,
    required this.surah,
    this.ayah = 1,
    this.position = Duration.zero,
    this.speed = 1.0,
    this.repeat = ListenRepeat.off,
  });

  final String reciterId;
  final int surah;
  final int ayah;
  final Duration position;
  final double speed;
  final ListenRepeat repeat;

  Map<String, dynamic> toJson() => {'r': reciterId, 's': surah, 'a': ayah, 'p': position.inMilliseconds, 'v': speed, 'rp': repeat.name};

  static PlaybackSnapshot? tryParse(Object? j) {
    if (j is! Map || j['r'] is! String || j['s'] is! int) return null;
    return PlaybackSnapshot(
      reciterId: j['r'] as String,
      surah: j['s'] as int,
      ayah: (j['a'] as int?) ?? 1,
      position: Duration(milliseconds: (j['p'] as int?) ?? 0),
      speed: (j['v'] as num?)?.toDouble() ?? 1.0,
      repeat: ListenRepeat.values.asNameMap()[j['rp']] ?? ListenRepeat.off,
    );
  }
}

/// «الاستماع» challenge task: ≥ 5 minutes of playback in a local day ticks `listen` once (spec §5.13).
class ListenDay {
  const ListenDay({required this.date, this.seconds = 0, this.ticked = false});
  final String date;
  final int seconds;
  final bool ticked;

  static const goalSeconds = 5 * 60;

  Map<String, dynamic> toJson() => {'date': date, 'sec': seconds, 'ticked': ticked};
  static ListenDay? tryParse(Object? j) => j is Map && j['date'] is String
      ? ListenDay(date: j['date'] as String, seconds: (j['sec'] as int?) ?? 0, ticked: (j['ticked'] as bool?) ?? false)
      : null;

  /// Adds [played] wall-clock listening (not media time — 1.5× speed doesn't count faster).
  static ({ListenDay day, bool tickNow}) add(ListenDay? current, {required String today, required Duration played}) {
    final base = current == null || current.date != today ? ListenDay(date: today) : current;
    final seconds = base.seconds + played.inSeconds;
    final tickNow = !base.ticked && seconds >= goalSeconds;
    return (day: ListenDay(date: today, seconds: seconds, ticked: base.ticked || tickNow), tickNow: tickNow);
  }
}

const listenSpeeds = [0.75, 1.0, 1.25, 1.5];
const sleepTimerMinutes = [15, 30, 45, 60];
