import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/app/shell.dart';
import 'package:yaqeen/core/widgets/floating_tab_bar.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_icon.dart';

import '../helpers/harness.dart';

Widget _bar(int index, ValueChanged<int> onSelect) => Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 360,
          child: FloatingTabBar(
            currentIndex: index,
            onSelect: onSelect,
            avatarInitial: 'أ',
            profileLabel: 'profile',
            tabs: const [
              YqTab(icon: YqIcons.home, label: 'home'),
              YqTab(icon: YqIcons.quran, label: 'quran'),
              YqTab(icon: YqIcons.prayer, label: 'prayer'),
              YqTab(icon: YqIcons.challenge, label: 'challenge'),
            ],
          ),
        ),
      ),
    );

double _labelOpacity(WidgetTester tester, String label) =>
    tester.widget<AnimatedOpacity>(find.ancestor(of: find.text(label), matching: find.byType(AnimatedOpacity)).first).opacity;

void main() {
  setUp(() => YqGlassConfig.enableBlur = false);

  for (final locale in ['ar', 'en']) {
    testWidgets('tab bar: lens sits under the active tab and only its label shows ($locale)', (tester) async {
      var index = 0;
      await tester.pumpWidget(harness(StatefulBuilder(builder: (c, set) => _bar(index, (i) => set(() => index = i))), locale: locale));
      await tester.pumpAndSettle();
      expect(_labelOpacity(tester, 'home'), 1);
      expect(_labelOpacity(tester, 'prayer'), 0);

      await tester.tap(find.bySemanticsLabel('prayer'));
      await tester.pump(const Duration(milliseconds: 200)); // mid-animation: nothing overflows
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(index, 2);
      expect(_labelOpacity(tester, 'prayer'), 1);
      expect(_labelOpacity(tester, 'home'), 0);

      // The lens is centred on the active tab, on the correct side for the text direction.
      final lens = tester.getRect(find.byType(AnimatedPositionedDirectional));
      final tab = tester.getRect(find.ancestor(of: find.text('prayer'), matching: find.byType(AnimatedContainer)).first);
      expect((lens.center.dx - tab.center.dx).abs(), lessThan(1));
      final home = tester.getCenter(find.ancestor(of: find.text('home'), matching: find.byType(AnimatedContainer)).first);
      expect(locale == 'ar' ? home.dx > lens.center.dx : home.dx < lens.center.dx, isTrue);
    });
  }

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
  Widget build(BuildContext context) =>
      Center(child: TextButton(onPressed: () => setState(() => n++), child: Text('${widget.name}: $n')));
}
