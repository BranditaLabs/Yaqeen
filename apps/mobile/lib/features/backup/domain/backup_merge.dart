import 'dart:convert';

/// What the opt-in cloud backup holds (contracts `BACKUP_KINDS`) — one JSON document each.
enum BackupKind {
  quranReading('quran_reading'),
  quranNotes('quran_notes'),
  khatma('khatma'),
  hifz('hifz'),
  azkar('azkar'),
  listen('listen'),
  routine('routine'),
  ramadan('ramadan'),
  tasbeeh('tasbeeh');

  const BackupKind(this.wire);
  final String wire;

  static BackupKind? fromWire(String w) => values.where((k) => k.wire == w).firstOrNull;
}

typedef Json = Map<String, dynamic>;

/// Order-independent JSON text, so two documents compare equal whatever their key order.
String canonicalJson(Object? v) => jsonEncode(_sorted(v));

Object? _sorted(Object? v) => switch (v) {
      final Map<dynamic, dynamic> m => {for (final k in (m.keys.map((e) => '$e').toList()..sort())) k: _sorted(m[k])},
      final List<dynamic> l => [for (final e in l) _sorted(e)],
      _ => v,
    };

bool sameJson(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);

/// Deep copy through JSON, so merged documents never share mutable maps with their inputs.
Json jsonCopy(Json m) => (jsonDecode(jsonEncode(m)) as Map).cast<String, dynamic>();

/// The merge rules of the cloud backup, pure and three-way: `base` is the copy this phone last
/// agreed with the server (null on a phone that never synced), so a deletion on either side is
/// told apart from an item the other side added.
abstract final class BackupMerge {
  /// Keyed items (bookmarks, notes, highlights, favourites, khatma history): the union by key. An
  /// item changed on one side only takes that side; changed on both, the newer `at` wins (this
  /// phone on a tie). An item gone from one side stays gone unless the other side edited it.
  static Map<String, T> keyed<T>(Map<String, T> local, Map<String, T> remote, Map<String, T>? base, {DateTime? Function(T v)? at}) {
    final out = <String, T>{};
    for (final k in {...local.keys, ...remote.keys}) {
      final inL = local.containsKey(k);
      final inR = remote.containsKey(k);
      final inB = base?.containsKey(k) ?? false;
      final b = base?[k];
      if (inL && inR) {
        final l = local[k] as T;
        final r = remote[k] as T;
        final lChanged = !inB || !sameJson(l, b);
        final rChanged = !inB || !sameJson(r, b);
        if (!lChanged) {
          out[k] = r;
        } else if (!rChanged) {
          out[k] = l;
        } else {
          final la = at?.call(l);
          final ra = at?.call(r);
          out[k] = (la != null && ra != null && ra.isAfter(la)) ? r : l;
        }
      } else if (inL) {
        // Not on the server: new here, or deleted there (kept only if edited here since).
        if (!inB || !sameJson(local[k], b)) out[k] = local[k] as T;
      } else if (inR) {
        if (!inB || !sameJson(remote[k], b)) out[k] = remote[k] as T;
      }
    }
    return out;
  }

  /// A set (favourite ids, fasted days): [keyed] over its members.
  static Set<String> set(Set<String> local, Set<String> remote, Set<String>? base) => keyed<bool>(
        {for (final e in local) e: true},
        {for (final e in remote) e: true},
        base == null ? null : {for (final e in base) e: true},
      ).keys.toSet();

  /// Scalar state (last page, khatma plan, routine, reciter, hifz plan): last writer wins. The side
  /// that still equals [base] didn't change, so the other one wins outright; otherwise the later
  /// change wins ([localAt] = when this phone changed it, [remoteAt] = the server's `updatedAt`).
  static T lww<T>(T local, T remote, {required bool hasBase, Object? base, required DateTime localAt, required DateTime remoteAt}) {
    if (sameJson(local, remote)) return local;
    if (hasBase && sameJson(local, base)) return remote;
    if (hasBase && sameJson(remote, base)) return local;
    return remoteAt.isAfter(localAt) ? remote : local;
  }

  /// Per-day counters (`{date: [n, m, …]}` — reading stats): every day of both, each number the max.
  static Map<String, List<int>> dailyMax(Map<String, List<int>> local, Map<String, List<int>> remote, {int? keepDays}) {
    final out = <String, List<int>>{};
    for (final d in {...local.keys, ...remote.keys}) {
      final l = local[d] ?? const <int>[];
      final r = remote[d] ?? const <int>[];
      final n = l.length > r.length ? l.length : r.length;
      out[d] = [for (var i = 0; i < n; i++) _max(i < l.length ? l[i] : 0, i < r.length ? r[i] : 0)];
    }
    if (keepDays != null && out.length > keepDays) {
      final keys = out.keys.toList()..sort();
      for (final k in keys.take(out.length - keepDays)) {
        out.remove(k);
      }
    }
    return out;
  }

  /// A "today" document (`{date, …}` — azkar counts, wird, listening time): the later day wins; on
  /// the same day [sameDay] combines both (counts take the max, ticks the union).
  static Json? day(Json? local, Json? remote, Json Function(Json l, Json r) sameDay) {
    if (local == null) return remote;
    if (remote == null) return local;
    final ld = '${local['date']}';
    final rd = '${remote['date']}';
    if (ld == rd) return sameDay(local, remote);
    return rd.compareTo(ld) > 0 ? remote : local;
  }

  /// Per-key max of two count maps (`{id: n}`).
  static Map<String, int> countsMax(Map<String, int> l, Map<String, int> r) => {
        for (final k in {...l.keys, ...r.keys}) k: _max(l[k] ?? 0, r[k] ?? 0),
      };

  static int _max(int a, int b) => a > b ? a : b;
}

/* ------------------------------------------------------------- JSON helpers */

Json? asJson(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
List<dynamic> asList(Object? v) => v is List ? v : const [];
Set<String> asStringSet(Object? v) => {for (final e in asList(v)) '$e'};
Map<String, int> asCounts(Object? v) => {
      for (final e in (asJson(v) ?? const {}).entries)
        if (e.value is num) e.key: (e.value as num).toInt(),
    };
DateTime? asTime(Object? v) => v is String ? DateTime.tryParse(v) : null;
