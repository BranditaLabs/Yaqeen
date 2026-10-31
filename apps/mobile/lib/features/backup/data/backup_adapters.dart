import 'dart:convert';

import '../../../core/settings/app_settings.dart';
import '../../../core/storage/kv_store.dart';
import '../../../core/storage/local_store.dart';
import '../../azkar/data/azkar_store.dart';
import '../../hifz/data/hifz_repository.dart';
import '../../home/data/tasbeeh_controller.dart';
import '../../listen/data/listen_store.dart';
import '../../quran/data/reading_repository.dart';
import '../../quran/domain/reading_stats.dart';
import '../../ramadan/data/ramadan_repository.dart';
import '../domain/backup_merge.dart';

/// One kind of the cloud backup: how to read this phone's copy, write a merged one back, merge
/// two copies, and which store keys mean "it changed". Stores keep working exactly as before —
/// an adapter only reads and writes the documents they already keep.
abstract class BackupAdapter {
  BackupKind get kind;

  /// The KvStore keys that hold this kind (a write to one schedules a backup).
  bool watches(String key);

  /// How long to wait after a change before uploading (playback positions change every few seconds).
  Duration get debounce => const Duration(seconds: 5);

  Future<Json> export();
  Future<void> import(Json doc);
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt});

  /// Nothing worth uploading (a fresh install never overwrites a backup with emptiness).
  bool isEmpty(Json doc) => doc.values.every((v) => v == null || (v is Map && v.isEmpty) || (v is List && v.isEmpty));
}

Json _base(Json? base) => base ?? const {};

/* -------------------------------------------------------------- Quran */

/// Last page, bookmarks, today's wird and reading stats.
class QuranReadingBackup extends BackupAdapter {
  QuranReadingBackup(this.repo);
  final ReadingRepository repo;
  static const fields = ['lastRead', 'bookmarks', 'wird', 'stats'];

  @override
  BackupKind get kind => BackupKind.quranReading;
  @override
  bool watches(String key) => key == 'db.reading';
  @override
  Future<Json> export() => repo.backupFields(fields);
  @override
  Future<void> import(Json doc) => repo.restoreFields({for (final f in fields) f: doc[f]});

  static String bookmarkKey(Json b) => b['k'] == 'page' ? 'p${b['p']}' : 'a${b['s']}:${b['a']}';

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) {
    Map<String, Json> marks(Object? list) => {
          for (final e in asList(list))
            if (asJson(e) case final b?) bookmarkKey(b): b,
        };
    final bookmarks = BackupMerge.keyed<Json>(
      marks(local['bookmarks']),
      marks(remote['bookmarks']),
      base == null ? null : marks(base['bookmarks']),
      at: (b) => asTime(b['at']),
    ).values.toList()
      ..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));

    // The last page carries its own time: the later read wins.
    final ll = asJson(local['lastRead']);
    final rl = asJson(remote['lastRead']);
    final lastRead = ll == null
        ? rl
        : rl == null
            ? ll
            : ((asTime(rl['at']) ?? DateTime(2000)).isAfter(asTime(ll['at']) ?? DateTime(2000)) ? rl : ll);

    final wird = BackupMerge.day(
      asJson(local['wird']),
      asJson(remote['wird']),
      (l, r) => {
        'date': l['date'],
        'pages': ({...asList(l['pages']).whereType<int>(), ...asList(r['pages']).whereType<int>()}.toList()..sort()),
        'ticked': l['ticked'] == true || r['ticked'] == true,
      },
    );

    Map<String, List<int>> days(Object? j) => {
          for (final e in (asJson(j) ?? const {}).entries)
            e.key: [
              for (final v in asList(e.value))
                if (v is num) v.toInt(),
            ],
        };
    final stats = BackupMerge.dailyMax(days(local['stats']), days(remote['stats']), keepDays: ReadingStats.keepDays);

    return {'lastRead': lastRead, 'bookmarks': bookmarks, 'wird': wird, 'stats': stats};
  }
}

/// Highlights (`{"s:a": colour}`) and notes.
class QuranNotesBackup extends BackupAdapter {
  QuranNotesBackup(this.repo);
  final ReadingRepository repo;

  @override
  BackupKind get kind => BackupKind.quranNotes;
  @override
  bool watches(String key) => key == 'db.reading';
  @override
  Future<Json> export() => repo.backupFields(const ['highlights', 'notes']);
  @override
  Future<void> import(Json doc) => repo.restoreFields({'highlights': doc['highlights'], 'notes': doc['notes']});

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) {
    Map<String, Object?> hl(Object? j) => {...?asJson(j)};
    Map<String, Json> notes(Object? list) => {
          for (final e in asList(list))
            if (asJson(e) case final n?) '${n['s']}:${n['a']}': n,
        };
    final highlights =
        BackupMerge.keyed<Object?>(hl(local['highlights']), hl(remote['highlights']), base == null ? null : hl(base['highlights']));
    final merged = BackupMerge.keyed<Json>(
      notes(local['notes']),
      notes(remote['notes']),
      base == null ? null : notes(base['notes']),
      at: (n) => asTime(n['at']),
    ).values.toList()
      ..sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
    return {'highlights': highlights, 'notes': merged};
  }
}

/// The active khatma plan (last writer wins) and the finished ones (union).
class KhatmaBackup extends BackupAdapter {
  KhatmaBackup(this.repo);
  final ReadingRepository repo;

  @override
  BackupKind get kind => BackupKind.khatma;
  @override
  bool watches(String key) => key == 'db.reading';
  @override
  Future<Json> export() => repo.backupFields(const ['khatma', 'khatmaHistory']);
  @override
  Future<void> import(Json doc) => repo.restoreFields({'khatma': doc['khatma'], 'khatmaHistory': doc['khatmaHistory']});

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) {
    Map<String, Json> history(Object? list) => {
          for (final e in asList(list))
            if (asJson(e) case final h?) '${h['startedOn']}|${h['finishedOn']}': h,
        };
    final plan = BackupMerge.lww<Object?>(
      local['khatma'],
      remote['khatma'],
      hasBase: base != null,
      base: _base(base)['khatma'],
      localAt: localAt,
      remoteAt: remoteAt,
    );
    final done = BackupMerge.keyed<Json>(
      history(local['khatmaHistory']),
      history(remote['khatmaHistory']),
      base == null ? null : history(base['khatmaHistory']),
    ).values.toList()
      ..sort((a, b) => '${b['finishedOn']}'.compareTo('${a['finishedOn']}'));
    return {'khatma': plan, 'khatmaHistory': done};
  }
}

/* --------------------------------------------------------------- hifz */

/// The whole hifz plan and review state, last writer wins.
class HifzBackup extends BackupAdapter {
  HifzBackup(this.store);
  final LocalStore store;

  @override
  BackupKind get kind => BackupKind.hifz;
  @override
  bool watches(String key) => key == 'db.hifz';
  @override
  Future<Json> export() async => {'plan': await store.read(HifzRepository.doc)};
  @override
  Future<void> import(Json doc) => store.write(HifzRepository.doc, doc['plan'] ?? const <String, Object>{});

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) {
    // A cleared plan is `{}` — treat it like none so an empty phone never wins against a real plan.
    Object? plan(Json d) => (d['plan'] is Map && (d['plan'] as Map).isEmpty) ? null : d['plan'];
    final l = plan(local);
    final r = plan(remote);
    if (l == null && r != null && (base == null || plan(base) == null)) return {'plan': r};
    return {
      'plan': BackupMerge.lww<Object?>(
        l,
        r,
        hasBase: base != null,
        base: base == null ? null : plan(base),
        localAt: localAt,
        remoteAt: remoteAt,
      ),
    };
  }
}

/* -------------------------------------------------------------- azkar */

/// Today's azkar counts and the favourite duas.
class AzkarBackup extends BackupAdapter {
  AzkarBackup(this.store);
  final LocalStore store;

  @override
  BackupKind get kind => BackupKind.azkar;
  @override
  bool watches(String key) => key == 'db.azkar' || key == 'db.favourites';
  @override
  Future<Json> export() async => {'day': await store.read('azkar'), 'favourites': await store.readList('favourites')};
  @override
  Future<void> import(Json doc) async {
    if (doc['day'] != null) await store.write('azkar', doc['day'] as Object);
    final favs = AzkarStore(store);
    await favs.saveFavourites(asStringSet(doc['favourites']));
  }

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) {
    final day = BackupMerge.day(
      asJson(local['day']),
      asJson(remote['day']),
      (l, r) => {
        'date': l['date'],
        'counts': BackupMerge.countsMax(asCounts(l['counts']), asCounts(r['counts'])),
        'ticked': ({...asStringSet(l['ticked']), ...asStringSet(r['ticked'])}.toList()..sort()),
      },
    );
    final favs = BackupMerge.set(
      asStringSet(local['favourites']),
      asStringSet(remote['favourites']),
      base == null ? null : asStringSet(base['favourites']),
    ).toList()
      ..sort();
    return {'day': day, 'favourites': favs};
  }
}

/* ------------------------------------------------------------- listen */

/// The chosen reciter, where playback stopped and today's listening time (never the audio files).
class ListenBackup extends BackupAdapter {
  ListenBackup(this.store);
  final ListenStore store;

  @override
  BackupKind get kind => BackupKind.listen;
  @override
  bool watches(String key) => key == 'db.listen';
  @override
  Duration get debounce => const Duration(minutes: 2);
  @override
  Future<Json> export() => store.backupFields();
  @override
  Future<void> import(Json doc) => store.restoreFields(doc);

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) {
    final b = _base(base);
    Object? pick(String k) {
      if (local[k] == null) return remote[k];
      if (remote[k] == null) return local[k];
      return BackupMerge.lww<Object?>(local[k], remote[k], hasBase: base != null, base: b[k], localAt: localAt, remoteAt: remoteAt);
    }

    final day = BackupMerge.day(
      asJson(local['day']),
      asJson(remote['day']),
      (l, r) => {
        'date': l['date'],
        'sec': ((l['sec'] as num?) ?? 0) > ((r['sec'] as num?) ?? 0) ? l['sec'] : r['sec'],
        'ticked': l['ticked'] == true || r['ticked'] == true,
      },
    );
    return {'reciter': pick('reciter'), 'snapshot': pick('snapshot'), 'day': day};
  }
}

/* ------------------------------------------------------------ routine */

/// When the user reads Quran, reviews hifz and does dhikr (never the place or coordinates).
class RoutineBackup extends BackupAdapter {
  RoutineBackup({required this.load, required this.apply});

  /// The current settings, and how to apply restored slots (through the settings controller).
  final Future<AppSettings> Function() load;
  final Future<void> Function(RoutineSlot quran, RoutineSlot hifz, RoutineSlot dhikr) apply;
  static const fields = ['quranSlot', 'hifzSlot', 'dhikrSlot'];

  @override
  BackupKind get kind => BackupKind.routine;
  @override
  bool watches(String key) => key == 'settings.v1';
  @override
  Future<Json> export() async {
    final s = await load();
    return {'quranSlot': s.quranSlot.toJson(), 'hifzSlot': s.hifzSlot.toJson(), 'dhikrSlot': s.dhikrSlot.toJson()};
  }

  @override
  Future<void> import(Json doc) async {
    final s = await load();
    await apply(
      RoutineSlot.fromJson(doc['quranSlot'], s.quranSlot),
      RoutineSlot.fromJson(doc['hifzSlot'], s.hifzSlot),
      RoutineSlot.fromJson(doc['dhikrSlot'], s.dhikrSlot),
    );
  }

  @override
  bool isEmpty(Json doc) => false; // the defaults are a choice too

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) => {
        for (final f in fields)
          f: remote[f] == null
              ? local[f]
              : BackupMerge.lww<Object?>(
                  local[f],
                  remote[f],
                  hasBase: base != null,
                  base: _base(base)[f],
                  localAt: localAt,
                  remoteAt: remoteAt,
                ),
      };
}

/* ------------------------------------------------------------ ramadan */

/// Every Ramadan's tracker (fasts, taraweeh, juz read), by Hijri year.
class RamadanBackup extends BackupAdapter {
  RamadanBackup(this.kv, {this.firstYear = 1440, this.lastYear = 1480});
  final KvStore kv;
  final int firstYear;
  final int lastYear;
  static const tracks = ['fasted', 'taraweeh', 'juz'];

  @override
  BackupKind get kind => BackupKind.ramadan;
  @override
  bool watches(String key) => key.startsWith('ramadan.log.');
  @override
  Future<Json> export() async {
    final years = <String, Object?>{};
    for (var y = firstYear; y <= lastYear; y++) {
      final raw = await kv.read(RamadanRepository.logKey(y));
      if (raw == null) continue;
      try {
        years['$y'] = jsonDecode(raw);
      } on FormatException {
        // A torn write loses that year only.
      }
    }
    return {'years': years};
  }

  @override
  Future<void> import(Json doc) async {
    for (final e in (asJson(doc['years']) ?? const {}).entries) {
      final y = int.tryParse(e.key);
      if (y == null || asJson(e.value) == null) continue;
      await kv.write(RamadanRepository.logKey(y), jsonEncode(e.value));
    }
  }

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) {
    final ly = asJson(local['years']) ?? const {};
    final ry = asJson(remote['years']) ?? const {};
    final by = asJson(base?['years']);
    Set<String> members(Map<String, dynamic>? years, String y, String t) => asStringSet(asJson(years?[y])?[t]);
    return {
      'years': {
        for (final y in {...ly.keys, ...ry.keys})
          y: {
            for (final t in tracks)
              t: (BackupMerge.set(members(ly, y, t), members(ry, y, t), by == null ? null : members(by, y, t)).map(int.parse).toList()
                ..sort()),
          },
      },
    };
  }
}

/* ------------------------------------------------------------ tasbeeh */

/// The Home misbaha count — last writer wins (it can be reset).
class TasbeehBackup extends BackupAdapter {
  TasbeehBackup(this.kv, {this.adopt});
  final KvStore kv;

  /// Pushes a restored count into the live counter (else it's only written to the store).
  final void Function(int count)? adopt;
  static const key = TasbeehController.key;

  @override
  BackupKind get kind => BackupKind.tasbeeh;
  @override
  bool watches(String k) => k == key;
  @override
  Future<Json> export() async => {'count': int.tryParse(await kv.read(key) ?? '') ?? 0};
  @override
  Future<void> import(Json doc) async {
    final n = (doc['count'] as num?)?.toInt() ?? 0;
    if (adopt != null) {
      adopt!(n);
    } else {
      await kv.write(key, '$n');
    }
  }

  @override
  bool isEmpty(Json doc) => (doc['count'] ?? 0) == 0;

  @override
  Json merge(Json local, Json remote, {Json? base, required DateTime localAt, required DateTime remoteAt}) => {
        'count': BackupMerge.lww<Object?>(
          local['count'],
          remote['count'],
          hasBase: base != null,
          base: base?['count'],
          localAt: localAt,
          remoteAt: remoteAt,
        ),
      };
}
