import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';
import 'package:yaqeen/core/platform/location_service.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/storage/local_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/notifications/data/inbox_repository.dart';
import 'package:yaqeen/features/notifications/domain/inbox_item.dart';
import 'package:yaqeen/features/notifications/presentation/inbox_screen.dart';
import 'package:yaqeen/features/notifications/presentation/notification_settings_screen.dart';
import 'package:yaqeen/features/prayer/presentation/prayer_screen.dart';
import 'package:yaqeen/features/prayer/presentation/qibla_screen.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  // Tuesday 20 Oct 2026, 15:00 Cairo — Asr (15:53) is next.
  final now = DateTime.utc(2026, 10, 20, 12, 0);
  const cairo = AppSettings(place: Place.cairo);

  List<dynamic> base({AppSettings settings = cairo, MemoryKvStore? kv}) => [
        clockProvider.overrideWithValue(() => now),
        initialSettingsProvider.overrideWithValue(settings),
      ];

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('prayer times: six rows, Asr highlighted with a countdown, Qibla 136°', (tester) async {
    tall(tester);
    await tester.pumpWidget(harness(const Scaffold(body: PrayerScreen()), overrides: [...base()].cast()));
    await tester.pump();
    expect(find.text('مواقيت الصلاة'), findsOneWidget);
    // The stage leads with Asr; the arc and the day's journey name it too.
    expect(find.text('العصر'), findsNWidgets(3));
    expect(find.text('3:53 م'), findsOneWidget);
    expect(find.text('بعد 00:53:00'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('اتجاه القبلة 136°')), findsOneWidget);
    expect(find.textContaining('الهيئة المصرية العامة للمساحة'), findsOneWidget);
  });

  testWidgets('bell toggles a prayer off and on (device-only setting)', (tester) async {
    tall(tester);
    final kv = MemoryKvStore();
    await tester.pumpWidget(harness(const Scaffold(body: PrayerScreen()), kv: kv, overrides: [...base()].cast()));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('تنبيه الفجر مفعل'));
    await tester.pump();
    expect(find.bySemanticsLabel('تنبيه الفجر متوقف'), findsOneWidget);
    expect(kv.data['settings.v1'], contains('"fajr":"silent"'));
  });

  testWidgets('Friday shows Jumu\'ah instead of Dhuhr', (tester) async {
    tall(tester);
    final friday = DateTime.utc(2026, 10, 23, 6);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: PrayerScreen()),
        overrides: [clockProvider.overrideWithValue(() => friday), initialSettingsProvider.overrideWithValue(cairo)],
      ),
    );
    await tester.pump();
    expect(find.text('الجمعة'), findsWidgets);
    expect(find.text('الظهر'), findsNothing);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 1100 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('qibla: guidance and aligned state from the compass', (tester) async {
    phone(tester);
    final headings = StreamController<HeadingReading>();
    await tester.pumpWidget(
      harness(
        const QiblaScreen(),
        overrides: [
          ...base().cast(),
          compassServiceProvider.overrideWithValue(FakeCompassService(headings.stream)),
        ],
      ),
    );
    headings.add(const HeadingReading(100));
    await tester.pump();
    expect(find.text('استدر يميناً'), findsOneWidget);
    headings.add(const HeadingReading(135.5));
    await tester.pump();
    await tester.pump();
    expect(find.text('أنت في اتجاه القبلة'), findsOneWidget);
    headings.add(const HeadingReading(200, accuracy: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('استدر يساراً'), findsOneWidget);
    expect(find.text('البوصلة تحتاج معايرة'), findsOneWidget);
    await headings.close();
  });

  testWidgets('qibla without a compass still gives the bearing', (tester) async {
    phone(tester);
    await tester.pumpWidget(harness(const QiblaScreen(), overrides: base().cast()));
    await tester.pump();
    expect(find.textContaining('136°'), findsWidgets);
  });

  testWidgets('notification settings: tapping a mode cycles adhan → notify → silent', (tester) async {
    final scheduler = NoopLocalNotificationScheduler();
    await tester.pumpWidget(
      harness(
        const NotificationSettingsScreen(),
        overrides: [
          ...base().cast(),
          localNotificationsProvider.overrideWithValue(scheduler),
        ],
      ),
    );
    await tester.pump();
    final fajr = find.bySemanticsLabel('الفجر، الوضع الحالي أذان. المس للتغيير');
    expect(fajr, findsOneWidget);
    await tester.tap(fajr);
    await tester.pump();
    expect(find.bySemanticsLabel('الفجر، الوضع الحالي تنبيه. المس للتغيير'), findsOneWidget);
  });

  testWidgets('inbox: grouped, unread dot, filters, empty state', (tester) async {
    final kv = MemoryKvStore();
    final repo = InboxRepository(LocalStore(kv), now: () => now);
    await repo.addAll([
      InboxItem(
        id: 'a',
        category: InboxCategory.worship,
        title: 'العصر بعد 10 دقائق',
        body: 'استعد للصلاة · 3:53 م',
        at: now.subtract(const Duration(minutes: 5)),
      ),
      InboxItem(
        id: 'b',
        category: InboxCategory.offers,
        title: 'خصم الجمعة',
        body: 'على سجاد الصلاة',
        at: now.subtract(const Duration(days: 1)),
      ),
    ]);
    await tester.pumpWidget(harness(const InboxScreen(), kv: kv, overrides: base().cast()));
    await tester.pumpAndSettle();
    expect(find.text('اليوم'), findsOneWidget);
    expect(find.text('أمس'), findsOneWidget);
    await tester.tap(find.text('العروض'));
    await tester.pump();
    expect(find.text('العصر بعد 10 دقائق'), findsNothing);
    await tester.tap(find.text('التحدي'));
    await tester.pump();
    expect(find.text('لا إشعارات هنا'), findsOneWidget);
  });

  testWidgets('prayer screen golden', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1300 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    debugDisableShadows = false;
    await tester.pumpWidget(harness(const Scaffold(body: PrayerScreen()), overrides: base().cast()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    try {
      await expectLater(find.byType(PrayerScreen), matchesGoldenFile('../../goldens/prayer_ar.png'));
    } finally {
      debugDisableShadows = true;
    }
  });
}
