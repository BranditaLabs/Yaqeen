import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/calendar/presentation/calendar_screen.dart';
import 'package:yaqeen/features/challenge/presentation/challenge_screen.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/rewards/presentation/redeem_screen.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

Map<String, Object?> day(String date, int n, String status, List<String> done, int points) =>
    {'date': date, 'dayNumber': n, 'status': status, 'points': points, 'completedTasks': done, 'bonuses': <String>[]};

final summary = {
  'enrolled': true,
  'startedOn': '2026-09-04',
  'dayNumber': 47,
  'streak': 12,
  'balance': 3240,
  'challengeLengthDays': 365,
  'nextMilestone': {'days': 30, 'points': 200},
  'today': day('2026-10-20', 47, 'today', ['wird'], 20),
  'qadaDays': 2,
  'tasks': [
    {'key': 'wird', 'labelAr': 'الورد اليومي', 'labelEn': 'Daily wird', 'points': 20},
    {'key': 'five_prayers', 'labelAr': 'الصلوات الخمس', 'labelEn': 'Five prayers', 'points': 25},
    {'key': 'morning_azkar', 'labelAr': 'أذكار الصباح', 'labelEn': 'Morning azkar', 'points': 10},
  ],
};

Map<String, Object?> cell(String g, int h, int weekday, Map<String, Object?>? challenge, [List<String> special = const []]) => {
      'gregorian': g,
      'hijriDay': h,
      'hijriMonth': 5,
      'hijriYear': 1448,
      'hijriMonthNameAr': 'جمادى الأولى',
      'weekday': weekday,
      'challenge': challenge,
      'special': special,
    };

final calendar = {
  'month': '2026-10',
  'enrolled': true,
  'startedOn': '2026-09-04',
  'endsOn': '2027-09-03',
  'today': '2026-10-20',
  'dayNumber': 47,
  'streak': 12,
  'balance': 3240,
  'qadaWindowDays': 7,
  'qadaDayPoints': 80,
  'dailyTotal': 100,
  'days': [
    cell('2026-10-17', 5, 6, day('2026-10-17', 44, 'done', ['wird', 'five_prayers', 'morning_azkar'], 100)),
    cell('2026-10-18', 6, 0, day('2026-10-18', 45, 'qada', ['wird'], 80)),
    cell('2026-10-19', 7, 1, day('2026-10-19', 46, 'missed', [], 0), ['mon_thu']),
    cell('2026-10-20', 8, 2, day('2026-10-20', 47, 'today', ['wird'], 20)),
    cell('2026-10-21', 9, 3, day('2026-10-21', 48, 'future', [], 0)),
  ],
};

final rewards = [
  {
    'id': '00000000-0000-4000-8000-0000000000a1',
    'titleAr': 'خصم 50 ج.م',
    'titleEn': '50 EGP off',
    'kind': 'fixed_amount',
    'value': 50,
    'costPoints': 1000,
    'available': true,
  },
  {
    'id': '00000000-0000-4000-8000-0000000000a2',
    'titleAr': 'شحن مجاني',
    'titleEn': 'Free shipping',
    'kind': 'free_shipping',
    'value': 0,
    'costPoints': 4000,
    'available': false,
  },
];

final requests = <http.BaseRequest>[];
var redeemCalls = 0;

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

http.Client server({String? redeemError}) => MockClient((req) async {
      requests.add(req);
      final p = req.url.path;
      if (p == '/v1/challenge/summary') return json(summary);
      if (p == '/v1/challenge/calendar') return json(calendar);
      if (p == '/v1/daily-task') return json({'date': '2026-10-20', 'taskAr': '[مهمة اليوم]', 'taskEn': '[Task]'});
      if (p == '/v1/rewards') return json(rewards);
      if (p.endsWith('/redeem')) {
        redeemCalls++;
        if (redeemError != null) {
          return json(
            {
              'error': {'code': redeemError, 'message': 'x'},
            },
            503,
          );
        }
        return json({
          'id': 'r1',
          'rewardId': rewards[0]['id'],
          'code': 'YQ-AB12-CD34',
          'status': 'issued',
          'expiresAt': '2026-11-19T00:00:00Z',
          'balanceAfter': 2240,
        });
      }
      if (p.endsWith('/complete')) {
        return json(
          {
            'error': {'code': 'day_closed', 'message': 'closed'},
          },
          409,
        );
      }
      return json(
        {
          'error': {'code': 'not_found'},
        },
        404,
      );
    });

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() {
    YqGlassConfig.enableBlur = false;
    requests.clear();
    redeemCalls = 0;
  });

  Future<List<Override>> base({String? redeemError}) async {
    final secure = MemoryKvStore();
    await secure.write('auth.access', 'token');
    return [
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 9)),
      initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.google, userId: 'u1', displayName: 'أحمد')),
      tokenStoreProvider.overrideWithValue(TokenStore(secure)),
      apiClientProvider.overrideWith(
        (ref) => ApiClient(baseUrl: 'https://api.test', tokens: ref.watch(tokenStoreProvider), client: server(redeemError: redeemError)),
      ),
    ];
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('challenge: hero, tasks from the summary, private prayers, qada days, rejected tick reverts', (tester) async {
    phone(tester);
    final o = await base();
    await tester.pumpWidget(harness(const Scaffold(body: ChallengeScreen()), overrides: o));
    await settle(tester);
    expect(find.text('3,240 نقطة'), findsOneWidget);
    expect(find.text('يوما قضاء'), findsOneWidget);
    expect(find.text('20 من 55'), findsOneWidget);
    expect(find.text('الصلوات الخمس'), findsOneWidget);
    expect(find.text('خاص بك'), findsOneWidget);
    expect(find.text('يُحتسب تلقائياً'), findsNWidgets(2));
    expect(find.text('1,000 نقطة لكل مكافأة'), findsNothing); // config has no cheapest reward in tests

    await tester.tap(find.text('الصلوات الخمس'));
    await settle(tester);
    expect(requests.where((r) => r.url.path.endsWith('five_prayers/complete')), isNotEmpty);
    expect(find.text('انتهى هذا اليوم، ولم تُحتسب المهمة'), findsOneWidget);
    expect(find.text('20 من 55'), findsOneWidget); // reverted
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('calendar: Saturday-first grid, statuses, qada CTA inside the window', (tester) async {
    phone(tester);
    final o = await base();
    await tester.pumpWidget(harness(const CalendarScreen(), overrides: o));
    await settle(tester);
    expect(find.text('تقويم اليقين'), findsOneWidget);
    expect(find.text('جمادى الأولى 1448'), findsOneWidget);
    expect(find.text('سبت'), findsOneWidget);
    expect(find.bySemanticsLabel('7 جمادى الأولى، 2026-10-19، فائت'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('7 جمادى الأولى، 2026-10-19، فائت'));
    await tester.pumpAndSettle();
    expect(find.text('فائت · 0 / 80'), findsOneWidget);
    expect(find.text('قضاء هذا اليوم الآن · يحافظ على رحلتك'), findsOneWidget);
    expect(find.text('الإثنين/الخميس'), findsOneWidget);
  });

  testWidgets('redeem: choose → confirm → success with code; idempotency key sent', (tester) async {
    phone(tester);
    final o = await base();
    await tester.pumpWidget(harness(const RedeemScreen(), overrides: o));
    await settle(tester);
    expect(find.text('رصيدك الحالي 3,240 نقطة'), findsOneWidget);
    expect(find.text('متاح'), findsOneWidget);
    expect(find.text('ينقصك 760'), findsOneWidget);
    await tester.tap(find.text('استبدال').first);
    await tester.pumpAndSettle();
    expect(find.text('تأكيد الاستبدال'), findsOneWidget);
    expect(find.text('− 1,000'), findsOneWidget);
    expect(find.text('2,240'), findsOneWidget);
    await tester.tap(find.text('تأكيد'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('بارك الله لك'), findsOneWidget);
    expect(find.text('YQ-AB12-CD34'), findsOneWidget);
    final redeem = requests.firstWhere((r) => r.url.path.endsWith('/redeem'));
    expect(redeem.headers['Idempotency-Key'], hasLength(32));
  });

  testWidgets('redeem: Shopify down → «لم تُخصم نقاطك», stays on confirm', (tester) async {
    phone(tester);
    final o = await base(redeemError: 'shopify_unavailable');
    await tester.pumpWidget(harness(const RedeemScreen(), overrides: o));
    await settle(tester);
    await tester.tap(find.text('استبدال').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد'));
    await settle(tester);
    expect(find.text('المتجر غير متاح الآن، لم تُخصم نقاطك'), findsOneWidget);
    expect(find.text('تأكيد الاستبدال'), findsOneWidget);
  });
}
