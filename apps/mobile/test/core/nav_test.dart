import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/app/router.dart';
import 'package:yaqeen/app/shell.dart';
import 'package:yaqeen/core/design/living_sky.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/features/quran/domain/quran_data.dart';
import 'package:yaqeen/main.dart';
import 'package:yaqeen/core/widgets/floating_tab_bar.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_icon.dart';

import '../helpers/harness.dart';

const _labels = {
  'ar': ['الرئيسية', 'القرآن', 'الصلاة', 'التحدي', 'حسابي'],
  'en': ['Home', 'Quran', 'Prayer', 'Challenge', 'Profile'],
};

List<YqTab> _tabs(String locale) {
  final l = _labels[locale]!;
  return [
    YqTab(icon: YqIcons.home, label: l[0]),
    YqTab(icon: YqIcons.quran, label: l[1]),
    YqTab(icon: YqIcons.prayer, label: l[2]),
    YqTab(icon: YqIcons.challenge, label: l[3]),
    YqTab.avatar(initial: 'أ', label: l[4]),
  ];
}

Widget _bar(String locale, int index, ValueChanged<int> onSelect, {double width = 350}) => Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: width, child: FloatingTabBar(currentIndex: index, onSelect: onSelect, tabs: _tabs(locale))),
      ),
    );

/// The rect of the tab whose label is [label] (its semantics node covers the whole slot).
Rect _slot(WidgetTester tester, String label) => tester.getRect(find.bySemanticsLabel(label));

/// The pill under the active tab.
Rect _pill(WidgetTester tester) => tester.getRect(find.byType(PositionedDirectional).first);

void main() {
  setUp(() => YqGlassConfig.enableBlur = false);

  for (final locale in ['ar', 'en']) {
    final l = _labels[locale]!;

    testWidgets('dock: five equal slots in reading order, pill glides under the active tab ($locale)', (tester) async {
      final semantics = tester.ensureSemantics();
      var index = 0;
      await tester
          .pumpWidget(harness(StatefulBuilder(builder: (c, set) => _bar(locale, index, (i) => set(() => index = i))), locale: locale));
      await tester.pumpAndSettle();

      // Symmetric: every slot has the same width, and the row is centred in the capsule.
      final slots = [for (final label in l) _slot(tester, label)];
      for (final r in slots) {
        expect(r.width, moreOrLessEquals(slots.first.width, epsilon: 0.01));
        expect(r.height, greaterThanOrEqualTo(44)); // touch target
      }
      final bar = tester.getRect(find.byType(FloatingTabBar));
      final row = slots.reduce((a, b) => a.expandToInclude(b));
      expect(row.left - bar.left, moreOrLessEquals(bar.right - row.right, epsilon: 0.01));
      // Reading order: the first tab is at the start edge (right in Arabic).
      expect(locale == 'ar' ? slots.first.center.dx > slots.last.center.dx : slots.first.center.dx < slots.last.center.dx, isTrue);

      // Every label is always visible; the pill starts under Home.
      for (final label in l) {
        expect(find.text(label), findsOneWidget);
      }
      expect((_pill(tester).center.dx - slots[0].center.dx).abs(), lessThan(0.5));
      final home = tester.getSemantics(find.bySemanticsLabel(l[0]));
      expect(home, isSemantics(label: l[0], isButton: true, isSelected: true, hasTapAction: true));

      await tester.tap(find.text(l[2]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // mid-glide: between the two tabs, nothing overflows
      expect(tester.takeException(), isNull);
      final mid = _pill(tester).center.dx;
      expect(mid, inExclusiveRange(math.min(slots[0].center.dx, slots[2].center.dx), math.max(slots[0].center.dx, slots[2].center.dx)));
      await tester.pumpAndSettle();
      expect(index, 2);
      expect((_pill(tester).center.dx - slots[2].center.dx).abs(), lessThan(0.5));
      expect(tester.getSemantics(find.bySemanticsLabel(l[2])), isSemantics(isSelected: true));
      expect(tester.getSemantics(find.bySemanticsLabel(l[0])), isSemantics(isSelected: false));

      // The profile avatar is a slot like the others.
      await tester.tap(find.bySemanticsLabel(l[4]));
      await tester.pumpAndSettle();
      expect(index, 4);
      expect((_pill(tester).center.dx - slots[4].center.dx).abs(), lessThan(0.5));
      semantics.dispose();
    });
  }

  testWidgets('dock: tapping the open tab reports it again (pop to root); haptic only on a change', (tester) async {
    final taps = <int>[];
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(harness(_bar('en', 1, taps.add), locale: 'en'));
    await tester.tap(find.text('Quran'));
    await tester.tap(find.text('Prayer'));
    await tester.pumpAndSettle();
    expect(taps, [1, 2]);
    expect(haptics.length, 1);
  });

  testWidgets('dock: reduce-motion moves the pill at once', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      harness(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(builder: (c, set) => _bar('en', index, (i) => set(() => index = i))),
        ),
        locale: 'en',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Challenge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16)); // one frame, no glide
    expect((_pill(tester).center.dx - _slot(tester, 'Challenge').center.dx).abs(), lessThan(0.5));
  });

  for (final locale in ['ar', 'en']) {
    testWidgets('dock: 1.3x text on a narrow phone fits without overflow ($locale)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(harness(_bar(locale, 3, (_) {}, width: 320), locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in _labels[locale]!) {
        // Each label stays inside its own slot.
        final text = tester.getRect(find.text(label));
        final slot = _slot(tester, label);
        expect(text.left, greaterThanOrEqualTo(slot.left - 0.5));
        expect(text.right, lessThanOrEqualTo(slot.right + 0.5));
      }
      expect(tester.getSize(find.byType(FloatingTabBar)).height, FloatingTabBar.height);
    });
  }

  test('dock clearance: above the iOS home indicator, clear of Android system bars', () {
    expect(FloatingTabBar.gapFor(TargetPlatform.iOS, 34), 22);
    expect(FloatingTabBar.gapFor(TargetPlatform.iOS, 0), 16);
    expect(FloatingTabBar.gapFor(TargetPlatform.android, 48), 48); // 3-button bar
    expect(FloatingTabBar.gapFor(TargetPlatform.android, 0), 16);
    expect(FloatingTabBar.clearanceFor(TargetPlatform.android, 24), 24 + FloatingTabBar.height + 16);
  });

  for (final route in ['/profile/privacy', '/profile']) {
    testWidgets('shell: scrolled to the end, $route clears the dock (iOS insets)', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(MemoryKvStore()),
            secureStoreProvider.overrideWithValue(MemoryKvStore()),
            skyClockProvider.overrideWithValue(fixedSkyClock),
            quranDataProvider.overrideWith((_) => Completer<QuranData>().future),
          ],
          child: YaqeenApp(router: buildRouter(initialLocation: route)),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
      for (var i = 0; i < 6; i++) {
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 100));
      }
      final dock = tester.getRect(find.byType(FloatingTabBar));
      final texts = find.descendant(of: find.byType(CustomScrollView).first, matching: find.byType(Text));
      final lowest = texts.evaluate().map((e) => tester.getRect(find.byWidget(e.widget)).bottom).reduce(math.max);
      expect(lowest, lessThanOrEqualTo(dock.top));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('shell: every tab opens its screen; tapping the open tab returns it to its root', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = buildRouter(initialLocation: '/home/inbox');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
          skyClockProvider.overrideWithValue(fixedSkyClock),
          quranDataProvider.overrideWith((_) => Completer<QuranData>().future),
        ],
        child: YaqeenApp(router: router),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    String path() => router.routerDelegate.currentConfiguration.uri.path;
    expect(path(), '/home/inbox');

    for (final (label, target) in [('القرآن', '/quran'), ('الصلاة', '/prayer'), ('التحدي', '/challenge'), ('حسابي', '/profile')]) {
      await tester.tap(find.descendant(of: find.byType(FloatingTabBar), matching: find.text(label)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(path(), target);
    }
    // Home kept its pushed inbox; a second tap on the open tab pops back to the root.
    final home = find.descendant(of: find.byType(FloatingTabBar), matching: find.text('الرئيسية'));
    await tester.tap(home);
    await tester.pump(const Duration(milliseconds: 500));
    expect(path(), '/home/inbox');
    await tester.tap(home);
    await tester.pump(const Duration(milliseconds: 500));
    expect(path(), '/home');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tab branches keep state, fade in, and leave only the active tab onstage', (tester) async {
    var index = 0;
    late StateSetter setIndex;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (c, set) {
            setIndex = set;
            return TabBranches(
              currentIndex: index,
              children: [for (var i = 0; i < 3; i++) _Counter(key: ValueKey('tab$i'), name: 'tab$i')],
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('tab0: 0'));
    await tester.pump();
    expect(find.text('tab0: 1'), findsOneWidget);

    setIndex(() => index = 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('tab0: 1'), findsOneWidget); // still painted under the fade
    await tester.pumpAndSettle();
    expect(find.text('tab0: 1'), findsNothing); // offstage now
    expect(find.text('tab2: 0'), findsOneWidget);

    setIndex(() => index = 0);
    await tester.pumpAndSettle();
    expect(find.text('tab0: 1'), findsOneWidget); // state kept

    // Rapid switches mid-fade settle on the last tab only.
    setIndex(() => index = 1);
    await tester.pump(const Duration(milliseconds: 50));
    setIndex(() => index = 2);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('tab1: 0'), findsOneWidget); // the tab being left stays under the fade
    expect(find.text('tab0: 1'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('tab2: 0'), findsOneWidget);
    expect(find.text('tab1: 0'), findsNothing);
  });
}

class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.name});
  final String name;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Center(child: TextButton(onPressed: () => setState(() => n++), child: Text('${widget.name}: $n')));
}
