import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:yaqeen/app/router.dart';
import 'package:yaqeen/core/config/env.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/notifications/push_service.dart';
import 'package:yaqeen/core/platform/nfc_service.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/widgets/controls.dart';
import 'package:yaqeen/features/card/domain/medal_nfc.dart';
import 'package:yaqeen/features/card/presentation/card_screen.dart';
import 'package:yaqeen/features/card/presentation/encode_screen.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';

import '../helpers/harness.dart';

/// Stands in for the NFC plugin: scripted chip reads/writes, every call recorded.
class FakeNfcService implements NfcService {
  FakeNfcService({this.state = NfcState.enabled});
  NfcState state;
  final reads = <Object>[]; // NfcRead or NfcException, consumed in order
  final writes = <Object>[]; // NfcWrite or NfcException
  final written = <({String uri, bool lock})>[];
  int cancels = 0;

  @override
  Future<NfcState> availability() async => state;

  @override
  Future<NfcRead> readUri({String? prompt, String? failure}) async {
    final next = reads.isEmpty ? const NfcException(NfcError.timeout) : reads.removeAt(0);
    if (next is NfcException) throw next;
    return next as NfcRead;
  }

  @override
  Future<NfcWrite> writeUri(String uri, {bool lock = false, String? prompt, String? success, String? failure}) async {
    written.add((uri: uri, lock: lock));
    final next = writes.isEmpty ? NfcWrite(uid: '04AABB', verified: true, locked: lock) : writes.removeAt(0);
    if (next is NfcException) throw next;
    return next as NfcWrite;
  }

  @override
  Future<void> cancel() async => cancels++;
}

final token = 'T' * 43;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('chip links: only our own /t/<code>', () {
    const site = 'https://api.yaqin-brand.com';
    test('accepts our site and any https host with exactly /t/<code>', () {
      expect(tagCodeFromChipUri('https://api.yaqin-brand.com/t/AB23CD45', siteUrl: site), 'AB23CD45');
      expect(tagCodeFromChipUri('https://id.yaqin.cards/t/ab23cd45', siteUrl: site), 'AB23CD45');
      expect(tagCodeFromChipUri('http://localhost:4000/t/AB23CD45', siteUrl: 'http://localhost:4000'), 'AB23CD45');
    });
    test('rejects everything else', () {
      for (final bad in [
        'http://evil.test/t/AB23CD45', // plain http off our site
        'https://evil.test:8443/t/AB23CD45',
        'https://evil.test/t/AB23CD45?next=x',
        'https://evil.test/t/AB23CD45#x',
        'https://user@evil.test/t/AB23CD45',
        'https://evil.test/x/t/AB23CD45',
        'https://evil.test/t/AB23CD45/more',
        'https://evil.test/t/AB23-CD45',
        'https://evil.test/t/AB23CD4',
        'https://evil.test/t/AB23CD450',
        'https://evil.test/t/AB01CD45', // 0 and 1 are not in the alphabet
        'https://evil.test/u/ahmed',
        'yaqeen://tag/AB23CD45',
        'javascript:alert(1)',
        'AB23CD45',
        '',
      ]) {
        expect(tagCodeFromChipUri(bad, siteUrl: site), isNull, reason: bad);
      }
    });
    test('the link written for a code', () {
      expect(chipUrl('https://id.test/', 'AB23CD45'), 'https://id.test/t/AB23CD45');
    });
  });

  group('NDEF URI records', () {
    test('https prefix is abbreviated and round-trips', () {
      final p = encodeUriPayload('https://id.test/t/AB23CD45');
      expect(p.first, 0x04);
      expect(utf8.decode(p.sublist(1)), 'id.test/t/AB23CD45');
      expect(decodeUriPayload(p), 'https://id.test/t/AB23CD45');
      expect(encodeUriPayload('https://www.x.test/').first, 0x02);
      expect(encodeUriPayload('custom:x').first, 0x00);
    });
    test('first URI from a message; other records are skipped', () {
      final text = NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: Uint8List.fromList([0x54]),
        identifier: Uint8List(0),
        payload: Uint8List.fromList([2, 0x65, 0x6e, 0x68, 0x69]),
      );
      expect(firstUri([text, uriRecord('https://id.test/t/AB23CD45')]), 'https://id.test/t/AB23CD45');
      expect(firstUri([text]), isNull);
      expect(decodeUriPayload([200, 1]), isNull);
    });
  });

  group('deep links', () {
    test('yaqeen://encode/<token> opens the encoder; anything else goes home', () {
      expect(routeForDeepLink(Uri.parse('yaqeen://encode/$token')), '/encode/$token');
      expect(routeForDeepLink(Uri.parse('yaqeen://encode/short')), '/home');
      expect(routeForDeepLink(Uri.parse('yaqeen://encode/$token/extra')), '/home');
      expect(routeForDeepLink(Uri.parse('yaqeen://encode')), '/home');
    });
    test('custom-scheme links go through the splash first', () {
      final to = Uri.parse(deepLinkRedirect(Uri.parse('yaqeen://encode/$token'))!);
      expect(to.path, '/splash');
      expect(to.queryParameters['to'], '/encode/$token');
      expect(Uri.parse(deepLinkRedirect(Uri.parse('yaqeen://tag/ab23-cd45'))!).queryParameters['to'], '/profile/card?tag=AB23CD45');
      expect(deepLinkRedirect(Uri.parse('/home')), isNull);
      expect(deepLinkRedirect(Uri.parse('/encode/$token')), isNull);
    });
  });

  group('medal scan in «ميدالياتي»', () {
    late List<http.Request> requests;

    Future<List<Override>> overrides(FakeNfcService nfc) async {
      requests = [];
      final secure = MemoryKvStore();
      await secure.write('auth.access', 'token');
      final h = {'content-type': 'application/json'};
      final client = MockClient((req) async {
        requests.add(req);
        final p = req.url.path;
        if (p == '/v1/me/public-profile') {
          return http.Response(
            jsonEncode({
              'published': true,
              'handle': 'ahmed',
              'displayName': 'أحمد',
              'bio': '',
              'links': [],
              'show': {'level': true},
              'theme': 'sky',
              'url': 'https://id.test/u/ahmed',
              'views': 0,
            }),
            200,
            headers: h,
          );
        }
        if (p == '/v1/me/tags' && req.method == 'GET') return http.Response('[]', 200, headers: h);
        if (p == '/v1/me/tags' && req.method == 'POST') {
          final code = (jsonDecode(req.body) as Map)['code'];
          return http.Response(
            jsonEncode({'code': code, 'kind': 'medal', 'url': 'https://id.test/t/$code', 'linkedAt': '2026-10-26T10:00:00Z', 'scans': 0}),
            200,
            headers: h,
          );
        }
        if (p == '/v1/me/journey') return http.Response('{}', 404, headers: h);
        return http.Response('{}', 404, headers: h);
      });
      return [
        initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.google, userId: 'u1', displayName: 'أحمد')),
        tokenStoreProvider.overrideWithValue(TokenStore(secure)),
        apiClientProvider
            .overrideWith((ref) => ApiClient(baseUrl: 'https://api.test', tokens: ref.watch(tokenStoreProvider), client: client)),
        nfcServiceProvider.overrideWithValue(nfc),
      ];
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel(RegExp('^ميدالياتي')).first);
      await settle(tester);
    }

    testWidgets('a medal held to the phone pre-fills its code; the user still confirms', (tester) async {
      tall(tester);
      final nfc = FakeNfcService()..reads.add(const NfcRead(uri: '${Env.siteUrl}/t/AB23CD45', uid: '04A1'));
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(nfc)));
      await settle(tester);
      await openSheet(tester);
      await tester.tap(find.text('قرّب الميدالية من الهاتف'));
      await settle(tester);
      expect(find.widgetWithText(TextField, 'AB23-CD45'), findsOneWidget);
      expect(find.text('وجدنا الميدالية AB23-CD45. اضغط «تفعيل» لتأكيدها.'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty); // nothing activates by itself
      await tester.tap(find.text('تفعيل'));
      await settle(tester);
      final post = requests.singleWhere((r) => r.method == 'POST' && r.url.path == '/v1/me/tags');
      expect(jsonDecode(post.body), {'code': 'AB23CD45'});
    });

    testWidgets("a stranger's tag is refused with a friendly message", (tester) async {
      tall(tester);
      final nfc = FakeNfcService()..reads.add(const NfcRead(uri: 'https://evil.test/t/AB23CD45?x=1'));
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(nfc)));
      await settle(tester);
      await openSheet(tester);
      await tester.tap(find.text('قرّب الميدالية من الهاتف'));
      await settle(tester);
      expect(find.textContaining('هذه ليست ميدالية يقين'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'AB23-CD45'), findsNothing);
    });

    testWidgets('no NFC: no button; NFC off: a hint', (tester) async {
      tall(tester);
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(FakeNfcService(state: NfcState.unsupported))));
      await settle(tester);
      await openSheet(tester);
      expect(find.text('قرّب الميدالية من الهاتف'), findsNothing);
      expect(find.textContaining('فعّل NFC'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(harness(const CardScreen(), overrides: await overrides(FakeNfcService(state: NfcState.disabled))));
      await settle(tester);
      await openSheet(tester);
      expect(find.text('قرّب الميدالية من الهاتف'), findsNothing);
      expect(find.textContaining('فعّل NFC من إعدادات الهاتف'), findsOneWidget);
    });
  });

  group('staff encoding screen', () {
    late List<http.Request> requests;
    late Map<String, String?> encoded;
    var gone = false;
    final codes = ['AB23CD45', 'AB23CD46', 'AB23CD47'];

    Future<List<Override>> overrides(FakeNfcService nfc) async {
      requests = [];
      gone = false;
      encoded = {for (final c in codes) c: null};
      final h = {'content-type': 'application/json'};
      final client = MockClient((req) async {
        requests.add(req);
        Map<String, Object> error(String code) => {
              'error': {'code': code},
            };
        if (gone) return http.Response(jsonEncode(error('not_found')), 404, headers: h);
        if (req.url.path == '/v1/encode/$token' && req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'batch': 'medal-2026-11',
              'kind': 'medal',
              'baseUrl': 'https://id.test',
              'expiresAt': DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String(),
              'codes': [
                for (final c in codes) {'code': c, 'encodedAt': encoded[c]},
              ],
            }),
            200,
            headers: h,
          );
        }
        if (req.url.path == '/v1/encode/$token/written') {
          final code = (jsonDecode(req.body) as Map)['code'] as String;
          if (!codes.contains(code)) return http.Response(jsonEncode(error('code_not_in_batch')), 409, headers: h);
          encoded[code] = '2026-11-01T10:00:00Z';
          final done = encoded.values.where((v) => v != null).length;
          return http.Response(jsonEncode({'code': code, 'encodedAt': encoded[code], 'encoded': done, 'total': 3}), 200, headers: h);
        }
        return http.Response('{}', 404, headers: h);
      });
      return [
        tokenStoreProvider.overrideWithValue(TokenStore(MemoryKvStore())),
        apiClientProvider
            .overrideWith((ref) => ApiClient(baseUrl: 'https://api.test', tokens: ref.watch(tokenStoreProvider), client: client)),
        nfcServiceProvider.overrideWithValue(nfc),
      ];
    }

    List<Map<String, Object?>> posts() =>
        [for (final r in requests.where((r) => r.method == 'POST')) (jsonDecode(r.body) as Map).cast<String, Object?>()];

    testWidgets('writes the next code, unlocked by default, reports it and advances', (tester) async {
      tall(tester);
      final nfc = FakeNfcService();
      await tester.pumpWidget(harness(EncodeScreen(token: token), overrides: await overrides(nfc)));
      await settle(tester);
      expect(find.text('الدفعة medal-2026-11'), findsOneWidget);
      expect(find.text('0 من 3 مُرمّزة'), findsOneWidget);
      expect(find.text('التالية: AB23-CD45'), findsOneWidget);

      await tester.tap(find.text('قرّب شريحة فارغة من الهاتف'));
      await settle(tester);
      expect(nfc.written.single, (uri: 'https://id.test/t/AB23CD45', lock: false));
      expect(posts().single, {'code': 'AB23CD45', 'uid': '04AABB', 'locked': false});
      expect(find.text('1 من 3 مُرمّزة'), findsOneWidget);
      expect(find.text('التالية: AB23-CD46'), findsOneWidget);
      expect(find.text('تمّت AB23-CD45 وتحققنا منها'), findsOneWidget);
    });

    testWidgets('locking is opt-in with a warning; a chosen code is re-encoded', (tester) async {
      tall(tester);
      final nfc = FakeNfcService();
      await tester.pumpWidget(harness(EncodeScreen(token: token), overrides: await overrides(nfc)));
      await settle(tester);
      expect(find.textContaining('القفل مفعّل'), findsNothing);
      await tester.tap(find.byType(YqSwitch));
      await settle(tester);
      expect(find.textContaining('القفل مفعّل'), findsOneWidget);

      await tester.tap(find.text('AB23-CD47'));
      await settle(tester);
      expect(find.text('المختارة: AB23-CD47'), findsOneWidget);
      await tester.tap(find.text('قرّب شريحة فارغة من الهاتف'));
      await settle(tester);
      expect(nfc.written.single, (uri: 'https://id.test/t/AB23CD47', lock: true));
      expect(posts().single, {'code': 'AB23CD47', 'uid': '04AABB', 'locked': true});
      expect(find.text('التالية: AB23-CD45'), findsOneWidget);
    });

    testWidgets('chip errors say why and report nothing; a formatted blank is verified by a second tap', (tester) async {
      tall(tester);
      final nfc = FakeNfcService()
        ..writes.addAll([
          const NfcException(NfcError.readOnly),
          const NfcException(NfcError.tooSmall),
          const NfcException(NfcError.notNdef),
          const NfcWrite(uid: '04CC', verified: false, locked: false),
        ])
        ..reads.add(const NfcRead(uri: 'https://id.test/t/AB23CD45'));
      await tester.pumpWidget(harness(EncodeScreen(token: token), overrides: await overrides(nfc)));
      await settle(tester);
      Future<void> tapWrite() async {
        await tester.tap(find.text('قرّب شريحة فارغة من الهاتف'));
        await settle(tester);
      }

      await tapWrite();
      expect(find.text('الشريحة مقفلة ولا يمكن الكتابة عليها.'), findsOneWidget);
      await tapWrite();
      expect(find.text('الرابط لا يتسع في هذه الشريحة. استخدم شريحة أكبر.'), findsOneWidget);
      await tapWrite();
      expect(find.textContaining('ليست NDEF'), findsOneWidget);
      expect(posts(), isEmpty);
      await tapWrite();
      expect(posts().single, {'code': 'AB23CD45', 'uid': '04CC', 'locked': false});
    });

    testWidgets('a revoked or expired session stops the screen', (tester) async {
      tall(tester);
      final nfc = FakeNfcService();
      await tester.pumpWidget(harness(EncodeScreen(token: token), overrides: await overrides(nfc)));
      await settle(tester);
      gone = true;
      await tester.tap(find.text('قرّب شريحة فارغة من الهاتف'));
      await settle(tester);
      expect(find.textContaining('انتهت جلسة الترميز'), findsOneWidget);
      expect(find.text('قرّب شريحة فارغة من الهاتف'), findsNothing);
    });

    testWidgets('no NFC: the write button stays off and says why', (tester) async {
      tall(tester);
      final nfc = FakeNfcService(state: NfcState.unsupported);
      await tester.pumpWidget(harness(EncodeScreen(token: token), overrides: await overrides(nfc)));
      await settle(tester);
      expect(find.textContaining('هذا الهاتف لا يدعم NFC'), findsOneWidget);
      await tester.tap(find.text('قرّب شريحة فارغة من الهاتف'));
      await settle(tester);
      expect(nfc.written, isEmpty);
    });
  });
}
