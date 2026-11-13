import '../../community/domain/community_models.dart';
import 'avatar.dart';
import 'level.dart';

/// GET /v1/me/profile (contracts `MeProfile`) — the caller only. Cached on the device
/// (`profile.me.v1`) so Home and the Profile tab paint at once, offline included.

/// The opt-in switches (contracts `CommunitySettings`). All off by default.
class CommunitySettings {
  const CommunitySettings({
    this.leagues = false,
    this.leaderboard = false,
    this.leaderboardCountry = false,
    this.banned = false,
    this.attestedAdult = false,
    this.country,
  });
  final bool leagues;
  final bool leaderboard;

  /// Refines [leaderboard] (the country board); never grants the consent alone.
  final bool leaderboardCountry;
  final bool banned;

  /// «عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري» was confirmed (needed for every join, and
  /// before a photo shows publicly).
  final bool attestedAdult;

  /// ISO-2 of the chosen city, null when unknown.
  final String? country;

  static const off = CommunitySettings();

  /// In any competition (what grants the `community` consent, tournaments aside).
  bool get anyOn => leagues || leaderboard;

  factory CommunitySettings.fromJson(Map<String, dynamic> j) => CommunitySettings(
        leagues: j['leagues'] == true,
        leaderboard: j['leaderboard'] == true,
        leaderboardCountry: j['leaderboardCountry'] == true,
        banned: j['banned'] == true,
        attestedAdult: j['attestedAdult'] == true,
        country: j['country'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'leagues': leagues,
        'leaderboard': leaderboard,
        'leaderboardCountry': leaderboardCountry,
        'banned': banned,
        'attestedAdult': attestedAdult,
        'country': country,
      };

  CommunitySettings copyWith({bool? leagues, bool? leaderboard, bool? leaderboardCountry, bool? banned, bool? attestedAdult, String? country}) =>
      CommunitySettings(
        leagues: leagues ?? this.leagues,
        leaderboard: leaderboard ?? this.leaderboard,
        leaderboardCountry: leaderboardCountry ?? this.leaderboardCountry,
        banned: banned ?? this.banned,
        attestedAdult: attestedAdult ?? this.attestedAdult,
        country: country ?? this.country,
      );

  @override
  bool operator ==(Object other) =>
      other is CommunitySettings &&
      other.leagues == leagues &&
      other.leaderboard == leaderboard &&
      other.leaderboardCountry == leaderboardCountry &&
      other.banned == banned &&
      other.attestedAdult == attestedAdult &&
      other.country == country;

  @override
  int get hashCode => Object.hash(leagues, leaderboard, leaderboardCountry, banned, attestedAdult, country);
}

/// contracts `LeagueOutcome`.
enum LeagueOutcome {
  up,
  stay,
  down;

  static LeagueOutcome? fromWire(Object? w) {
    for (final o in values) {
      if (o.name == w) return o;
    }
    return null;
  }
}

/// The week that just closed — shown once in «انتهى الأسبوع».
class LeagueLastWeek {
  const LeagueLastWeek({
    required this.startsOn,
    required this.division,
    required this.newDivision,
    required this.rank,
    required this.outcome,
    required this.badge,
  });
  final String startsOn;
  final int division;
  final int newDivision;
  final int? rank;

  /// Null when the member left that week (no result, no sheet).
  final LeagueOutcome? outcome;
  final Badge? badge;

  factory LeagueLastWeek.fromJson(Map<String, dynamic> j) => LeagueLastWeek(
        startsOn: j['startsOn'] as String,
        division: (j['division'] as num).toInt(),
        newDivision: (j['newDivision'] as num).toInt(),
        rank: (j['rank'] as num?)?.toInt(),
        outcome: LeagueOutcome.fromWire(j['outcome']),
        badge: Badge.tryParse(j['badge']),
      );

  Map<String, dynamic> toJson() => {
        'startsOn': startsOn,
        'division': division,
        'newDivision': newDivision,
        'rank': rank,
        'outcome': outcome?.name,
        'badge': badge?.toJson(),
      };
}

/// The caller's league place (contracts `LeagueSummary`): rank from the snapshot.
class LeagueSummary {
  const LeagueSummary({
    required this.division,
    required this.divisionAr,
    required this.divisionEn,
    required this.rank,
    required this.size,
    required this.lastWeek,
  });
  final int division;
  final String divisionAr;
  final String divisionEn;
  final int? rank;
  final int size;
  final LeagueLastWeek? lastWeek;

  String divisionName(String locale) => locale == 'ar' ? divisionAr : divisionEn;

  factory LeagueSummary.fromJson(Map<String, dynamic> j) => LeagueSummary(
        division: (j['division'] as num).toInt(),
        divisionAr: j['divisionAr'] as String,
        divisionEn: j['divisionEn'] as String,
        rank: (j['rank'] as num?)?.toInt(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        lastWeek: j['lastWeek'] is Map ? LeagueLastWeek.fromJson((j['lastWeek'] as Map).cast<String, dynamic>()) : null,
      );

  Map<String, dynamic> toJson() => {
        'division': division,
        'divisionAr': divisionAr,
        'divisionEn': divisionEn,
        'rank': rank,
        'size': size,
        'lastWeek': lastWeek?.toJson(),
      };
}

class MeProfile {
  const MeProfile({
    required this.displayName,
    this.nameHidden = false,
    this.handle,
    this.avatar = const InitialAvatar(),
    this.photoHidden = false,
    this.photoPublic = false,
    required this.level,
    this.lifetimePoints = 0,
    this.weekPoints = 0,
    this.community = CommunitySettings.off,
    this.league,
    this.recentBadges = const [],
    this.badgesCount = 0,
  });

  /// A guest (or a signed-in user before the first fetch): level 1 at 0 points, nothing public.
  factory MeProfile.guest({String? displayName, AvatarRef avatar = const InitialAvatar()}) =>
      MeProfile(displayName: displayName, avatar: avatar, level: levelFor(0));

  final String? displayName;

  /// Support hid the name: others see «عضو يقين» and renaming is locked.
  final bool nameHidden;
  final String? handle;

  /// The caller's own: a photo carries the authed paths (and this device's copy).
  final AvatarRef avatar;

  /// Support removed the photo: «أخفى فريق الدعم صورتك. اختر صورة من المجموعة.»
  final bool photoHidden;

  /// Whether others can see the photo (visible somewhere + age attested).
  final bool photoPublic;

  /// Live, the caller's own level.
  final CardLevel level;
  final int lifetimePoints;

  /// Live, self only.
  final int weekPoints;
  final CommunitySettings community;
  final LeagueSummary? league;
  final List<Badge> recentBadges;
  final int badgesCount;

  /// The first word of the name — what join sheets and onboarding prefill (never the full name).
  String get firstName => firstNameOf(displayName);

  static String firstNameOf(String? name) {
    final t = (name ?? '').trim();
    if (t.isEmpty) return '';
    return t.split(RegExp(r'\s+')).first;
  }

  /// The initial drawn when there is no avatar picture.
  String initial(String fallback) {
    final t = (displayName ?? '').trim();
    final source = t.isEmpty ? fallback : t;
    return source.isEmpty ? '' : String.fromCharCode(source.runes.first);
  }

  factory MeProfile.fromJson(Map<String, dynamic> j) => MeProfile(
        displayName: j['displayName'] as String?,
        nameHidden: j['nameHidden'] == true,
        handle: j['handle'] as String?,
        avatar: AvatarRef.fromJson(j['avatar']),
        photoHidden: j['photoHidden'] == true,
        photoPublic: j['photoPublic'] == true,
        level: j['level'] is Map
            ? CardLevel.fromJson((j['level'] as Map).cast<String, dynamic>())
            : levelFor((j['lifetimePoints'] as num?)?.toInt() ?? 0),
        lifetimePoints: (j['lifetimePoints'] as num?)?.toInt() ?? 0,
        weekPoints: (j['weekPoints'] as num?)?.toInt() ?? 0,
        community: j['community'] is Map ? CommunitySettings.fromJson((j['community'] as Map).cast<String, dynamic>()) : CommunitySettings.off,
        league: j['league'] is Map ? LeagueSummary.fromJson((j['league'] as Map).cast<String, dynamic>()) : null,
        recentBadges: Badge.listFrom(j['recentBadges']),
        badgesCount: (j['badgesCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'nameHidden': nameHidden,
        'handle': handle,
        'avatar': avatar.toJson(),
        'photoHidden': photoHidden,
        'photoPublic': photoPublic,
        'level': level.toJson(),
        'lifetimePoints': lifetimePoints,
        'weekPoints': weekPoints,
        'community': community.toJson(),
        'league': league?.toJson(),
        'recentBadges': [for (final b in recentBadges) b.toJson()],
        'badgesCount': badgesCount,
      };

  MeProfile copyWith({
    String? displayName,
    bool? nameHidden,
    String? handle,
    AvatarRef? avatar,
    bool? photoHidden,
    bool? photoPublic,
    CardLevel? level,
    int? lifetimePoints,
    int? weekPoints,
    CommunitySettings? community,
    LeagueSummary? league,
    bool clearLeague = false,
    List<Badge>? recentBadges,
    int? badgesCount,
  }) =>
      MeProfile(
        displayName: displayName ?? this.displayName,
        nameHidden: nameHidden ?? this.nameHidden,
        handle: handle ?? this.handle,
        avatar: avatar ?? this.avatar,
        photoHidden: photoHidden ?? this.photoHidden,
        photoPublic: photoPublic ?? this.photoPublic,
        level: level ?? this.level,
        lifetimePoints: lifetimePoints ?? this.lifetimePoints,
        weekPoints: weekPoints ?? this.weekPoints,
        community: community ?? this.community,
        league: clearLeague ? null : (league ?? this.league),
        recentBadges: recentBadges ?? this.recentBadges,
        badgesCount: badgesCount ?? this.badgesCount,
      );
}
