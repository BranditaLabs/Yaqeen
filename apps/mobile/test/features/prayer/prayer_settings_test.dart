import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/format.dart';
import 'package:yaqeen/core/notifications/local_notifier.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/platform/location_service.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/calendar/data/hijri_today.dart';
import 'package:yaqeen/features/calendar/domain/hijri_day.dart';
import 'package:yaqeen/features/notifications/presentation/notification_settings_screen.dart';
import 'package:yaqeen/features/prayer/domain/prayer_calculator.dart';
import 'package:yaqeen/features/prayer/presentation/city_picker_sheet.dart';
import 'package:yaqeen/features/prayer/presentation/prayer_screen.dart';
import 'package:yaqeen/features/prayer/presentation/prayer_settings_screen.dart';
import 'package:yaqeen/features/ramadan/domain/ramadan.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  final now = DateTime.utc(2026, 10, 20, 12, 0);
  const cairo = AppSettings(place: Place.cairo);
  const riyadh = Place(nameAr: 'الرياض', nameEn: 'Riyadh', country: 'SA', lat: 24.7136, lng: 46.6753, timezone: 'Asia/Riyadh');
  const alex = Place(nameAr: 'الإسكندرية', nameEn: 'Alexandria', country: 'EG', lat: 31.2, lng: 29.92, timezone: 'Africa/Cairo');
  const hijri = HijriDay(gregorian: '2026-10-20', hijriDay: 8, hijriMonth: 5, hijriYear: 1448, monthNameAr: 'جمادى الأولى', weekday: 2);

  group('logic', () {
    test('Fajr adhan has its own sound and Android channel', () {
      expect(PluginLocalNotifier.adhanSoundFor('makkah', Prayer.fajr, bundled: true), 'adhan_makkah_fajr');
      expect(PluginLocalNotifier.adhanSoundFor('makkah', Prayer.dhuhr, bundled: true), 'adhan_makkah');
      expect(PluginLocalNotifier.adhanSoundFor('makkah', Prayer.fajr, bundled: false), isNull);
    });

    test('compass: magnetic headings become true headings (Cairo ≈ +4.5°)', () async {
      final out = await trueHeadings(
        Stream.fromIterable(const [HeadingReading(100, accuracy: 10), HeadingReading(358)]),
        Future.value(4.5),
      ).toList();
      expect(out.map((h) => h.degrees), [104.5, closeTo(2.5, 1e-9)]);
      expect(out.first.accuracy, 10);
    });

    test('compass: unknown declination (iOS true heading, no answer) passes headings through', () async {
      expect((await trueHeadings(Stream.value(const HeadingReading(136)), Future.value(null)).toList()).single.degrees, 136);
      expect(
        (await trueHeadings(Stream.value(const HeadingReading(136)), Future<double?>.error(Exception('no channel'))).toList()).single.degrees,
        136,
      );
    });

    test('hijri label follows the locale (widget line in English)', () {
      expect(hijri.label('ar'), '8 جمادى الأولى 1448');
      expect(hijri.label('en'), '8 Jumada al-Ula 1448');
    });

    test('moving country offers its recommended method; same country does not', () {
      expect(methodToOffer(cairo, riyadh), CalcMethod.ummAlQura);
      expect(methodToOffer(cairo, alex), isNull);
      expect(methodToOffer(cairo.copyWith(method: CalcMethod.ummAlQura), riyadh), isNull);
    });

    test('Ramadan dates from the imsakiyya', () {
      final days = [RamadanDay(hijriDay: 1, hijriYear: 1448, date: DateTime(2027, 2, 8), weekday: 1)];
      expect(isRamadanDate(DateTime(2027, 2, 8), days), isTrue);
      expect(isRamadanDate(DateTime(2027, 2, 7), days), isFalse);
    });

    test('per-prayer adjustments move one prayer and stay within ±30', () {
      final a = PrayerSettingsScreen.adjusted(const PrayerAdjustments(isha: 30), PrayerName.isha, 1);
      expect(a.isha, 30);
      final b = PrayerSettingsScreen.adjusted(a, PrayerName.fajr, -1);
      expect((b.fajr, b.isha, b.dhuhr), (-1, 30, 0));
    });
  });

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 3200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('prayer settings: method, Asr school, adjustment and Hijri offset are saved', (tester) async {
    tall(tester);
    final kv = MemoryKvStore();
    await tester.pumpWidget(
      harness(
        const PrayerSettingsScreen(),
        kv: kv,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          initialSettingsProvider.overrideWithValue(cairo),
          hijriTodayProvider.overrideWith((ref) async => hijri),
        ],
      ),
    );
    await tester.pump();
    // Every method is offered, the recommended one first.
    expect(find.text('رئاسة الشؤون الدينية التركية'), findsOneWidget);
    expect(find.text('الموصى بها لموقعك'), findsOneWidget);
    expect(find.text('اليوم 8 جمادى الأولى 1448'), findsOneWidget);

    await tester.tap(find.text('أم القرى'));
    await tester.pump();
    await tester.tap(find.text('الحنفي'));
    await tester.pump();
    await tester.tap(find.byTooltip('تأخير الفجر دقيقة'));
    await tester.pump();
    await tester.tap(find.text('+1 يوم'));
    await tester.pump();
    await tester.tap(find.text('منتصف الليل'));
    await tester.pump();

    final saved = kv.data['settings.v1']!;
    expect(saved, contains('"method":"umm_al_qura"'));
    expect(saved, contains('"asr":"hanafi"'));
    expect(saved, contains('"hijriOffsetDays":1'));
    expect(saved, contains('"highLatitude":"middleOfTheNight"'));
    expect(saved, contains('"fajr":1'));
    expect(find.text('+1 د'), findsOneWidget);
  });

  testWidgets('today\'s reminders show the azkar when they fire (30 min after Fajr / Asr)', (tester) async {
    tall(tester);
    final container = ProviderContainer(overrides: [initialSettingsProvider.overrideWithValue(cairo)]);
    addTearDown(container.dispose);
    final repo = container.read(prayerRepositoryProvider);
    final times = repo.forDate(cairo, repo.today(cairo, now));
    String at(DateTime utc) => YqFormat.time(repo.local(cairo, utc), 'ar');
    await tester.pumpWidget(
      harness(
        const NotificationSettingsScreen(),
        overrides: [
          clockProvider.overrideWithValue(() => now),
          initialSettingsProvider.overrideWithValue(cairo),
          localNotificationsProvider.overrideWithValue(NoopLocalNotificationScheduler()),
        ],
      ),
    );
    await tester.pump();
    expect(find.text(at(times.fajr.add(const Duration(minutes: 30)))), findsWidgets);
    expect(find.text(at(times.asr.add(const Duration(minutes: 30)))), findsWidgets);
  });

  testWidgets('denied notifications: «افتح الإعدادات» opens the OS notification settings', (tester) async {
    tall(tester);
    final device = FakeDeviceServices();
    await tester.pumpWidget(
      harness(
        const NotificationSettingsScreen(),
        overrides: [
          clockProvider.overrideWithValue(() => now),
          initialSettingsProvider.overrideWithValue(cairo),
          localNotificationsProvider.overrideWithValue(NoopLocalNotificationScheduler()..permission = false),
          deviceServicesProvider.overrideWithValue(device),
        ],
      ),
    );
    await tester.pump();
    // Sunrise is silent by default: turning it on asks for the permission first.
    await tester.tap(find.bySemanticsLabel('الشروق، الوضع الحالي صامت. المس للتغيير'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افتح الإعدادات'));
    await tester.pumpAndSettle();
    expect(device.notificationSettingsOpened, 1);
    expect(device.opened, isEmpty);
  });

  testWidgets('prayer screen links to the prayer settings', (tester) async {
    tall(tester);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: PrayerScreen()),
        overrides: [clockProvider.overrideWithValue(() => now), initialSettingsProvider.overrideWithValue(cairo)],
      ),
    );
    await tester.pump();
    expect(find.text('إعدادات المواقيت'), findsOneWidget);
  });
}
