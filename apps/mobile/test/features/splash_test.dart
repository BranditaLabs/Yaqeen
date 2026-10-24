import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yaqeen/core/widgets/yq_logo.dart';
import 'package:yaqeen/features/onboarding/presentation/splash_screen.dart';

void main() {
  testWidgets('light splash shows the logo mark only and moves on', (tester) async {
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen(next: '/next', hold: Duration(milliseconds: 300))),
        GoRoute(path: '/next', builder: (_, __) => const Scaffold(body: Text('next'))),
      ],
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    // Logo mark only (navy wings + gold diamond layers) — no wordmark, no typeset name.
    final assets = tester.widgetList<Image>(find.byType(Image)).map((i) => (i.image as AssetImage).assetName).toSet();
    expect(assets, containsAll(['assets/brand/splash-wings-navy.png', 'assets/brand/splash-diamond-gold.png']));
    expect(assets.any((a) => a.contains('wordmark') || a.contains('lockup')), isFalse);
    expect(find.text('يقين'), findsNothing);
    expect(find.bySemanticsLabel('شعار يقين'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('next'), findsOneWidget);
  });

  test('logo picks the right file per variant and tone', () {
    expect(const YqLogo(variant: YqLogoVariant.mark).asset, 'assets/brand/mark-navy.png');
    expect(const YqLogo(variant: YqLogoVariant.mark, tone: YqLogoTone.onDark).asset, 'assets/brand/mark-white.png');
    expect(const YqLogo(variant: YqLogoVariant.horizontal).asset, 'assets/brand/lockup-horizontal-navy.png');
  });
}
