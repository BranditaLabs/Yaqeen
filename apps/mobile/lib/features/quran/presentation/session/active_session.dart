import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/settings/settings_controller.dart';
import '../../../../core/time/zoned.dart';
import '../../../hifz/domain/hifz_plan.dart';
import '../../data/session_store.dart';
import '../../domain/passage.dart';
import '../../domain/quran_session.dart';
import '../quran_providers.dart';
import 'read_strip.dart';

/// `read` of a [Ref] or a [WidgetRef] (both tear off to this).
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// Today in the user's place (YYYY-MM-DD), as the wird and the khatma count days.
String sessionToday(ProviderRead read) {
  final s = read(settingsProvider);
  return Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, read(clockProvider)()));
}

DateTime _localDay(ProviderRead read) {
  final n = read(clockProvider)().toLocal();
  return DateTime(n.year, n.month, n.day);
}

/// The plan a session of [kind] follows, as a key: editing that plan makes the session stale.
Future<String?> sessionPlanKey(ProviderRead read, QuranSessionKind kind) async {
  switch (kind) {
    case QuranSessionKind.wird:
      return 'wird/${read(settingsProvider).wirdGoalPages}';
    case QuranSessionKind.khatma:
      final k = await read(readingRepositoryProvider).khatma();
      return k == null ? 'khatma/none' : 'khatma/${k.startedOn}/${k.targetDate}/${k.pagesPerDay}';
    case QuranSessionKind.hifz:
    case QuranSessionKind.review:
      final p = await read(hifzRepositoryProvider).load();
      return p == null ? 'hifz/none' : 'hifz/${p.goal.name}/${p.perDay}';
    case QuranSessionKind.free:
      return null;
  }
}

/// Today's portion for a session of [kind]: today's new hifz passage, or a review portion still due
/// ([wanted] is the one the session holds). Null: nothing to compare.
Future<String?> sessionPortion(ProviderRead read, QuranSessionKind kind, {String? wanted}) async {
  if (!kind.guided) return null;
  final plan = await read(hifzRepositoryProvider).load();
  if (plan == null) return '';
  final today = _localDay(read);
  if (kind == QuranSessionKind.review) return plan.due(today).any((p) => p.id == wanted) ? wanted : '';
  final q = await read(quranDataProvider.future);
  // Memorised already today: the session's passage is still today's (its grade may be pending).
  final t = plan.todaysPortion(today) ?? plan.today(q);
  return switch (t) {
    null => '',
    final HifzPortion p => Passage(p.surah, p.from, p.to).toString(),
    final ({int surah, int from, int to}) n => Passage(n.surah, n.from, n.to).toString(),
    _ => '',
  };
}

/// The saved session if it can still be resumed; a stale one (after midnight, a plan edit, a portion
/// no longer today's) is dropped from the device.
Future<QuranSession?> loadValidSession(ProviderRead read) async {
  final store = read(quranSessionStoreProvider);
  final s = await store.load();
  if (s == null) return null;
  final stale = s.finished ||
      s.isStale(
        today: sessionToday(read),
        planKey: await sessionPlanKey(read, s.kind),
        portion: await sessionPortion(read, s.kind, wanted: s.portion),
      );
  if (!stale) return s;
  await store.clear();
  return null;
}

/// The session running in the open reader (null: free reading). Every change is saved at once
/// (writes in order), so a kill resumes where it was.
class ActiveSessionController extends Notifier<QuranSession?> {
  Future<void> _writes = Future.value();

  @override
  QuranSession? build() => null;

  QuranSessionStore get _store => ref.read(quranSessionStoreProvider);

  Future<void> _persist(QuranSession? s) => _writes = _writes.then((_) => s == null ? _store.clear() : _store.save(s));

  /// Starts (or resumes) [s] in the reader.
  Future<void> begin(QuranSession s) {
    state = s;
    return _persist(s);
  }

  /// Applies [change] to the running session (nothing when there is none).
  void update(QuranSession Function(QuranSession s) change) {
    final s = state;
    if (s == null) return;
    final next = change(s);
    if (identical(next, s)) return;
    state = next;
    _persist(next).ignore();
  }

  /// The session is over: gone from the device.
  Future<void> end() {
    state = null;
    return _persist(null);
  }

  /// The reader closed: the session stays saved for «أكمل جلستك».
  void detach() => state = null;

  /// Completes once every pending write has landed (tests, leaving the reader).
  Future<void> flushed() => _writes;
}

final activeSessionProvider = NotifierProvider<ActiveSessionController, QuranSession?>(ActiveSessionController.new);

/// «{done} / {goal}» for the running session: today's wird pages, the khatma's portion, or the
/// guided stages passed. Null for free reading.
final sessionProgressProvider = Provider.autoDispose<({int done, int goal})?>((ref) {
  final s = ref.watch(activeSessionProvider);
  if (s == null) return null;
  final today = sessionToday(ref.read);
  ref.watch(settingsProvider.select((x) => x.placeOrDefault.timezone));
  switch (s.kind) {
    case QuranSessionKind.wird:
      final goal = ref.watch(settingsProvider.select((x) => x.wirdGoalPages));
      final wird = ref.watch(todayWirdProvider).valueOrNull;
      return (done: wird?.date == today ? wird!.count : 0, goal: goal);
    case QuranSessionKind.khatma:
      final k = ref.watch(khatmaProvider).valueOrNull;
      if (k == null || k.finished) return null;
      final read = k.readOn(today);
      return (done: read, goal: k.dailyTarget(today, readToday: read));
    case QuranSessionKind.hifz:
      final i = SessionStage.values.indexOf(s.stage) - SessionStage.listen.index;
      return (done: i.clamp(0, 3), goal: 3);
    case QuranSessionKind.review:
      return (done: s.finished ? 1 : 0, goal: 1);
    case QuranSessionKind.free:
      return null;
  }
});
