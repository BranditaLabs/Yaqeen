import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_button.dart';
import 'package:yaqeen/core/widgets/yq_countdown.dart';
import 'package:yaqeen/core/widgets/yq_icon.dart';
import 'package:yaqeen/core/widgets/yq_layout.dart';
import 'package:yaqeen/core/widgets/yq_states.dart';
import 'package:yaqeen/features/debug/gallery_screen.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  group('YqButton loading', () {
    Widget button({required bool loading, YqButtonKind kind = YqButtonKind.primary, VoidCallback? onPressed}) => Center(
          child: SizedBox(
            width: 300,
            child: switch (kind) {
              YqButtonKind.primary => YqButton(label: 'تأكيد', onPressed: onPressed ?? () {}, loading: loading),
              YqButtonKind.secondary => YqButton.secondary(label: 'تأكيد', onPressed: onPressed ?? () {}, loading: loading),
              YqButtonKind.text => YqButton.text(label: 'تأكيد', onPressed: onPressed ?? () {}, loading: loading),
            },
          ),
        );

    testWidgets('ignores taps, keeps its label and shows no spinner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(harness(Scaffold(body: button(loading: true, onPressed: () => taps++))));
      await tester.tap(find.byType(YqButton), warnIfMissed: false);
      expect(taps, 0);
      expect(find.text('تأكيد'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // The label shimmers under one mask.
      expect(find.descendant(of: find.byType(YqButton), matching: find.byType(ShaderMask)), findsOneWidget);
    });

    for (final kind in YqButtonKind.values) {
      testWidgets('keeps its exact size (${kind.name})', (tester) async {
        await tester.pumpWidget(harness(Scaffold(body: button(loading: false, kind: kind))));
        final idle = tester.getSize(find.byType(YqButton));
        await tester.pumpWidget(harness(Scaffold(body: button(loading: true, kind: kind))));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getSize(find.byType(YqButton)), idle);
      });
    }

    testWidgets('announces the label with «جارٍ التنفيذ», disabled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(harness(Scaffold(body: button(loading: true))));
      expect(
        tester.getSemantics(find.byType(YqButton)),
        isSemantics(label: 'تأكيد', value: 'جارٍ التنفيذ', isButton: true, hasEnabledState: true, isEnabled: false),
      );
      await tester.pumpWidget(harness(Scaffold(body: button(loading: true)), locale: 'en'));
      expect(tester.getSemantics(find.byType(YqButton)), isSemantics(label: 'تأكيد', value: 'Working'));
      await tester.pumpWidget(harness(Scaffold(body: button(loading: false))));
      expect(tester.getSemantics(find.byType(YqButton)), isNot(isSemantics(value: 'جارٍ التنفيذ')));
      handle.dispose();
    });

    testWidgets('is static at 60% under reduce-motion', (tester) async {
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(body: button(loading: true)),
            ),
          ),
        ),
      );
      // Nothing keeps ticking: the frame settles.
      await tester.pumpAndSettle();
      final inButton = find.descendant(of: find.byType(YqButton), matching: find.byType(Opacity));
      expect(inButton, findsOneWidget);
      expect(tester.widget<Opacity>(inButton).opacity, 0.6);
      expect(find.descendant(of: find.byType(YqButton), matching: find.byType(ShaderMask)), findsNothing);
      expect(find.text('تأكيد'), findsOneWidget);
    });
  });

  testWidgets('a skeleton reads «جارٍ التحميل» to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(harness(const Scaffold(body: YqSkeleton(child: YqSkeletonCard(height: 80)))));
    expect(find.bySemanticsLabel('جارٍ التحميل'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('error state shows the spec copy and retries', (tester) async {
    var retried = false;
    await tester.pumpWidget(harness(Scaffold(body: YqErrorState(onRetry: () => retried = true))));
    expect(find.text('تعذّر التحميل. تحقق من الاتصال.'), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    expect(retried, isTrue);
  });

  testWidgets('offline banner copy, and nothing when online', (tester) async {
    await tester.pumpWidget(harness(const Scaffold(body: YqOfflineBanner(offline: true))));
    expect(find.text('أنت غير متصل · نعمل بما على جهازك'), findsOneWidget);
    await tester.pumpWidget(harness(const Scaffold(body: YqOfflineBanner(offline: false))));
    await tester.pumpAndSettle();
    expect(find.textContaining('غير متصل'), findsNothing);
  });

  testWidgets('empty state and stepper expose readable semantics', (tester) async {
    await tester.pumpWidget(
      harness(
        const Scaffold(
          body: Column(
            children: [
              YqEmptyState(icon: YqIcons.bookmark, title: 'لا توجد علامات بعد', hint: 'اضغط مطولاً'),
              YqStepper(step: 1, semanticLabel: 'الخطوة 1 من 4'),
            ],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('الخطوة 1 من 4'), findsOneWidget);
    expect(find.text('لا توجد علامات بعد'), findsOneWidget);
  });

  testWidgets('back chevron points right in RTL and left in LTR', (tester) async {
    // One glyph in both languages: Flutter mirrors `matchTextDirection` icons in RTL itself, so
    // picking the right-pointing glyph by hand in Arabic flipped it twice (pointing the wrong way).
    final mirror = find.descendant(of: find.byType(Icon), matching: find.byType(Transform));
    await tester.pumpWidget(harness(const Scaffold(body: YqBackButton())));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(mirror, findsOneWidget); // drawn pointing right in Arabic
    await tester.pumpWidget(harness(const Scaffold(body: YqBackButton()), locale: 'en'));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    expect(mirror, findsNothing); // pointing left in English
  });

  testWidgets('toast appears and goes away', (tester) async {
    await tester.pumpWidget(
      harness(Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => YqToast.show(c, 'حُفظ'), child: const Text('x'))))),
    );
    await tester.tap(find.text('x'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('حُفظ'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('حُفظ'), findsNothing);
  });

  test('countdown format never goes negative', () {
    expect(YqCountdown.format(const Duration(hours: 1, minutes: 24, seconds: 10)), '01:24:10');
    expect(YqCountdown.format(const Duration(seconds: -5)), '00:00:00');
  });

  for (final locale in ['ar', 'en']) {
    testWidgets('gallery golden ($locale)', (tester) async {
      debugDisableShadows = false; // real soft shadows in goldens (reset before the test ends)
      tester.view.physicalSize = const Size(390 * 3, 2300 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(GalleryScreen(now: DateTime(2026, 10, 20, 12)), locale: locale));
      // Decode the bundled preset avatars so the shot shows them, not their loading discs.
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pump(const Duration(milliseconds: 600));
      try {
        await expectLater(find.byType(GalleryScreen), matchesGoldenFile('../goldens/gallery_$locale.png'));
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
