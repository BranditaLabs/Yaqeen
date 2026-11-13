import 'passage.dart';
import 'quran_data.dart';

/// What a guided «جلسة» in the reader is for (spec §5.11 «صفحة واحدة»): today's wird, the khatma's
/// portion, today's new hifz passage, a due review, or a passage chosen freely («احفظ من هنا»).
enum QuranSessionKind {
  wird,
  khatma,
  hifz,
  review,
  free;

  /// `?session=` in `/quran/read/:page` (unknown → null).
  static QuranSessionKind? tryParse(String? raw) => values.asNameMap()[raw];

  /// Guided hifz sessions: listen ×3 → repeat ×10 → test, the dock pinned.
  bool get guided => this == hifz || this == review;
}

/// Where a session stands. Reading sessions (wird, khatma, free) stay at [reading] until their goal
/// is met; guided ones walk «استماع ×3» → «تكرار ×10» → «اختبار». [done] ends any of them.
enum SessionStage {
  reading,
  listen,
  repeat,
  test,
  done;

  /// The hifz plan's step for this stage («استمع · كرّر · اختبر نفسك»), or null.
  int? get hifzStep => switch (this) {
        listen => 0,
        repeat => 1,
        test => 2,
        _ => null,
      };
}

/// One session, saved on every change so a kill resumes it («أكمل جلستك · ص {page}»). Device-only:
/// the passage, reveals and the raw recitation transcript never leave the phone (KV
/// `quran.session.v1`); only a confirmed grade reaches the hifz plan.
class QuranSession {
  const QuranSession({
    required this.id,
    required this.kind,
    required this.passage,
    required this.startedAt,
    required this.day,
    this.mode = QuranMode.read,
    this.stage = SessionStage.reading,
    this.round = 0,
    this.reveals = const {},
    this.results = '',
    this.page,
    this.planKey,
    this.portion,
  });

  /// Starts [kind] on [passage]: hifz at «استماع ×3», a review straight at «اختبار».
  factory QuranSession.start(
    QuranSessionKind kind,
    Passage passage, {
    required DateTime now,
    required String day,
    QuranMode mode = QuranMode.read,
    int? page,
    String? planKey,
    String? portion,
  }) =>
      QuranSession(
        id: '${kind.name}-${now.microsecondsSinceEpoch}',
        kind: kind,
        passage: passage,
        startedAt: now,
        day: day,
        mode: mode,
        stage: switch (kind) {
          QuranSessionKind.hifz => SessionStage.listen,
          QuranSessionKind.review => SessionStage.test,
          _ => SessionStage.reading,
        },
        page: page,
        planKey: planKey,
        portion: portion,
      );

  final String id;
  final QuranSessionKind kind;
  final Passage passage;
  final DateTime startedAt;

  /// The local day (YYYY-MM-DD) the session belongs to: after midnight it is stale.
  final String day;
  final QuranMode mode;
  final SessionStage stage;

  /// Listening rounds heard, or repetitions made, in the current stage.
  final int round;

  /// Ayat revealed during the test (they lower the suggested grade).
  final Set<AyahRef> reveals;

  /// The recitation heard during the test, raw — kept only to restore the attempt after a kill.
  final String results;

  /// The page last on screen.
  final int? page;

  /// The plan the session was started from (goal, pace…): editing the plan makes it stale.
  final String? planKey;

  /// The portion it covers (a hifz portion id, today's khatma portion): no longer today's → stale.
  final String? portion;

  bool get finished => stage == SessionStage.done;

  /// Stages of a guided session in order.
  static const guidedStages = [SessionStage.listen, SessionStage.repeat, SessionStage.test];

  /// The next stage: listen → repeat → test → done; a reading session goes straight to done.
  QuranSession advance() => _copy(
        stage: switch (stage) {
          SessionStage.listen => SessionStage.repeat,
          SessionStage.repeat => SessionStage.test,
          _ => SessionStage.done,
        },
        round: 0,
        reveals: const {},
        results: '',
      );

  /// «تخطَّ إلى التكرار» (no recitation on the device).
  QuranSession skipToRepeat() => stage == SessionStage.listen ? advance() : this;

  QuranSession withRound(int round) => _copy(round: round);
  QuranSession withMode(QuranMode mode) => _copy(mode: mode);
  QuranSession withPage(int page) => _copy(page: page);
  QuranSession withPassage(Passage p) => p == passage ? this : _copy(passage: p, reveals: const {}, results: '');
  QuranSession reveal(Iterable<AyahRef> refs) => _copy(reveals: {...reveals, ...refs.where(passage.contains)});
  QuranSession withResults(String heard) => _copy(results: heard);
  QuranSession finish() => _copy(stage: SessionStage.done);

  /// Dropped (never resumed) after midnight, when its plan was edited, or when the portion it covers
  /// is no longer today's ([portion] is today's expected one; null skips that check).
  bool isStale({required String today, String? planKey, String? portion}) {
    if (day != today) return true;
    if (this.planKey != null && planKey != this.planKey) return true;
    if (this.portion != null && portion != null && portion != this.portion) return true;
    return false;
  }

  QuranSession _copy({
    QuranMode? mode,
    SessionStage? stage,
    int? round,
    Set<AyahRef>? reveals,
    String? results,
    int? page,
    Passage? passage,
  }) =>
      QuranSession(
        id: id,
        kind: kind,
        passage: passage ?? this.passage,
        startedAt: startedAt,
        day: day,
        mode: mode ?? this.mode,
        stage: stage ?? this.stage,
        round: round ?? this.round,
        reveals: reveals ?? this.reveals,
        results: results ?? this.results,
        page: page ?? this.page,
        planKey: planKey,
        portion: portion,
      );

  static const version = 1;

  Map<String, dynamic> toJson() => {
        'v': version,
        'id': id,
        'kind': kind.name,
        'passage': passage.toJson(),
        'startedAt': startedAt.toIso8601String(),
        'day': day,
        'mode': mode.name,
        'stage': stage.name,
        'round': round,
        if (reveals.isNotEmpty) 'reveals': [for (final r in reveals) '${r.surah}:${r.ayah}'],
        if (results.isNotEmpty) 'results': results,
        if (page != null) 'page': page,
        if (planKey != null) 'planKey': planKey,
        if (portion != null) 'portion': portion,
      };

  /// Anything unreadable (another version, a damaged value) is null: the session is simply gone.
  static QuranSession? tryParse(Object? j) {
    if (j is! Map || j['v'] != version) return null;
    final kind = QuranSessionKind.tryParse(j['kind'] as String?);
    final passage = Passage.tryParse(j['passage']);
    final startedAt = DateTime.tryParse('${j['startedAt']}');
    final stage = SessionStage.values.asNameMap()[j['stage']];
    if (kind == null || passage == null || startedAt == null || stage == null || j['id'] is! String || j['day'] is! String) {
      return null;
    }
    final page = j['page'];
    return QuranSession(
      id: j['id'] as String,
      kind: kind,
      passage: passage,
      startedAt: startedAt,
      day: j['day'] as String,
      mode: QuranMode.parse(j['mode'] as String?),
      stage: stage,
      round: (j['round'] as int?) ?? 0,
      reveals: {
        for (final r in (j['reveals'] as List?) ?? const [])
          if (parseAyahRef('$r') case final AyahRef a) a,
      },
      results: (j['results'] as String?) ?? '',
      page: page is int && page >= 1 && page <= QuranData.pageCount ? page : null,
      planKey: j['planKey'] as String?,
      portion: j['portion'] as String?,
    );
  }
}
