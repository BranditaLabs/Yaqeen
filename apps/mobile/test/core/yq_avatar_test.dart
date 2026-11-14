import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yaqeen/core/design/motion.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/network/api_client.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/theme/tokens.dart';
import 'package:yaqeen/core/widgets/yq_avatar.dart';
import 'package:yaqeen/core/widgets/yq_once.dart';
import 'package:yaqeen/core/widgets/yq_ring.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/profile/data/profile_repository.dart';
import 'package:yaqeen/features/profile/domain/avatar.dart';
import 'package:yaqeen/features/profile/domain/me_profile.dart';
import 'package:yaqeen/features/profile/presentation/me_avatar.dart';

import '../helpers/harness.dart';

void main() {
  setUp(YqAvatar.clearMemoryCache);

  testWidgets('a preset draws the bundled art with «صورة {name}» semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(harness(const Center(child: YqAvatar(avatar: PresetAvatar('m03'), size: 64, name: 'سارة'))));
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).imageProvider, const AssetImage('assets/avatars/m03.webp'));
    expect(find.bySemanticsLabel('صورة سارة'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the initial: the first letter in ink on ice, labelled as an initial (English too)', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(harness(const Center(child: YqAvatar(avatar: InitialAvatar(), size: 48, name: 'Omar Ali')), locale: 'en'));
    expect(find.text('O'), findsOneWidget);
    expect(tester.widget<Text>(find.text('O')).style!.color, YqColors.ink);
    expect(find.bySemanticsLabel("Omar Ali's initial"), findsOneWidget);
    handle.dispose();
  });

  testWidgets("the caller's own photo (authed path) loads through ApiClient.getBytes, once", (tester) async {
    final calls = <String>[];
    final api = ApiClient(
      baseUrl: 'https://api.test',
      tokens: TokenStore(MemoryKvStore()),
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path} ${req.headers['Authorization'] ?? ''}');
        return http.Response.bytes(base64Decode(_png1x1), 200);
      }),
    );
    const own = PhotoAvatar(id: 'p1', url: '/v1/me/avatar/photo/256', smallUrl: '/v1/me/avatar/photo/96');
    final widget = harness(
      const Column(children: [YqAvatar(avatar: own, size: 40, name: 'A'), YqAvatar(avatar: own, size: 40, name: 'A')]),
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    await tester.pumpWidget(widget);
    // Skeleton circle until the bytes arrive.
    expect(find.byType(Image), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(calls.where((c) => c.startsWith('GET /v1/me/avatar/photo/96')), hasLength(greaterThanOrEqualTo(1)));
    expect(find.byType(Image), findsNWidgets(2));
    // A second avatar later reuses the in-memory copy.
    final before = calls.length;
    await tester.pumpWidget(harness(const YqAvatar(avatar: own, size: 40), overrides: [apiClientProvider.overrideWithValue(api)]));
    await tester.pump();
    expect(calls.length, before);
  });

  group('YqLevelAvatar', () {
    testWidgets('lapis ring by default with the level semantics; the numeral sits at the bottom end (RTL)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        harness(
          const Center(
            child: YqLevelAvatar(avatar: InitialAvatar(), level: 3, progress: 0.4, size: 48, showLevel: true, name: 'سارة', levelName: 'مواظب'),
          ),
        ),
      );
      final ring = tester.widget<YqRing>(find.byType(YqRing));
      expect(ring.color, YqColors.lapis);
      expect(ring.glint, isFalse);
      expect(find.bySemanticsLabel('سارة، المستوى 3 · مواظب، 40%'), findsOneWidget);
      final badge = find.text('3');
      expect(badge, findsOneWidget);
      // RTL: bottom end = the left edge.
      final box = tester.getRect(find.byType(YqLevelAvatar));
      expect(tester.getCenter(badge).dx, lessThan(box.center.dx));
      handle.dispose();
    });

    testWidgets('a level just reached: gold with a one-shot glint and pulse; reduce-motion skips both', (tester) async {
      await tester.pumpWidget(
        harness(const Center(child: YqLevelAvatar(avatar: InitialAvatar(), level: 6, progress: 1, achieved: true, glint: true))),
      );
      final ring = tester.widget<YqRing>(find.byType(YqRing));
      expect(ring.color, YqColors.gold);
      expect(ring.glint, isTrue);
      await tester.pump();
      // The ring's own painter plus the glint's light.
      expect(find.descendant(of: find.byType(YqRing), matching: find.byType(CustomPaint)), findsNWidgets(2));
      expect(tester.widget<YqPulse>(find.byType(YqPulse)).active, isTrue);
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const Center(child: YqLevelAvatar(avatar: InitialAvatar(), level: 6, progress: 1, achieved: true, glint: true)),
            ),
          ),
        ),
      );
      expect(find.descendant(of: find.byType(YqRing), matching: find.byType(CustomPaint)), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('by default a top-level gold ring stays quiet (no glint, no pulse on every visit)', (tester) async {
      await tester.pumpWidget(
        harness(const Center(child: YqLevelAvatar(avatar: InitialAvatar(), level: 6, progress: 1, achieved: true))),
      );
      await tester.pump();
      expect(tester.widget<YqRing>(find.byType(YqRing)).color, YqColors.gold);
      expect(tester.widget<YqRing>(find.byType(YqRing)).glint, isFalse);
      expect(tester.widget<YqPulse>(find.byType(YqPulse)).active, isFalse);
      expect(find.descendant(of: find.byType(YqRing), matching: find.byType(CustomPaint)), findsOneWidget);
    });

    testWidgets('a new picture cross-fades in from 0.94 without redrawing the ring', (tester) async {
      Widget a(AvatarRef ref) => harness(Center(child: YqLevelAvatar(avatar: ref, level: 2, progress: 0.5, drawIn: Motion.ringDraw)));
      await tester.pumpWidget(a(const InitialAvatar()));
      await tester.pumpAndSettle();
      final ringState = tester.state(find.byType(YqRing));
      await tester.pumpWidget(a(const PresetAvatar('m01')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(YqAvatar), findsNWidgets(2)); // old fading out, new fading in
      final scale = tester.widget<ScaleTransition>(
        find.ancestor(of: find.byType(YqAvatar).last, matching: find.byType(ScaleTransition)).first,
      );
      expect(scale.scale.value, inInclusiveRange(0.94, 1.0));
      await tester.pumpAndSettle();
      expect(find.byType(YqAvatar), findsOneWidget);
      expect(tester.state(find.byType(YqRing)), same(ringState)); // the ring kept its state
    });
  });

  group('MeAvatar', () {
    testWidgets('a guest has no ring', (tester) async {
      await tester.pumpWidget(
        harness(
          const Center(child: MeAvatar(size: 48, ring: true)),
          overrides: [initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.guest, pendingServer: true))],
        ),
      );
      await tester.pump();
      expect(find.byType(YqRing), findsNothing);
      expect(find.byType(YqAvatar), findsOneWidget);
    });

    testWidgets('a signed-in account shows the cached level ring without waiting on the network', (tester) async {
      final kv = MemoryKvStore();
      final cached = MeProfile.fromJson(
        jsonDecode('{"displayName":"سارة","level":{"level":2,"nameAr":"على الطريق","nameEn":"On the path","progress":0.5,"nextAt":2000}}')
            as Map<String, dynamic>,
      );
      await kv.write(ProfileRepository.meKey, jsonEncode(cached.toJson()));
      final failing = ApiClient(
        baseUrl: 'https://api.test',
        tokens: TokenStore(MemoryKvStore()),
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await tester.pumpWidget(
        harness(
          const Center(child: MeAvatar(size: 48, ring: true, showLevel: true)),
          kv: kv,
          overrides: [
            apiClientProvider.overrideWithValue(failing),
            initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.google, userId: 'u1', displayName: 'سارة')),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(YqRing), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });
}

/// A 1×1 transparent PNG.
const _png1x1 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
