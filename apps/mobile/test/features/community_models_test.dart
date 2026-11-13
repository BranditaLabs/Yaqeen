import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/features/community/domain/community_models.dart';
import 'package:yaqeen/features/community/presentation/badge_label.dart';
import 'package:yaqeen/features/profile/domain/avatar.dart';
import 'package:yaqeen/features/profile/domain/level.dart';
import 'package:yaqeen/features/profile/domain/me_profile.dart';
import 'package:yaqeen/l10n/gen/app_localizations_ar.dart';
import 'package:yaqeen/l10n/gen/app_localizations_en.dart';

/// Shared fixtures (also parsed by zod in services/api/test/contracts-fixtures.test.ts) and the
/// generated constants (tools/contracts/gen_dart_fixtures.mjs) keep the Dart mirrors in step.
Object? fixture(String name) => jsonDecode(File('test/fixtures/community/$name').readAsStringSync());
Map<String, dynamic> obj(String name) => (fixture(name) as Map).cast<String, dynamic>();

void main() {
  final constants = obj('constants.json');

  group('fixtures parse', () {
    test('me_profile.json', () {
      final p = MeProfile.fromJson(obj('me_profile.json'));
      expect(p.displayName, 'أحمد');
      expect(p.handle, 'ahmed-4821');
      expect(p.avatar, const PresetAvatar('m03'));
      expect(p.level.level, 3);
      expect(p.weekPoints, 145);
      expect(p.community.leagues, isTrue);
      expect(p.community.attestedAdult, isTrue);
      expect(p.community.country, 'EG');
      expect(p.league!.divisionAr, 'ذهب');
      expect(p.league!.lastWeek!.outcome, LeagueOutcome.up);
      expect(p.league!.lastWeek!.badge!.kind, BadgeKind.leagueTop3);
      expect(p.recentBadges, hasLength(3));
      expect(p.firstName, 'أحمد');
      // Round-trips through the device cache.
      expect(MeProfile.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>).toJson(), p.toJson());
    });

    test('me_profile_photo.json: own photo uses authed paths', () {
      final p = MeProfile.fromJson(obj('me_profile_photo.json'));
      final a = p.avatar as PhotoAvatar;
      expect(a.isAuthedPath, isTrue);
      expect(a.url, '/v1/me/avatar/photo/256');
      expect(p.level.isTop, isTrue);
      expect(p.league, isNull);
      expect(p.community, CommunitySettings.off);
    });

    test('league states', () {
      expect(LeagueCurrent.fromJson(obj('league_current_off.json')), isA<LeagueOff>());
      expect(LeagueCurrent.fromJson(obj('league_current_closing.json')), isA<LeagueClosing>());
      final j = LeagueCurrent.fromJson(obj('league_current_joined.json')) as LeagueJoined;
      expect(j.division, 3);
      expect(j.myLivePoints, 335);
      expect(j.snapshotDay, '2026-11-16');
      expect(j.rows.map((r) => r.rank), [1, 1, 3, 4, null]); // ties share a rank; 0 points → null
      expect(j.rows[1].name, isNull); // hidden name → «عضو يقين»
      expect(j.rows[2].avatar, isA<PhotoAvatar>());
      expect((j.rows[2].avatar as PhotoAvatar).isAuthedPath, isFalse);
      expect(j.rows.where((r) => r.me).single.handle, 'ahmed-4821');
      expect(LeagueCurrent.fromJson(j.toJson()).toJson(), j.toJson());
    });

    test('tournaments, standings, leaderboard, badges, blocks, levels', () {
      final ts = Tournament.listFrom(fixture('tournaments.json'));
      expect(ts.map((t) => t.phase), [TournamentPhase.upcoming, TournamentPhase.live, TournamentPhase.ended]);
      expect(ts[1].me!.points, 640);
      expect(ts[0].joinOpen(DateTime.utc(2027, 2, 10)), isTrue);
      expect(ts[0].joinOpen(DateTime.utc(2027, 2, 20)), isFalse);

      final s = TournamentStandings.fromJson(obj('standings.json'));
      expect(s.rows, hasLength(3));
      expect(s.me!.me, isTrue);
      expect(s.nextCursor, isNotNull);

      final lb = LeaderboardView.fromJson(obj('leaderboard.json'));
      expect(lb.scope, LeaderboardScope.global);
      expect(lb.rows.every((r) => r.points == null), isTrue); // level board: rings only
      expect(lb.countryJoined, isFalse);

      final badges = Badge.listFrom(fixture('badges.json'));
      expect(badges.map((b) => b.kind).toSet(), BadgeKind.values.toSet());
      expect(Badge.tryParse({'kind': 'from_the_future', 'refKey': 'x', 'awardedAt': '2026-01-01T00:00:00Z'}), isNull);

      final blocks = BlockedUser.listFrom(fixture('blocks.json'));
      expect(blocks.first.name, isNull);
      expect(blocks.last.avatar, const PresetAvatar('m05'));

      for (final l in (fixture('levels.json') as List).cast<Map<String, dynamic>>()) {
        final level = CardLevel.fromJson(l);
        final (min, _, _) = cardLevels[level.level - 1];
        final sample = level.nextAt == null ? min : (min + level.progress * (level.nextAt! - min)).round();
        expect(levelFor(sample), level);
      }
    });
  });

  group('parity with the contracts (constants.json)', () {
    test('levelFor', () {
      for (final v in (constants['levelFor'] as List).cast<Map<String, dynamic>>()) {
        final l = levelFor((v['points'] as num).toInt());
        expect(l.level, v['level']);
        expect(l.nameAr, v['nameAr']);
        expect(l.nameEn, v['nameEn']);
        expect(l.progress, closeTo((v['progress'] as num).toDouble(), 1e-9));
        expect(l.nextAt, v['nextAt']);
      }
      final levels = (constants['LEVELS'] as List).cast<Map<String, dynamic>>();
      expect([for (final l in cardLevels) [l.$1, l.$2, l.$3]], [for (final l in levels) [l['min'], l['ar'], l['en']]]);
    });

    test('DIVISIONS', () {
      final divisions = (constants['DIVISIONS'] as List).cast<Map<String, dynamic>>();
      expect([for (final d in kDivisions) {'id': d.id, 'key': d.key, 'ar': d.ar, 'en': d.en}], divisions);
    });

    test('BADGE_KINDS', () {
      expect(BadgeKind.values.map((k) => k.wire).toList(), constants['BADGE_KINDS']);
    });

    test('COMMUNITY_ERROR_CODES: one failure per code, plus offline and unknown', () {
      expect(CommunityFailure.serverCodes.map((f) => f.code).toList(), constants['COMMUNITY_ERROR_CODES']);
      for (final code in (constants['COMMUNITY_ERROR_CODES'] as List).cast<String>()) {
        expect(CommunityFailure.fromCode(code).code, code);
      }
      expect(CommunityFailure.fromCode('nope'), CommunityFailure.unknown);
    });

    test('REPORT_REASONS', () {
      expect(ReportReason.values.map((r) => r.name).toList(), constants['REPORT_REASONS']);
    });
  });

  group('labels', () {
    final ar = AppLocalizationsAr();
    final en = AppLocalizationsEn();
    test('badgeLabel for every kind, ar and en, with Western digits', () {
      final badges = Badge.listFrom(fixture('badges.json'));
      final labels = {for (final b in badges) b.kind: badgeLabel(b, ar, 'ar')};
      expect(labels[BadgeKind.leagueTop3], 'بين الثلاثة الأوائل');
      expect(labels[BadgeKind.leaguePromoted], 'صعود إلى فضة');
      expect(labels[BadgeKind.divisionReached], 'بلوغ قسم ذهب');
      expect(labels[BadgeKind.tournamentPodium], 'منصّة تحدّي المولد');
      expect(labels[BadgeKind.tournamentTop10], 'أعلى 10% · صيف الخير');
      expect(labels[BadgeKind.streak], '7 أيام متتالية');
      expect(labels[BadgeKind.level], 'بلوغ مستوى على الطريق');
      for (final b in badges) {
        expect(badgeLabel(b, en, 'en'), isNotEmpty);
        expect(badgeLabel(b, ar, 'ar'), isNot(matches(RegExp('[٠-٩]'))));
      }
    });

    test('divisionName: bundled names, or the admin name in force', () {
      expect(divisionName(3, ar), 'ذهب');
      expect(divisionName(6, en), 'Diamond');
      expect(divisionName(2, ar, custom: 'الفضة'), 'الفضة');
    });
  });

  test('CommunityUpdate wire', () {
    expect(
      const CommunityUpdate(leagues: true, displayName: ' سارة ', attestAdult: true, source: CommunitySource.onboarding).toJson(),
      {'leagues': true, 'displayName': 'سارة', 'attestAdult': true, 'source': 'onboarding'},
    );
    expect(const CommunityUpdate(leaderboard: false).toJson(), {'leaderboard': false, 'source': 'settings'});
  });
}
