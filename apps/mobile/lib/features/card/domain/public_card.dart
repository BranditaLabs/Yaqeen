import 'dart:convert';
import 'dart:typed_data';

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
  const CardVisibility({this.level = true, this.streak = false, this.challengeDay = false, this.badges = false, this.memberSince = false});
  final bool level;
  final bool streak;
  final bool challengeDay;
  final bool badges;
  final bool memberSince;

  factory CardVisibility.fromJson(Map<String, dynamic> j) => CardVisibility(
        level: j['level'] as bool? ?? true,
        streak: j['streak'] as bool? ?? false,
        challengeDay: j['challengeDay'] as bool? ?? false,
        badges: j['badges'] as bool? ?? false,
        memberSince: j['memberSince'] as bool? ?? false,
      );
  Map<String, dynamic> toJson() => {'level': level, 'streak': streak, 'challengeDay': challengeDay, 'badges': badges, 'memberSince': memberSince};

  CardVisibility copyWith({bool? level, bool? streak, bool? challengeDay, bool? badges, bool? memberSince}) => CardVisibility(
        level: level ?? this.level,
        streak: streak ?? this.streak,
        challengeDay: challengeDay ?? this.challengeDay,
        badges: badges ?? this.badges,
        memberSince: memberSince ?? this.memberSince,
      );

  @override
  bool operator ==(Object other) =>
      other is CardVisibility &&
      other.level == level &&
      other.streak == streak &&
      other.challengeDay == challengeDay &&
      other.badges == badges &&
      other.memberSince == memberSince;
  @override
  int get hashCode => Object.hash(level, streak, challengeDay, badges, memberSince);
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
  const CardView({required this.level, required this.streak, required this.challengeDay, required this.challengeOf, required this.badges});
  final CardLevel? level;
  final int? streak;
  final int? challengeDay;
  final int? challengeOf;
  final List<int>? badges;

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
    );
  }
}

/* ------------------------------------------------------------------- NFC */

/// NDEF well-known URI record payload: one prefix byte (0x04 = "https://", 0x03 = "http://",
/// 0x00 = none) then the rest of the URI in UTF-8 (NFC Forum URI RTD).
Uint8List uriRecordPayload(String uri) {
  const prefixes = {'https://www.': 0x02, 'http://www.': 0x01, 'https://': 0x04, 'http://': 0x03};
  for (final e in prefixes.entries) {
    if (uri.startsWith(e.key)) return Uint8List.fromList([e.value, ...utf8.encode(uri.substring(e.key.length))]);
  }
  return Uint8List.fromList([0x00, ...utf8.encode(uri)]);
}
