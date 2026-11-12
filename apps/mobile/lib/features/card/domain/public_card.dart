import 'dart:convert';

/// Public profile card («بطاقة يقين») — mirrors `packages/contracts/src/profile.ts`.
///
/// Opt-in and privacy-first: unpublished until the user says so, only the switched-on fields are
/// public, and it never carries worship detail (no prayers, azkar, pages or tasks).

final profileHandle = RegExp(r'^[a-z][a-z0-9_.]{2,23}$');

const reservedHandles = {
  'admin', 'api', 'app', 'apps', 'assets', 'help', 'support', 'yaqeen', 'yaqin', 'yaqinbrand', 'official', 'store', 'shop', //
  'login', 'signup', 'settings', 'profile', 'me', 'u', 'www', 'about', 'privacy', 'terms', 'null', 'undefined',
};

enum SocialKind { instagram, x, tiktok, facebook, youtube, snapchat, linkedin, whatsapp, website }

enum CardLook { sky, gold, night }

class SocialLink {
  const SocialLink(this.kind, this.value);
  final SocialKind kind;
  final String value;

  factory SocialLink.fromJson(Map<String, dynamic> j) => SocialLink(SocialKind.values.byName(j['kind'] as String), j['value'] as String);
  Map<String, dynamic> toJson() => {'kind': kind.name, 'value': value.trim()};

  /// The https URL it opens, or null when the value can't make a safe link (mirrors `socialUrl`).
  String? get url {
    final v = value.trim();
    if (RegExp(r'^https://', caseSensitive: false).hasMatch(v)) return v;
    if (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(v)) return null;
    final user = v.replaceFirst(RegExp('^@'), '').replaceAll(RegExp(r'[^\w.\-]'), '');
    return switch (kind) {
      SocialKind.instagram => user.isEmpty ? null : 'https://instagram.com/$user',
      SocialKind.x => user.isEmpty ? null : 'https://x.com/$user',
      SocialKind.tiktok => user.isEmpty ? null : 'https://www.tiktok.com/@$user',
      SocialKind.facebook => user.isEmpty ? null : 'https://facebook.com/$user',
      SocialKind.youtube => user.isEmpty ? null : 'https://www.youtube.com/@$user',
      SocialKind.snapchat => user.isEmpty ? null : 'https://www.snapchat.com/add/$user',
      SocialKind.linkedin => user.isEmpty ? null : 'https://www.linkedin.com/in/$user',
      SocialKind.whatsapp => () {
          final phone = v.replaceAll(RegExp(r'[^\d]'), '');
          return phone.length >= 8 ? 'https://wa.me/$phone' : null;
        }(),
      SocialKind.website => RegExp(r'^[\w.-]+\.[a-z]{2,}(/.*)?$', caseSensitive: false).hasMatch(v) ? 'https://$v' : null,
    };
  }

  @override
  bool operator ==(Object other) => other is SocialLink && other.kind == kind && other.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
}

class CardVisibility {
  const CardVisibility({
    this.level = true,
    this.streak = false,
    this.challengeDay = false,
    this.badges = false,
    this.memberSince = false,
    this.timeline = false,
  });
  final bool level;
  final bool streak;
  final bool challengeDay;
  final bool badges;
  final bool memberSince;

  /// The journey milestones (joined, challenge days, levels, badges) — never worship detail.
  final bool timeline;

  factory CardVisibility.fromJson(Map<String, dynamic> j) => CardVisibility(
        level: j['level'] as bool? ?? true,
        streak: j['streak'] as bool? ?? false,
        challengeDay: j['challengeDay'] as bool? ?? false,
        badges: j['badges'] as bool? ?? false,
        memberSince: j['memberSince'] as bool? ?? false,
        timeline: j['timeline'] as bool? ?? false,
      );
  Map<String, dynamic> toJson() => {
        'level': level,
        'streak': streak,
        'challengeDay': challengeDay,
        'badges': badges,
        'memberSince': memberSince,
        'timeline': timeline,
      };

  CardVisibility copyWith({bool? level, bool? streak, bool? challengeDay, bool? badges, bool? memberSince, bool? timeline}) =>
      CardVisibility(
        level: level ?? this.level,
        streak: streak ?? this.streak,
        challengeDay: challengeDay ?? this.challengeDay,
        badges: badges ?? this.badges,
        memberSince: memberSince ?? this.memberSince,
        timeline: timeline ?? this.timeline,
      );

  @override
  bool operator ==(Object other) =>
      other is CardVisibility &&
      other.level == level &&
      other.streak == streak &&
      other.challengeDay == challengeDay &&
      other.badges == badges &&
      other.memberSince == memberSince &&
      other.timeline == timeline;
  @override
  int get hashCode => Object.hash(level, streak, challengeDay, badges, memberSince, timeline);
}

/// The owner's card (GET/PUT /v1/me/public-profile). [url] and [views] come from the server.
class PublicCard {
  const PublicCard({
    required this.published,
    required this.handle,
    required this.displayName,
    this.bio = '',
    this.links = const [],
    this.show = const CardVisibility(),
    this.theme = CardLook.sky,
    this.url = '',
    this.views = 0,
    this.moderated = false,
  });

  final bool published;
  final String handle;
  final String displayName;
  final String bio;
  final List<SocialLink> links;
  final CardVisibility show;
  final CardLook theme;
  final String url;
  final int views;

  /// Hidden by Yaqeen support; can't be published until support restores it.
  final bool moderated;

  static const maxLinks = 8;
  static const maxBio = 160;
  static const maxName = 40;

  factory PublicCard.fromJson(Map<String, dynamic> j) => PublicCard(
        published: j['published'] as bool,
        handle: j['handle'] as String,
        displayName: j['displayName'] as String,
        bio: j['bio'] as String? ?? '',
        links: [for (final l in (j['links'] as List? ?? const [])) SocialLink.fromJson((l as Map).cast<String, dynamic>())],
        show: CardVisibility.fromJson(((j['show'] as Map?) ?? const {}).cast<String, dynamic>()),
        theme: CardLook.values.asNameMap()[j['theme']] ?? CardLook.sky,
        url: j['url'] as String? ?? '',
        views: (j['views'] as num?)?.toInt() ?? 0,
        moderated: j['moderated'] == true,
      );

  /// The PUT body (server fields left out).
  Map<String, dynamic> toUpdateJson() => {
        'published': published,
        'handle': handle.trim().toLowerCase(),
        'displayName': displayName.trim(),
        'bio': bio.trim(),
        'links': [for (final l in links) l.toJson()],
        'show': show.toJson(),
        'theme': theme.name,
      };

  PublicCard copyWith({
    bool? published,
    String? handle,
    String? displayName,
    String? bio,
    List<SocialLink>? links,
    CardVisibility? show,
    CardLook? theme,
    String? url,
    int? views,
  }) =>
      PublicCard(
        published: published ?? this.published,
        handle: handle ?? this.handle,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        links: links ?? this.links,
        show: show ?? this.show,
        theme: theme ?? this.theme,
        url: url ?? this.url,
        views: views ?? this.views,
        moderated: moderated,
      );

  /// What the server would accept; null when valid.
  HandleProblem? get handleProblem => handleProblemOf(handle);

  /// Same content as [other] for the PUT (ignores url and views).
  bool sameAs(PublicCard other) => jsonEncode(toUpdateJson()) == jsonEncode(other.toUpdateJson());
}

enum HandleProblem { format, reserved, taken }

HandleProblem? handleProblemOf(String raw) {
  final h = raw.trim().toLowerCase();
  if (!profileHandle.hasMatch(h)) return HandleProblem.format;
  if (reservedHandles.contains(h)) return HandleProblem.reserved;
  return null;
}

/* ------------------------------------------------------------------ levels */

class CardLevel {
  const CardLevel({required this.level, required this.nameAr, required this.nameEn, required this.progress, this.nextAt});
  final int level;
  final String nameAr;
  final String nameEn;
  final double progress;
  final int? nextAt;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;
}

/// Mirrors `LEVELS` / `levelFor` in contracts: levels from lifetime points.
const cardLevels = [
  (0, 'بداية الطريق', 'Setting out'),
  (500, 'على الطريق', 'On the path'),
  (2000, 'مواظب', 'Steadfast'),
  (5000, 'ثابت', 'Unwavering'),
  (12000, 'راسخ', 'Rooted'),
  (25000, 'منارة', 'Beacon'),
];

CardLevel levelFor(int lifetimePoints) {
  final pts = lifetimePoints < 0 ? 0 : lifetimePoints;
  var i = 0;
  while (i + 1 < cardLevels.length && pts >= cardLevels[i + 1].$1) {
    i++;
  }
  final cur = cardLevels[i];
  final next = i + 1 < cardLevels.length ? cardLevels[i + 1] : null;
  return CardLevel(
    level: i + 1,
    nameAr: cur.$2,
    nameEn: cur.$3,
    progress: next == null ? 1 : (pts - cur.$1) / (next.$1 - cur.$1),
    nextAt: next?.$1,
  );
}

/// The public view (GET /v1/public/profiles/:handle) — what a scanner sees.
class CardView {
  const CardView({
    required this.level,
    required this.streak,
    required this.challengeDay,
    required this.challengeOf,
    required this.badges,
    this.timeline,
  });
  final CardLevel? level;
  final int? streak;
  final int? challengeDay;
  final int? challengeOf;
  final List<int>? badges;
  final List<JourneyEvent>? timeline;

  factory CardView.fromJson(Map<String, dynamic> j) {
    final l = j['level'] as Map?;
    final c = j['challengeDay'] as Map?;
    return CardView(
      level: l == null
          ? null
          : CardLevel(
              level: (l['level'] as num).toInt(),
              nameAr: l['nameAr'] as String,
              nameEn: l['nameEn'] as String,
              progress: (l['progress'] as num).toDouble(),
            ),
      streak: (j['streak'] as num?)?.toInt(),
      challengeDay: (c?['day'] as num?)?.toInt(),
      challengeOf: (c?['of'] as num?)?.toInt(),
      badges: (j['badges'] as List?)?.map((e) => (e as num).toInt()).toList(),
      timeline: (j['timeline'] as List?) == null
          ? null
          : [
              for (final e in j['timeline'] as List)
                if (JourneyEvent.tryParse((e as Map).cast<String, dynamic>()) case final ev?) ev,
            ],
    );
  }
}

/* ---------------------------------------------------------------- journey */

enum JourneyKind { joined, challengeStart, challengeDay, level, badge }

/// A dated milestone (contracts `JourneyEvent`). [value]: level number, challenge day or badge days.
class JourneyEvent {
  const JourneyEvent(this.kind, this.date, [this.value]);
  final JourneyKind kind;
  final DateTime date;
  final int? value;

  static const _kinds = {
    'joined': JourneyKind.joined,
    'challenge_start': JourneyKind.challengeStart,
    'challenge_day': JourneyKind.challengeDay,
    'level': JourneyKind.level,
    'badge': JourneyKind.badge,
  };

  /// Unknown kinds (a newer server) are skipped by the caller.
  static JourneyEvent? tryParse(Map<String, dynamic> j) {
    final kind = _kinds[j['kind']];
    final date = DateTime.tryParse(j['date'] as String? ?? '');
    if (kind == null || date == null) return null;
    return JourneyEvent(kind, date, (j['value'] as num?)?.toInt());
  }

  /// The big moments get the gold mark.
  bool get golden => kind == JourneyKind.level || kind == JourneyKind.badge;
}

/// GET /v1/me/journey — the owner's private journey for the Profile tab.
class MyJourney {
  const MyJourney({
    required this.lifetimePoints,
    required this.level,
    required this.streak,
    required this.challengeDay,
    required this.challengeOf,
    required this.events,
  });
  final int lifetimePoints;
  final CardLevel level;
  final int streak;
  final int? challengeDay;
  final int challengeOf;
  final List<JourneyEvent> events;

  factory MyJourney.fromJson(Map<String, dynamic> j) {
    final l = (j['level'] as Map).cast<String, dynamic>();
    return MyJourney(
      lifetimePoints: (j['lifetimePoints'] as num).toInt(),
      level: CardLevel(
        level: (l['level'] as num).toInt(),
        nameAr: l['nameAr'] as String,
        nameEn: l['nameEn'] as String,
        progress: (l['progress'] as num).toDouble(),
        nextAt: (l['nextAt'] as num?)?.toInt(),
      ),
      streak: (j['streak'] as num?)?.toInt() ?? 0,
      challengeDay: (j['challengeDay'] as num?)?.toInt(),
      challengeOf: (j['challengeOf'] as num?)?.toInt() ?? 365,
      events: [
        for (final e in (j['events'] as List? ?? const []))
          if (JourneyEvent.tryParse((e as Map).cast<String, dynamic>()) case final ev?) ev,
      ],
    );
  }

  /// Points still needed for the next level (null at the top).
  int? get toNext => level.nextAt == null ? null : level.nextAt! - lifetimePoints;
}

/* ------------------------------------------------------------ medal / card tags */

/// Mirrors contracts `TAG_ALPHABET` / `normalizeTagCode`: the permanent code printed on a Yaqeen key
/// medal or card (and inside its NFC chip as `/t/<code>`). No look-alikes (0/O, 1/I).
const tagAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const tagCodeLength = 8;
final _tagCode = RegExp('^[$tagAlphabet]{$tagCodeLength}\$');

/// "ab12-cd34", a pasted `…/t/AB12CD34` link or a `yaqeen://tag/…` → "AB12CD34".
String normalizeTagCode(String raw) {
  final s = raw.trim();
  final m = RegExp(r'(?:/t/|tag/)([^/?#]+)', caseSensitive: false).firstMatch(s);
  return (m?.group(1) ?? s).toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
}

bool isTagCode(String raw) => _tagCode.hasMatch(normalizeTagCode(raw));

/// "AB12CD34" → "AB12-CD34", as printed.
String formatTagCode(String code) => code.length == tagCodeLength ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

enum TagKind { medal, card }

/// One of the owner's activated tags (GET /v1/me/tags).
class CardTag {
  const CardTag({required this.code, required this.kind, required this.url, required this.linkedAt, required this.scans});
  final String code;
  final TagKind kind;
  final String url;
  final DateTime linkedAt;
  final int scans;

  factory CardTag.fromJson(Map<String, dynamic> j) => CardTag(
        code: j['code'] as String,
        kind: TagKind.values.asNameMap()[j['kind']] ?? TagKind.medal,
        url: j['url'] as String? ?? '',
        linkedAt: DateTime.tryParse(j['linkedAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        scans: (j['scans'] as num?)?.toInt() ?? 0,
      );
}

enum TagProblem { format, notFound, limit, paused, network }
