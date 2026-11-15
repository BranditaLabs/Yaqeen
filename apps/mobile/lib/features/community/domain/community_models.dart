import '../../profile/domain/avatar.dart';
import '../../profile/domain/me_profile.dart';

export '../../profile/domain/me_profile.dart' show CommunitySettings, LeagueLastWeek, LeagueOutcome;
export 'result.dart';

/// The opt-in community (APP_SPEC §5.31) — mirrors `packages/contracts/src/community.ts`.
///
/// Privacy: other people appear only as name/@handle, avatar, a public level ring (nightly snapshot)
/// and the period's points from the nightly snapshot — never worship detail, never anything live.
/// The caller's own live points ([LeagueJoined.myLivePoints], [TournamentMe.points]) are self only.

/* --------------------------------------------------------------- divisions */

/// A league division (contracts `DIVISIONS`). Monochrome: «ذهب» never gets gold styling.
class Division {
  const Division({required this.id, required this.key, required this.ar, required this.en});
  final int id;
  final String key;
  final String ar;
  final String en;

  String name(String locale) => locale == 'ar' ? ar : en;
}

const kDivisions = [
  Division(id: 1, key: 'bronze', ar: 'برونز', en: 'Bronze'),
  Division(id: 2, key: 'silver', ar: 'فضة', en: 'Silver'),
  Division(id: 3, key: 'gold', ar: 'ذهب', en: 'Gold'),
  Division(id: 4, key: 'emerald', ar: 'زمرّد', en: 'Emerald'),
  Division(id: 5, key: 'ruby', ar: 'ياقوت', en: 'Ruby'),
  Division(id: 6, key: 'diamond', ar: 'ألماس', en: 'Diamond'),
];

Division divisionById(int id) => kDivisions[(id - 1).clamp(0, kDivisions.length - 1)];

/* ------------------------------------------------------------------ badges */

/// contracts `BADGE_KINDS`. Streak and level badges are derived; the rest are awarded at a period's
/// close. Badges are keepsakes only — never points.
enum BadgeKind {
  streak('streak'),
  level('level'),
  leagueFirst('league_first'),
  leagueTop3('league_top3'),
  leaguePromoted('league_promoted'),
  divisionReached('division_reached'),
  tournamentPodium('tournament_podium'),
  tournamentTop10('tournament_top10'),
  tournamentFinisher('tournament_finisher');

  const BadgeKind(this.wire);
  final String wire;

  static BadgeKind? fromWire(Object? w) {
    for (final k in values) {
      if (k.wire == w) return k;
    }
    return null;
  }

  bool get isLeague => this == leagueFirst || this == leagueTop3 || this == leaguePromoted || this == divisionReached;
  bool get isTournament => this == tournamentPodium || this == tournamentTop10 || this == tournamentFinisher;
}

/// `Badge.meta` — see the contracts doc for which fields each kind carries.
class BadgeMeta {
  const BadgeMeta({
    this.days,
    this.level,
    this.division,
    this.rank,
    this.size,
    this.startsOn,
    this.tournamentId,
    this.titleAr,
    this.titleEn,
    this.labelAr,
    this.labelEn,
  });
  final int? days;
  final int? level;
  final int? division;
  final int? rank;
  final int? size;
  final String? startsOn;
  final String? tournamentId;
  final String? titleAr;
  final String? titleEn;
  final String? labelAr;
  final String? labelEn;

  factory BadgeMeta.fromJson(Map<String, dynamic> j) => BadgeMeta(
        days: (j['days'] as num?)?.toInt(),
        level: (j['level'] as num?)?.toInt(),
        division: (j['division'] as num?)?.toInt(),
        rank: (j['rank'] as num?)?.toInt(),
        size: (j['size'] as num?)?.toInt(),
        startsOn: j['startsOn'] as String?,
        tournamentId: j['tournamentId'] as String?,
        titleAr: j['titleAr'] as String?,
        titleEn: j['titleEn'] as String?,
        labelAr: j['labelAr'] as String?,
        labelEn: j['labelEn'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (days != null) 'days': days,
        if (level != null) 'level': level,
        if (division != null) 'division': division,
        if (rank != null) 'rank': rank,
        if (size != null) 'size': size,
        if (startsOn != null) 'startsOn': startsOn,
        if (tournamentId != null) 'tournamentId': tournamentId,
        if (titleAr != null) 'titleAr': titleAr,
        if (titleEn != null) 'titleEn': titleEn,
        if (labelAr != null) 'labelAr': labelAr,
        if (labelEn != null) 'labelEn': labelEn,
      };

  String? title(String locale) => locale == 'ar' ? (titleAr ?? titleEn) : (titleEn ?? titleAr);
  String? label(String locale) => locale == 'ar' ? (labelAr ?? labelEn) : (labelEn ?? labelAr);
}

class Badge {
  const Badge({required this.kind, required this.refKey, required this.awardedAt, this.meta = const BadgeMeta()});
  final BadgeKind kind;
  final String refKey;
  final DateTime awardedAt;
  final BadgeMeta meta;

  /// Null for a kind this build does not know (a newer server) — callers skip it.
  static Badge? tryParse(Object? json) {
    if (json is! Map) return null;
    final j = json.cast<String, dynamic>();
    final kind = BadgeKind.fromWire(j['kind']);
    final at = DateTime.tryParse(j['awardedAt'] as String? ?? '');
    if (kind == null || at == null) return null;
    return Badge(
      kind: kind,
      refKey: j['refKey'] as String? ?? '',
      awardedAt: at,
      meta: j['meta'] is Map ? BadgeMeta.fromJson((j['meta'] as Map).cast<String, dynamic>()) : const BadgeMeta(),
    );
  }

  static List<Badge> listFrom(Object? json) => [
        for (final e in (json is List ? json : const []))
          if (tryParse(e) case final b?) b,
      ];

  Map<String, dynamic> toJson() => {'kind': kind.wire, 'refKey': refKey, 'awardedAt': awardedAt.toUtc().toIso8601String(), 'meta': meta.toJson()};
}

/* -------------------------------------------------------------- competitor */

/// A public level ring — from the nightly `public_lifetime` snapshot, never live.
class PublicLevelRing {
  const PublicLevelRing({required this.level, required this.progress});
  final int level;
  final double progress;

  factory PublicLevelRing.fromJson(Map<String, dynamic> j) =>
      PublicLevelRing(level: (j['level'] as num).toInt(), progress: (j['progress'] as num).toDouble());

  Map<String, dynamic> toJson() => {'level': level, 'progress': progress};
}

/// One row in a public list.
class PublicCompetitor {
  const PublicCompetitor({
    required this.handle,
    required this.name,
    required this.avatar,
    required this.level,
    required this.points,
    required this.rank,
    required this.me,
  });
  final String handle;

  /// Null when support hid the name (render «عضو يقين»).
  final String? name;
  final AvatarRef avatar;
  final PublicLevelRing level;

  /// Snapshot period points; null on the level board.
  final int? points;

  /// Shared on ties (1, 1, 3); null before the first snapshot or with 0 points (render «—»).
  final int? rank;
  final bool me;

  factory PublicCompetitor.fromJson(Map<String, dynamic> j) => PublicCompetitor(
        handle: j['handle'] as String,
        name: j['name'] as String?,
        avatar: AvatarRef.fromJson(j['avatar']),
        level: PublicLevelRing.fromJson((j['level'] as Map).cast<String, dynamic>()),
        points: (j['points'] as num?)?.toInt(),
        rank: (j['rank'] as num?)?.toInt(),
        me: j['me'] == true,
      );

  static List<PublicCompetitor> listFrom(Object? json) => [
        for (final e in (json is List ? json : const [])) PublicCompetitor.fromJson((e as Map).cast<String, dynamic>()),
      ];

  Map<String, dynamic> toJson() =>
      {'handle': handle, 'name': name, 'avatar': avatar.toJson(), 'level': level.toJson(), 'points': points, 'rank': rank, 'me': me};
}

/* ------------------------------------------------------------------ league */

/// GET /v1/leagues/current.
sealed class LeagueCurrent {
  const LeagueCurrent();

  factory LeagueCurrent.fromJson(Map<String, dynamic> j) => switch (j['state']) {
        'joined' => LeagueJoined.fromJson(j),
        'closing' => const LeagueClosing(),
        _ => const LeagueOff(),
      };

  Map<String, dynamic> toJson();
}

/// Not opted in.
final class LeagueOff extends LeagueCurrent {
  const LeagueOff();
  @override
  Map<String, dynamic> toJson() => const {'state': 'off'};
}

/// A past week is still being closed: «نحسب نتائج الأسبوع… عُد بعد قليل».
final class LeagueClosing extends LeagueCurrent {
  const LeagueClosing();
  @override
  Map<String, dynamic> toJson() => const {'state': 'closing'};
}

final class LeagueJoined extends LeagueCurrent {
  const LeagueJoined({
    required this.startsOn,
    required this.endsAt,
    required this.snapshotDay,
    required this.division,
    required this.divisionAr,
    required this.divisionEn,
    required this.nextAr,
    required this.nextEn,
    required this.prevAr,
    required this.prevEn,
    required this.size,
    required this.promoteZone,
    required this.demoteZone,
    required this.myLivePoints,
    required this.rows,
    required this.lastWeek,
  });
  final String startsOn;
  final DateTime endsAt;

  /// The Cairo day of the snapshot the rows come from; null before the first one.
  final String? snapshotDay;
  final int division;
  final String divisionAr;
  final String divisionEn;
  final String? nextAr;
  final String? nextEn;
  final String? prevAr;
  final String? prevEn;
  final int size;
  final int promoteZone;
  final int demoteZone;

  /// Live, self only — the stage caption, never a row.
  final int myLivePoints;
  final List<PublicCompetitor> rows;
  final LeagueLastWeek? lastWeek;

  String divisionName(String locale) => locale == 'ar' ? divisionAr : divisionEn;
  String? nextName(String locale) => locale == 'ar' ? nextAr : nextEn;
  String? prevName(String locale) => locale == 'ar' ? prevAr : prevEn;

  factory LeagueJoined.fromJson(Map<String, dynamic> j) => LeagueJoined(
        startsOn: j['startsOn'] as String,
        endsAt: DateTime.parse(j['endsAt'] as String),
        snapshotDay: j['snapshotDay'] as String?,
        division: (j['division'] as num).toInt(),
        divisionAr: j['divisionAr'] as String,
        divisionEn: j['divisionEn'] as String,
        nextAr: j['nextAr'] as String?,
        nextEn: j['nextEn'] as String?,
        prevAr: j['prevAr'] as String?,
        prevEn: j['prevEn'] as String?,
        size: (j['size'] as num).toInt(),
        promoteZone: (j['promoteZone'] as num).toInt(),
        demoteZone: (j['demoteZone'] as num).toInt(),
        myLivePoints: (j['myLivePoints'] as num).toInt(),
        rows: PublicCompetitor.listFrom(j['rows']),
        lastWeek: j['lastWeek'] is Map ? LeagueLastWeek.fromJson((j['lastWeek'] as Map).cast<String, dynamic>()) : null,
      );

  @override
  Map<String, dynamic> toJson() => {
        'state': 'joined',
        'startsOn': startsOn,
        'endsAt': endsAt.toUtc().toIso8601String(),
        'snapshotDay': snapshotDay,
        'division': division,
        'divisionAr': divisionAr,
        'divisionEn': divisionEn,
        'nextAr': nextAr,
        'nextEn': nextEn,
        'prevAr': prevAr,
        'prevEn': prevEn,
        'size': size,
        'promoteZone': promoteZone,
        'demoteZone': demoteZone,
        'myLivePoints': myLivePoints,
        'rows': [for (final r in rows) r.toJson()],
        'lastWeek': lastWeek?.toJson(),
      };
}

/// GET /v1/leagues/history (last 12 weeks).
class LeagueHistoryItem {
  const LeagueHistoryItem({
    required this.startsOn,
    required this.division,
    required this.rank,
    required this.size,
    required this.points,
    required this.outcome,
  });
  final String startsOn;
  final int division;
  final int? rank;
  final int size;
  final int? points;
  final LeagueOutcome? outcome;

  factory LeagueHistoryItem.fromJson(Map<String, dynamic> j) => LeagueHistoryItem(
        startsOn: j['startsOn'] as String,
        division: (j['division'] as num).toInt(),
        rank: (j['rank'] as num?)?.toInt(),
        size: (j['size'] as num).toInt(),
        points: (j['points'] as num?)?.toInt(),
        outcome: LeagueOutcome.fromWire(j['outcome']),
      );

  Map<String, dynamic> toJson() =>
      {'startsOn': startsOn, 'division': division, 'rank': rank, 'size': size, 'points': points, 'outcome': outcome?.name};
}

/* ------------------------------------------------------------- tournaments */

enum TournamentPhase {
  upcoming,
  live,
  ended;

  static TournamentPhase fromWire(Object? w) => values.firstWhere((p) => p.name == w, orElse: () => TournamentPhase.ended);
}

/// The caller's own place in a tournament: rank from the snapshot (or final); points live, self only.
class TournamentMe {
  const TournamentMe({required this.rank, required this.points});
  final int? rank;
  final int points;
}

class Tournament {
  const Tournament({
    required this.id,
    required this.slug,
    required this.titleAr,
    required this.titleEn,
    required this.bodyAr,
    required this.bodyEn,
    required this.startsAt,
    required this.endsAt,
    required this.joinUntil,
    required this.phase,
    required this.closed,
    required this.joined,
    required this.participants,
    required this.badgeAr,
    required this.badgeEn,
    required this.me,
  });
  final String id;
  final String slug;
  final String titleAr;
  final String titleEn;
  final String bodyAr;
  final String bodyEn;
  final DateTime startsAt;

  /// Exclusive (a Cairo midnight).
  final DateTime endsAt;

  /// Exclusive (a Cairo midnight).
  final DateTime joinUntil;
  final TournamentPhase phase;
  final bool closed;
  final bool joined;
  final int participants;
  final String badgeAr;
  final String badgeEn;
  final TournamentMe? me;

  String title(String locale) => locale == 'ar' ? titleAr : titleEn;
  String body(String locale) => locale == 'ar' ? bodyAr : bodyEn;
  String badge(String locale) => locale == 'ar' ? badgeAr : badgeEn;

  /// «انتهى الانضمام» after [joinUntil].
  bool joinOpen(DateTime now) => !closed && phase != TournamentPhase.ended && now.isBefore(joinUntil);

  factory Tournament.fromJson(Map<String, dynamic> j) {
    final me = j['me'] as Map?;
    return Tournament(
      id: j['id'] as String,
      slug: j['slug'] as String,
      titleAr: j['titleAr'] as String,
      titleEn: j['titleEn'] as String,
      bodyAr: j['bodyAr'] as String? ?? '',
      bodyEn: j['bodyEn'] as String? ?? '',
      startsAt: DateTime.parse(j['startsAt'] as String),
      endsAt: DateTime.parse(j['endsAt'] as String),
      joinUntil: DateTime.parse(j['joinUntil'] as String),
      phase: TournamentPhase.fromWire(j['phase']),
      closed: j['closed'] == true,
      joined: j['joined'] == true,
      participants: (j['participants'] as num?)?.toInt() ?? 0,
      badgeAr: j['badgeAr'] as String? ?? '',
      badgeEn: j['badgeEn'] as String? ?? '',
      me: me == null ? null : TournamentMe(rank: (me['rank'] as num?)?.toInt(), points: (me['points'] as num?)?.toInt() ?? 0),
    );
  }

  static List<Tournament> listFrom(Object? json) => [
        for (final e in (json is List ? json : const [])) Tournament.fromJson((e as Map).cast<String, dynamic>()),
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'titleAr': titleAr,
        'titleEn': titleEn,
        'bodyAr': bodyAr,
        'bodyEn': bodyEn,
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt.toUtc().toIso8601String(),
        'joinUntil': joinUntil.toUtc().toIso8601String(),
        'phase': phase.name,
        'closed': closed,
        'joined': joined,
        'participants': participants,
        'badgeAr': badgeAr,
        'badgeEn': badgeEn,
        'me': me == null ? null : {'rank': me!.rank, 'points': me!.points},
      };
}

/// GET /v1/tournaments/:id/standings — pages of 100 from the snapshot.
class TournamentStandings {
  const TournamentStandings({required this.total, required this.snapshotDay, required this.rows, required this.me, required this.nextCursor});
  final int total;
  final String? snapshotDay;
  final List<PublicCompetitor> rows;
  final PublicCompetitor? me;
  final String? nextCursor;

  factory TournamentStandings.fromJson(Map<String, dynamic> j) => TournamentStandings(
        total: (j['total'] as num).toInt(),
        snapshotDay: j['snapshotDay'] as String?,
        rows: PublicCompetitor.listFrom(j['rows']),
        me: j['me'] is Map ? PublicCompetitor.fromJson((j['me'] as Map).cast<String, dynamic>()) : null,
        nextCursor: j['nextCursor'] as String?,
      );
}

/* ------------------------------------------------------------- leaderboard */

enum LeaderboardScope { global, country }

/// GET /v1/leaderboard?scope= — the level board (rings only, no points), top 100 + me.
class LeaderboardView {
  const LeaderboardView({
    required this.scope,
    required this.country,
    required this.snapshotDay,
    required this.joined,
    required this.countryJoined,
    required this.rows,
    required this.me,
  });
  final LeaderboardScope scope;
  final String? country;
  final String? snapshotDay;
  final bool joined;
  final bool countryJoined;
  final List<PublicCompetitor> rows;
  final PublicCompetitor? me;

  factory LeaderboardView.fromJson(Map<String, dynamic> j) => LeaderboardView(
        scope: j['scope'] == 'country' ? LeaderboardScope.country : LeaderboardScope.global,
        country: j['country'] as String?,
        snapshotDay: j['snapshotDay'] as String?,
        joined: j['joined'] == true,
        countryJoined: j['countryJoined'] == true,
        rows: PublicCompetitor.listFrom(j['rows']),
        me: j['me'] is Map ? PublicCompetitor.fromJson((j['me'] as Map).cast<String, dynamic>()) : null,
      );

  Map<String, dynamic> toJson() => {
        'scope': scope.name,
        'country': country,
        'snapshotDay': snapshotDay,
        'joined': joined,
        'countryJoined': countryJoined,
        'rows': [for (final r in rows) r.toJson()],
        'me': me?.toJson(),
      };
}

/* ------------------------------------------------------------------ safety */

class BlockedUser {
  const BlockedUser({required this.handle, required this.name, required this.avatar});
  final String handle;
  final String? name;
  final AvatarRef avatar;

  factory BlockedUser.fromJson(Map<String, dynamic> j) =>
      BlockedUser(handle: j['handle'] as String, name: j['name'] as String?, avatar: AvatarRef.fromJson(j['avatar']));

  static List<BlockedUser> listFrom(Object? json) => [
        for (final e in (json is List ? json : const [])) BlockedUser.fromJson((e as Map).cast<String, dynamic>()),
      ];
}

/// contracts `REPORT_REASONS`.
enum ReportReason { name, photo, other }

/* ------------------------------------------------------------- join/leave */

enum CommunitySource { onboarding, settings }

/// PUT /v1/me/community. Turning anything on is a direct online call; [attestAdult] must be true
/// the first time (until `CommunitySettings.attestedAdult`).
class CommunityUpdate {
  const CommunityUpdate({
    this.leagues,
    this.leaderboard,
    this.leaderboardCountry,
    this.displayName,
    this.attestAdult = false,
    this.source = CommunitySource.settings,
  });
  final bool? leagues;
  final bool? leaderboard;
  final bool? leaderboardCountry;
  final String? displayName;
  final bool attestAdult;
  final CommunitySource source;

  /// Whether this turns something on (a join) rather than only off (a leave).
  bool get joins => leagues == true || leaderboard == true || leaderboardCountry == true;

  Map<String, dynamic> toJson() => {
        if (leagues != null) 'leagues': leagues,
        if (leaderboard != null) 'leaderboard': leaderboard,
        if (leaderboardCountry != null) 'leaderboardCountry': leaderboardCountry,
        if (displayName != null) 'displayName': displayName!.trim(),
        if (attestAdult) 'attestAdult': true,
        'source': source.name,
      };
}

/// One value per contracts `COMMUNITY_ERROR_CODES`, plus [offline] and [unknown].
enum CommunityFailure {
  accountRequired('account_required'),
  communityBanned('community_banned'),
  nameRequired('name_required'),
  nameLocked('name_locked'),
  invalidName('invalid_name'),
  featureOff('feature_off'),
  attestationRequired('attestation_required'),
  useCommunitySettings('use_community_settings'),
  tournamentNotOpen('tournament_not_open'),
  ackRequired('ack_required'),
  countryUnknown('country_unknown'),
  countryTooSmall('country_too_small'),
  photoLocked('photo_locked'),
  photoTooLarge('photo_too_large'),
  photoType('photo_type'),
  photoUnreadable('photo_unreadable'),
  rateLimited('rate_limited'),
  notFound('not_found'),

  /// No connection: «تحتاج اتصالاً للانضمام».
  offline('offline'),

  /// Anything else (a 5xx, an unknown code).
  unknown('unknown');

  const CommunityFailure(this.code);
  final String code;

  /// The values that mirror server error codes (everything but [offline] and [unknown]).
  static Iterable<CommunityFailure> get serverCodes => values.where((f) => f != offline && f != unknown);

  static CommunityFailure fromCode(String code) {
    for (final f in serverCodes) {
      if (f.code == code) return f;
    }
    return unknown;
  }
}
