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
import 'package:yaqeen/features/azkar/domain/azkar_progress.dart';
import 'package:yaqeen/features/azkar/presentation/azkar_controller.dart';
import 'package:yaqeen/features/azkar/presentation/azkar_screen.dart';
import 'package:yaqeen/features/content/domain/content_item.dart';
import 'package:yaqeen/features/duas/presentation/duas_screen.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

// Placeholders only — religious text comes from reviewed content (rule 9).
Map<String, Object?> item(String id, String type, String category, {int repeat = 1, int order = 0, bool featured = false}) => {
      'id': id,
      'type': type,
      'category': category,
      'title': '[عنوان $id]',
      'textAr': '[نص $id]',
      'translationEn': null,
      'source': '[مصدر $id]',
      'virtue': type == 'zikr' ? '[فضل $id]' : null,
      'repeatCount': repeat,
      'sortOrder': order,
      'featured': featured,
      'version': 1,
      'updatedAt': '2026-10-01T00:00:00Z',
    };

final payload = [
  item('m1', 'zikr', 'morning', repeat: 3, order: 1),
  item('m2', 'zikr', 'morning', order: 2),
  item('e1', 'zikr', 'evening'),
  item('d1', 'dua', 'travel', featured: true),
  item('d2', 'dua', 'travel'),
  item('d3', 'dua', 'mosque'),
  {'id': 'bad', 'type': 'dua', 'category': 'travel', 'textAr': '[بلا مصدر]', 'source': ''},
];

http.Client server() => MockClient((req) async {
      if (req.url.path == '/v1/content') {
        return http.Response.bytes(utf8.encode(jsonEncode(payload)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('{}', 404);
    });

List<Override> base() => [
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 20, 6)),
      apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'https://api.test', tokens: TokenStore(MemoryKvStore()), client: server())),
    ];

void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  group('domain', () {
    final lib = ContentLibrary(payload.map(ContentItem.tryParse).whereType<ContentItem>().toList());

    test('items without a source are never shown; sets ordered by sortOrder', () {
      expect(lib.items.map((i) => i.id), isNot(contains('bad')));
      expect(lib.azkar(ZikrSet.morning).map((i) => i.id), ['m1', 'm2']);
      expect(lib.duas(DuaCategory.travel), hasLength(2));
    });

    test('dua of the day is deterministic and prefers the featured pool', () {
      expect(lib.duaOfTheDay('2026-10-20')!.id, 'd1');
      expect(lib.duaOfTheDay('2026-10-21')!.id, 'd1');
      expect(ContentLibrary(const []).duaOfTheDay('2026-10-20'), isNull);
    });

    test('taps cap at the repeat count; a set completes when every item is done', () {
      final set = lib.azkar(ZikrSet.morning);
      var d = const AzkarDay(date: '2026-10-20');
      for (var i = 0; i < 5; i++) {
        d = d.tap(set[0]);
      }
      expect(d.countOf(set[0]), 3);
      expect(d.doneSet(set), isFalse);
      d = d.tap(set[1]);
      expect(d.doneSet(set), isTrue);
      expect(AzkarDay.forToday(d, '2026-10-21').counts, isEmpty);
      expect(AzkarDay.tryParse(jsonDecode(jsonEncode(d.toJson())))!.countOf(set[0]), 3);
    });
  });

  test('controller: rapid taps all count, and progress survives a restart', () async {
    final kv = MemoryKvStore();
    ProviderContainer make() => ProviderContainer(
          overrides: [kvStoreProvider.overrideWithValue(kv), secureStoreProvider.overrideWithValue(MemoryKvStore()), ...base()],
        );
    final lib = ContentLibrary(payload.map(ContentItem.tryParse).whereType<ContentItem>().toList());
    final set = lib.azkar(ZikrSet.morning);
    var c = make();
    final ctl = c.read(azkarControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 3; i++) {
      ctl.tap(set[0], set: set, kind: ZikrSet.morning);
    }
    expect(c.read(azkarControllerProvider).countOf(set[0]), 3);
    c.dispose(); // flushes the debounced write
    await Future<void>.delayed(const Duration(milliseconds: 10));
    c = make();
    c.read(azkarControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(c.read(azkarControllerProvider).countOf(set[0]), 3);
    c.dispose();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('azkar: empty until content syncs, then counts on the card and advances', (tester) async {
    phone(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(const AzkarScreen(initial: ZikrSet.morning), overrides: base()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('أذكار الصباح'), findsWidgets);
    expect(find.text('الذكر 1 من 2'), findsOneWidget);
    expect(find.text('[نص m1]'), findsOneWidget);
    expect(find.text('[فضل m1] · [مصدر m1]'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('[نص m1]'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('تقبّل الله · انتقل للذكر التالي'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('الذكر 2 من 2'), findsOneWidget);
    await tester.tap(find.text('[نص m2]'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('تقبّل الله، اكتملت الأذكار'), findsOneWidget);
  });

  testWidgets('duas: dua of the day with source, sections with counts, favourites', (tester) async {
    phone(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(harness(const DuasScreen(), overrides: base()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('دعاء اليوم'), findsOneWidget);
    expect(find.text('[نص d1]'), findsOneWidget);
    expect(find.text('[مصدر d1]'), findsOneWidget);
    expect(find.text('السفر'), findsOneWidget);
    expect(find.text('دعاءان'), findsOneWidget);
    expect(find.text('دعاء واحد'), findsOneWidget);
    expect(find.text('لا يوجد بعد'), findsOneWidget);
    await tester.tap(find.byTooltip('إضافة إلى المفضلة'));
    await tester.pump();
    expect(find.byTooltip('إزالة من المفضلة'), findsOneWidget);
    expect(find.text('1 محفوظ'), findsOneWidget);
  });
}
