import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/community/presentation/league_screen.dart';
import 'package:yaqeen/features/community/presentation/tournament_screen.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import 'community_rig.dart';

/// Goldens `league_{ar,en}.png` and `tournament_{ar,en}.png`. They are generated only on Linux
/// (`.github/workflows/goldens.yml` runs `flutter test --update-goldens`); until a file exists the
/// comparison is skipped, so other platforms never write or compare a font-dependent image.
bool _missing(String name) => !autoUpdateGoldenFiles && !File('test/goldens/$name').existsSync();

/// Every avatar as the initial: no asset decoding, so the image is deterministic.
Map<String, dynamic> _initials(Map<String, dynamic> row) => {
      ...row,
      'avatar': {'kind': 'initial'},
    };

Map<String, dynamic> _profile() => {...fixtureMap('me_profile.json'), 'league': null};

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  Future<void> shoot(WidgetTester tester, CommunityRig rig, Widget screen, Type type, String golden, String locale) async {
    tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await rig.kv.write(ProfileRepository.meKey, jsonEncode(_profile()));
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(harness(screen, locale: locale, kv: rig.kv, overrides: rig.overrides));
      await tester.pumpAndSettle();
      await expectLater(find.byType(type), matchesGoldenFile('../../goldens/$golden'));
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final locale in ['ar', 'en']) {
    testWidgets('league golden ($locale)', (tester) async {
      final league = leagueJoined();
      league['rows'] = [for (final r in league['rows'] as List) _initials((r as Map).cast<String, dynamic>())];
      final rig = CommunityRig(routes: {
        'GET /v1/me/profile': (_) => jsonResponse(_profile()),
        'GET /v1/leagues/current': (_) => jsonResponse(league),
        'GET /v1/leagues/history': (_) => jsonResponse([
              {'startsOn': '2026-11-07', 'division': 2, 'rank': 2, 'size': 28, 'points': 510, 'outcome': 'up'},
            ]),
      },);
      await shoot(tester, rig, const LeagueScreen(), LeagueScreen, 'league_$locale.png', locale);
    }, skip: _missing('league_$locale.png'),);

    testWidgets('tournament golden ($locale)', (tester) async {
      final t = ((fixture('tournaments.json') as List)[1] as Map).cast<String, dynamic>();
      final id = t['id'] as String;
      final st = fixtureMap('standings.json');
      st['rows'] = [for (final r in st['rows'] as List) _initials((r as Map).cast<String, dynamic>())];
      st['nextCursor'] = null;
      final rig = CommunityRig(routes: {
        'GET /v1/me/profile': (_) => jsonResponse(_profile()),
        'GET /v1/tournaments/$id': (_) => jsonResponse(t),
        'GET /v1/tournaments/$id/standings': (_) => jsonResponse(st),
      },);
      await shoot(tester, rig, TournamentScreen(id: id), TournamentScreen, 'tournament_$locale.png', locale);
    }, skip: _missing('tournament_$locale.png'),);
  }
}
