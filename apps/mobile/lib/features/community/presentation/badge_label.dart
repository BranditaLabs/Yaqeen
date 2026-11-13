import '../../../l10n/gen/app_localizations.dart';
import '../../profile/domain/level.dart';
import '../domain/community_models.dart';

/// The localized name of division [id] (1–6). [custom] is the admin's name in force, when the
/// server sent one (`divisionAr/En`, a badge's `labelAr/En`); else the bundled names.
String divisionName(int id, AppLocalizations t, {String? custom}) {
  if (custom != null && custom.trim().isNotEmpty) return custom;
  return switch (id.clamp(1, 6)) {
    1 => t.divBronze,
    2 => t.divSilver,
    3 => t.divGold,
    4 => t.divEmerald,
    5 => t.divRuby,
    _ => t.divDiamond,
  };
}

/// What a badge says, e.g. «بين الثلاثة الأوائل», «صعود إلى فضة», «منصّة رمضان 1448».
String badgeLabel(Badge badge, AppLocalizations t, String locale) {
  final m = badge.meta;
  String division() => divisionName(m.division ?? 1, t, custom: m.label(locale));
  String title() => m.title(locale) ?? m.label(locale) ?? '';
  return switch (badge.kind) {
    BadgeKind.streak => t.badgeStreak(m.days ?? 0),
    BadgeKind.level => t.badgeLevel(_levelName(m.level ?? 1, locale)),
    BadgeKind.leagueFirst => t.badgeLeagueFirst,
    BadgeKind.leagueTop3 => t.badgeLeagueTop3,
    BadgeKind.leaguePromoted => t.badgeLeaguePromoted(division()),
    BadgeKind.divisionReached => t.badgeDivision(division()),
    BadgeKind.tournamentPodium => t.badgeTournamentPodium(title()),
    BadgeKind.tournamentTop10 => t.badgeTournamentTop10(title()),
    BadgeKind.tournamentFinisher => t.badgeTournamentFinisher(title()),
  };
}

String _levelName(int level, String locale) {
  final l = cardLevels[(level - 1).clamp(0, cardLevels.length - 1)];
  return locale == 'ar' ? l.$2 : l.$3;
}
