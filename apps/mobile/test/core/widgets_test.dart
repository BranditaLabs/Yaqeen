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

  testWidgets('a loading button ignores taps and shows a spinner', (tester) async {
    var taps = 0;
    await tester.pumpWidget(harness(Scaffold(body: YqButton(label: 'تأكيد', onPressed: () => taps++, loading: true))));
    await tester.tap(find.byType(YqButton));
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
    await tester.pumpWidget(harness(const Scaffold(body: YqBackButton())));
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await tester.pumpWidget(harness(const Scaffold(body: YqBackButton()), locale: 'en'));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
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
      tester.view.physicalSize = const Size(390 * 3, 1500 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness(GalleryScreen(now: DateTime(2026, 10, 20, 12)), locale: locale));
      await tester.pump(const Duration(milliseconds: 600));
      try {
        await expectLater(find.byType(GalleryScreen), matchesGoldenFile('../goldens/gallery_$locale.png'));
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
