import 'dart:convert';
import 'dart:ui';

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/platform/home_widget_publisher.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/notifications/presentation/reminders_controller.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/features/home/data/widget_snapshot.dart';
import 'package:yaqeen/features/prayer/data/prayer_repository.dart';
import 'package:yaqeen/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(Zoned.ensureInitialized);

  Map<String, dynamic> build({String locale = 'ar', int pages = 2, int? ramadanDay}) => jsonDecode(
        WidgetSnapshot.build(
          settings: AppSettings(locale: locale),
          prayers: const PrayerRepository(),
          now: DateTime.utc(2026, 10, 23, 9), // Friday, 12:00 Cairo
          t: lookupAppLocalizations(Locale(locale)),
          hijri: '12 جمادى الأولى 1448',
          wirdPages: pages,
          ramadanDay: ramadanDay,
        ),
      ) as Map<String, dynamic>;

  test('a week of the five prayers, in order, localised and pre-formatted', () {
    final j = build();
    final prayers = (j['prayers'] as List).cast<Map<String, dynamic>>();
    expect(prayers.length, 7 * 5);
    final at = prayers.map((p) => p['at'] as int).toList();
    expect(at, [...at]..sort());
    expect(prayers.first['key'], 'fajr');
    // Friday's Dhuhr is Jumu'ah; times use Western digits.
    expect(prayers[1]['label'], 'الجمعة');
    expect(prayers.every((p) => RegExp(r'^\d{1,2}:\d{2}').hasMatch(p['time'] as String)), isTrue);
    expect(j['nextLabel'], 'الصلاة القادمة');
    expect(j['hijri'], '12 جمادى الأولى 1448');
    expect(j['rtl'], isTrue);
    expect(j['ramadan'], isNull);
  });

  test('wird progress is clamped to the goal; Ramadan day and English labels', () {
    final j = build(locale: 'en', pages: 99, ramadanDay: 5);
    final wird = j['wird'] as Map<String, dynamic>;
    expect(wird['pages'], wird['goal']);
    expect(j['ramadan'], 'Ramadan · day 5');
    expect(j['rtl'], isFalse);
    expect(j['staleText'], 'Open Yaqeen to refresh the times');
  });

  test('a re-plan publishes the snapshot to the widget, offline included', () async {
    final publisher = NoopHomeWidgetPublisher();
    final kv = MemoryKvStore();
    final container = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
        secureStoreProvider.overrideWithValue(MemoryKvStore()),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 23, 9)),
        homeWidgetPublisherProvider.overrideWithValue(publisher),
        // Offline: the Hijri line is simply absent.
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(kv), client: MockClient((_) async => throw const SocketException('offline'))),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(remindersControllerProvider.notifier).replan();
    final j = jsonDecode(publisher.last!) as Map<String, dynamic>;
    expect((j['prayers'] as List).length, 35);
    expect(j['hijri'], isNull);
  });
}
