import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/widgets/yq_layout.dart';
import 'package:yaqeen/features/calendar/data/hijri_today.dart';
import 'package:yaqeen/features/calendar/domain/hijri_day.dart';
import 'package:yaqeen/features/ramadan/domain/ramadan.dart';
import 'package:yaqeen/features/ramadan/presentation/ramadan_controller.dart';
import 'package:yaqeen/features/ramadan/presentation/ramadan_screen.dart';

import '../../helpers/harness.dart';

/// Fri 12 Feb 2027, 11:00 Cairo = 5 Ramadan 1448 (fasting; iftar later today).
final _now = DateTime.utc(2027, 2, 12, 9);

List<RamadanDay> _month() => [
      for (var i = 0; i < 29; i++) RamadanDay(hijriDay: i + 1, hijriYear: 1448, date: DateTime(2027, 2, 8 + i), weekday: (1 + i) % 7),
    ];

Widget _screen({required String locale, required MemoryKvStore kv, bool bonuses = false}) => harness(
      const RamadanScreen(),
      locale: locale,
      kv: kv,
      skyClock: () => _now,
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        initialConfigProvider.overrideWithValue(
          RemoteConfig(
            features: {...RemoteConfig.defaultFeatures, 'ramadan': true, 'bonuses': bonuses},
            bonusPoints: const {'ramadan_fast': 30},
          ),
        ),
        hijriTodayProvider.overrideWith(
          (ref) async =>
              const HijriDay(gregorian: '2027-02-12', hijriDay: 5, hijriMonth: 9, hijriYear: 1448, monthNameAr: 'رمضان', weekday: 5),
        ),
        ramadanDaysProvider.overrideWith((ref) async => _month()),
      ],
    );

void main() {
  testWidgets('Ramadan: fasting clock, imsakiyya, khatma; ticks are kept on the device', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final kv = MemoryKvStore();
    await tester.pumpWidget(_screen(locale: 'ar', kv: kv, bonuses: true));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('رمضان 1448'), findsOneWidget);
    expect(find.textContaining('اليوم 5 من رمضان'), findsOneWidget);
    expect(find.text('حتى الإفطار'), findsOneWidget);
    expect(find.text('الإمساكية'), findsOneWidget);
    expect(find.text('+30 نقطة'), findsOneWidget); // bonus shown on the fast orb
    // Below the fold: the khatma grid. Tick juz 1 — saved for 1448 on this device.
    await tester.scrollUntilVisible(find.text('ختمة رمضان'), 400, scrollable: find.byType(Scrollable).first);
    final juz1 = find.byWidgetPredicate((w) => w is YqChip && w.label == '1');
    await tester.scrollUntilVisible(juz1, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(juz1.first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(await kv.read('ramadan.log.1448.v1'), contains('"juz":[1]'));
  });

  testWidgets('English, and no bonus label when bonuses are off', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_screen(locale: 'en', kv: MemoryKvStore()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Ramadan 1448'), findsOneWidget);
    expect(find.text('Until iftar'), findsOneWidget);
    expect(find.text('Imsakiyya'), findsOneWidget);
    expect(find.text('+30 pts'), findsNothing);
  });
}
