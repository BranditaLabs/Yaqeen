import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/notifications/push_service.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/widgets/controls.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/card/domain/public_card.dart';
import 'package:yaqeen/features/card/presentation/card_screen.dart';
import 'package:yaqeen/features/card/presentation/journey_widgets.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

/// What GET /v1/me/journey returns (contracts `MyJourney`).
Map<String, Object?> journeyJson() => {
      'lifetimePoints': 1250,
      'level': {'level': 2, 'nameAr': 'على الطريق', 'nameEn': 'On the path', 'progress': 0.5, 'nextAt': 2000},
      'streak': 4,
      'challengeDay': 47,
      'challengeOf': 365,
      'events': [
        {'kind': 'level', 'date': '2026-10-01', 'value': 2},
        {'kind': 'challenge_day', 'date': '2026-09-30', 'value': 30},
        {'kind': 'something_new', 'date': '2026-09-20', 'value': 1},
        {'kind': 'badge', 'date': '2026-09-08', 'value': 7},
        {'kind': 'challenge_start', 'date': '2026-09-01', 'value': 1},
        {'kind': 'joined', 'date': '2026-08-31', 'value': null},
        {'kind': 'badge', 'date': '2026-08-30', 'value': 3},
      ],
    };

/// What GET /v1/me/public-profile returns (shape of contracts `PublicProfileSettings`).
Map<String, Object?> cardJson({bool published = false}) => {
      'published': published,
      'handle': 'ahmed',
      'displayName': 'أحمد',
      'bio': '',
      'links': [
        {'kind': 'instagram', 'value': '@ahmed'},
      ],
      'show': {'level': true, 'streak': false, 'challengeDay': false, 'badges': false, 'memberSince': false},
      'theme': 'sky',
      'url': 'https://id.test/u/ahmed',
      'views': 12,
    };

void main() {
  group('domain mirrors contracts/profile.ts', () {
    test('levels from lifetime points', () {
      expect(levelFor(0).level, 1);
      expect(levelFor(0).nextAt, 500);
      expect(levelFor(1250).level, 2);
      expect(levelFor(1250).progress, closeTo(0.5, 1e-9));
      expect(levelFor(99999).nameAr, 'منارة');
      expect(levelFor(99999).progress, 1);
    });

    test('social links: https only', () {
      expect(const SocialLink(SocialKind.instagram, '@ahmed.y').url, 'https://instagram.com/ahmed.y');
      expect(const SocialLink(SocialKind.whatsapp, '+20 100 123 4567').url, 'https://wa.me/201001234567');
      expect(const SocialLink(SocialKind.website, 'yaqin-brand.com/about').url, 'https://yaqin-brand.com/about');
      expect(const SocialLink(SocialKind.website, 'javascript:alert(1)').url, isNull);
      expect(const SocialLink(SocialKind.x, 'http://evil.test').url, isNull);
    });

    test('handle rules', () {
      expect(handleProblemOf('ahmed.y'), isNull);
      expect(handleProblemOf('1abc'), HandleProblem.format);
      expect(handleProblemOf('أحمد'), HandleProblem.format);
      expect(handleProblemOf('yaqeen'), HandleProblem.reserved);
    });

    test('parse → update body round-trip', () {
      final c = PublicCard.fromJson(cardJson());
      expect(c.links.single.kind, SocialKind.instagram);
      expect(c.views, 12);
      final body = c.copyWith(handle: '  Ahmed ', published: true).toUpdateJson();
      expect(body['handle'], 'ahmed');
      expect(body['published'], true);
      expect(body.containsKey('url'), isFalse);
      expect(body.containsKey('views'), isFalse);
    });

    test('medal codes: typed, printed or pasted as a link; deep link opens activation', () {
      expect(normalizeTagCode(' ab23-cd45 '), 'AB23CD45');
      expect(normalizeTagCode('https://id.test/t/AB23CD45?x=1'), 'AB23CD45');
      expect(isTagCode('ab23-cd45'), isTrue);
      expect(isTagCode('AB10CD45'), isFalse); // 1 and 0 are never printed
      expect(formatTagCode('AB23CD45'), 'AB23-CD45');
      expect(routeForDeepLink(Uri.parse('yaqeen://tag/ab23-cd45')), '/profile/card?tag=AB23CD45');
      expect(routeForDeepLink(Uri.parse('yaqeen://card')), '/profile/card');
    });

    test('remote config: card switches default on; the medal product link comes from admin', () {
      expect(const RemoteConfig().isOn(Flags.publicCards), isTrue);
      expect(const RemoteConfig().isOn(Flags.medalActivation), isTrue);
      final c = RemoteConfig.fromJson({
        'features': {'medalActivation': false},
        'cards': {'medalProductUrl': 'https://store.test/medal'},
      });
      expect(c.isOn(Flags.medalActivation), isFalse);
      expect(c.isOn(Flags.publicCards), isTrue);
      expect(c.medalProductUrl, 'https://store.test/medal');
      expect(PublicCard.fromJson({...cardJson(), 'moderated': true}).moderated, isTrue);
    });

    test('journey parses, skipping kinds a newer server may add', () {
      final j = MyJourney.fromJson(journeyJson());
      expect(j.events.map((e) => e.kind), [
        JourneyKind.level,
        JourneyKind.challengeDay,
        JourneyKind.badge,
        JourneyKind.challengeStart,
        JourneyKind.joined,
        JourneyKind.badge,
      ]);
      expect(j.toNext, 750);
      expect(j.events.first.golden, isTrue);
      expect(const CardVisibility().timeline, isFalse); // off unless the user switches it on
      expect(CardVisibility.fromJson(const {}).toJson()['timeline'], false);
    });

  });

  group('card screen', () {
    setUpAll(loadAppFonts);
    setUp(() => YqGlassConfig.enableBlur = false);

    late List<http.Request> requests;
    late List<Map<String, Object?>> tags;
    http.Client server({bool published = false, bool moderated = false}) => MockClient((req) async {
          requests.add(req);
          final p = req.url.path;
          final h = {'content-type': 'application/json'};
          if (p == '/v1/me/public-profile' && req.method == 'GET') {
            return http.Response(jsonEncode({...cardJson(published: published), 'moderated': moderated}), 200, headers: h);
          }
          if (p == '/v1/me/public-profile' && req.method == 'PUT') {
            final body = (jsonDecode(req.body) as Map).cast<String, Object?>();
            return http.Response(jsonEncode({...body, 'url': 'https://id.test/u/${body['handle']}', 'views': 12}), 200, headers: h);
          }
          if (p == '/v1/me/public-profile/available') return http.Response(jsonEncode({'available': true}), 200, headers: h);
          if (p == '/v1/public/profiles/ahmed') {
            return http.Response(
              jsonEncode({
                'level': {'level': 2, 'nameAr': 'على الطريق', 'nameEn': 'On the path', 'progress': 0.3},
                'streak': null,
                'challengeDay': null,
                'badges': null,
              }),
              200,
              headers: h,
            );
          }
          if (p == '/v1/me/tags' && req.method == 'GET') return http.Response(jsonEncode(tags), 200, headers: h);
          if (p == '/v1/me/tags' && req.method == 'POST') {
            final code = (jsonDecode(req.body) as Map)['code'];
            if (code != 'AB23CD45') return http.Response(jsonEncode({'error': {'code': 'not_found'}}), 404, headers: h);
            final tag = {'code': code, 'kind': 'medal', 'url': 'https://id.test/t/$code', 'linkedAt': '2026-10-26T10:00:00Z', 'scans': 0};
            tags.add(tag);
            return http.Response(jsonEncode(tag), 200, headers: h);
          }
          if (p.startsWith('/v1/me/tags/') && req.method == 'DELETE') {
            tags.removeWhere((t) => t['code'] == p.split('/').last);
            return http.Response('', 204, headers: h);
          }
          if (p == '/v1/me/journey') return http.Response(jsonEncode(journeyJson()), 200, headers: h);
          if (p == '/v1/me/ledger') return http.Response('[]', 200, headers: h);
          return http.Response('{}', 404, headers: h);
        });

    Future<List<Override>> overrides({bool published = false, bool guest = false, RemoteConfig? config, bool moderated = false}) async {
      requests = [];
      tags = [];
      final secure = MemoryKvStore();
      await secure.write('auth.access', 'token');
      return [
        initialSessionProvider.overrideWithValue(
          guest ? const Session(provider: SignInProvider.guest) : const Session(provider: SignInProvider.google, userId: 'u1', displayName: 'أحمد'),
        ),
        tokenStoreProvider.overrideWithValue(TokenStore(secure)),
        apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'https://api.test', tokens: ref.watch(tokenStoreProvider), client: server(published: published, moderated: moderated))),
        if (config != null) initialConfigProvider.overrideWithValue(config),
      ];
    }

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('guests are invited to sign in', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(guest: true)));
      await settle(tester);
      expect(find.text('سجّل الدخول لتصنع بطاقتك العامة وتشاركها'), findsOneWidget);
    });

    testWidgets('loads the card, previews it, and saves only after a change', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides()));
      await settle(tester);
      expect(find.text('@ahmed'), findsWidgets); // preview handle (and the Instagram link)
      expect(find.text('مخفية'), findsOneWidget);
      expect(find.text('12'), findsOneWidget); // opens orb
      expect(find.text('عباداتك لا تظهر أبداً: لا صلوات ولا أذكار ولا صفحات. تظهر فقط الأرقام التي تختارها هنا.'), findsOneWidget);

      // Nothing changed → nothing to save.
      final save = find.widgetWithText(GestureDetector, 'حفظ البطاقة');
      await tester.tap(find.text('حفظ البطاقة'));
      await settle(tester);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
      expect(save, findsWidgets);

      // Publish + show the streak, then save.
      // Switches in order: publish, then level, streak, challenge day, badges, member since.
      await tester.tap(find.byType(YqSwitch).at(0));
      await tester.tap(find.byType(YqSwitch).at(2));
      await tester.pump();
      await tester.tap(find.text('حفظ البطاقة'));
      await settle(tester);
      final put = requests.singleWhere((r) => r.method == 'PUT');
      final body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['published'], true);
      expect((body['show'] as Map)['streak'], true);
      expect(body['links'], [
        {'kind': 'instagram', 'value': '@ahmed'},
      ]);
      expect(find.text('منشورة'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // the «saved» toast
    });

    testWidgets('the journey switch previews the milestones and saves the choice', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides()));
      await settle(tester);
      expect(find.text('الانضمام إلى يقين'), findsNothing);
      // Switches: publish, level, streak, challenge day, badges, member since, journey.
      await tester.tap(find.byType(YqSwitch).at(6));
      await settle(tester);
      expect(find.text('مستوى «على الطريق»'), findsOneWidget); // newest three in the preview
      expect(find.text('اليوم 30 من رحلة 365'), findsOneWidget);
      expect(find.text('الانضمام إلى يقين'), findsNothing);
      await tester.tap(find.text('حفظ البطاقة'));
      await settle(tester);
      final body = jsonDecode(requests.singleWhere((r) => r.method == 'PUT').body) as Map<String, dynamic>;
      expect((body['show'] as Map)['timeline'], true);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Profile journey: level, lifetime points and the whole rail on demand', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const Scaffold(body: SingleChildScrollView(child: JourneySection())), overrides: await overrides()));
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('على الطريق'), findsOneWidget);
      expect(find.text('1,250 نقطة منذ البداية'), findsOneWidget);
      expect(find.text('750 نقطة إلى «مواظب»'), findsOneWidget);
      expect(find.text('وسام المواظبة · 7 أيام'), findsOneWidget);
      expect(find.text('وسام المواظبة · 3 أيام'), findsNothing); // sixth: behind «the whole journey»
      await tester.tap(find.text('الرحلة كاملة'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('وسام المواظبة · 3 أيام'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('الانضمام إلى يقين، 31 أغسطس 2026')), findsOneWidget);
    });

    testWidgets('a bad handle blocks saving and says why', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides()));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'ahmed'), 'yaqeen');
      await tester.pump();
      expect(find.text('هذا الاسم محجوز'), findsOneWidget);
      await tester.tap(find.text('حفظ البطاقة'));
      await settle(tester);
      expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    testWidgets('a medal from the deep link activates, then lists and can be switched off', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const CardScreen(tag: 'ab23-cd45'), overrides: await overrides(published: true)));
      await settle(tester);
      expect(find.text('ميدالية وبطاقة يقين'), findsOneWidget); // the sheet opened by itself
      expect(find.widgetWithText(TextField, 'AB23-CD45'), findsOneWidget);
      await tester.tap(find.text('تفعيل'));
      await settle(tester);
      final post = requests.singleWhere((r) => r.method == 'POST' && r.url.path == '/v1/me/tags');
      expect(jsonDecode(post.body), {'code': 'AB23CD45'});
      expect(find.text('فُعّلت! كل لمسة أو مسح يفتح بطاقتك الآن.'), findsOneWidget);
      expect(find.text('ميدالية مفاتيح · AB23-CD45'), findsOneWidget);

      await tester.tap(find.byTooltip('إيقاف، فقدتها؟'));
      await settle(tester);
      await tester.tap(find.text('إيقافها'));
      await settle(tester);
      expect(requests.where((r) => r.method == 'DELETE' && r.url.path == '/v1/me/tags/AB23CD45'), hasLength(1));
      expect(find.text('ميدالية مفاتيح · AB23-CD45'), findsNothing);
    });

    testWidgets('admin switches: medals off hides the orb; cards off pauses the screen; moderation explains itself', (tester) async {
      tall(tester);
      final medalsOff = RemoteConfig(features: Map.of(RemoteConfig.defaultFeatures)..[Flags.medalActivation] = false);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(config: medalsOff)));
      await settle(tester);
      expect(find.text('ميدالياتي'), findsNothing);
      expect(find.text('حفظ البطاقة'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // a fresh scope for each case
      final cardsOff = RemoteConfig(features: Map.of(RemoteConfig.defaultFeatures)..[Flags.publicCards] = false);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(config: cardsOff)));
      await settle(tester);
      expect(find.text('البطاقات العامة متوقفة مؤقتاً، وستعود قريباً.'), findsOneWidget);
      expect(find.text('حفظ البطاقة'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(moderated: true)));
      await settle(tester);
      expect(find.text('أوقف فريق يقين ظهور بطاقتك لمخالفتها الإرشادات. تواصل معنا لمراجعتها.'), findsOneWidget);
    });

    testWidgets('a wrong or mistyped code says why, and a mistyped one never reaches the server', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides()));
      await settle(tester);
      expect(find.text('فعّل ميداليتك'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('^ميدالياتي')).first);
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'XXXX-XXXX'), 'abc');
      await tester.tap(find.text('تفعيل'));
      await settle(tester);
      expect(find.text('الرمز 8 خانات، مثل AB12-CD34'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.enterText(find.byType(TextField).last, 'ZZZZ-ZZZZ');
      await tester.tap(find.text('تفعيل'));
      await settle(tester);
      expect(find.text('لم نجد هذا الرمز، أو فُعّل من قبل. تأكد منه أو تواصل معنا.'), findsOneWidget);
    });
  });
}
