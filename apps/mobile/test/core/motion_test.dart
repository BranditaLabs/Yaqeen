import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/design/motion.dart';
import 'package:yaqeen/core/widgets/yq_count.dart';
import 'package:yaqeen/core/widgets/yq_flip.dart';
import 'package:yaqeen/core/widgets/yq_live_level.dart';
import 'package:yaqeen/core/widgets/yq_once.dart';
import 'package:yaqeen/core/widgets/yq_play_ring.dart';
import 'package:yaqeen/core/widgets/yq_ring.dart';
import 'package:yaqeen/core/widgets/yq_states.dart';

import '../helpers/harness.dart';

/// Wraps [child] with reduce-motion on.
Widget still(Widget child) => Builder(
      builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child),
    );

/// The value the ring's painter draws (its painter is private; read through dynamic).
double ringValue(WidgetTester tester) {
  final paint = tester.widgetList<CustomPaint>(find.descendant(of: find.byType(YqRing), matching: find.byType(CustomPaint))).first;
  return ((paint.painter as dynamic).value as num).toDouble();
}

void main() {
  group('Motion tokens', () {
    test('durations and curves', () {
      expect(Motion.quick, const Duration(milliseconds: 160));
      expect(Motion.standard, const Duration(milliseconds: 280));
      expect(Motion.emphasised, const Duration(milliseconds: 450));
      expect(Motion.emphasisedCurve, const Cubic(0.2, 0, 0, 1));
    });

    test('a spring curve runs 0 → 1, settles, and the overshooting one passes 1', () {
      for (final c in [Motion.pressCurve, Motion.popCurve, Motion.sheetCurve, Motion.settleCurve]) {
        expect(c.transform(0), 0);
        expect(c.transform(1), 1);
        expect(c.transform(0.98), closeTo(1, 0.02));
        expect(c.settle, greaterThan(Duration.zero));
        expect(c.settle, lessThan(const Duration(seconds: 2)));
      }
      final peak = [for (var i = 1; i < 100; i++) Motion.settleCurve.transform(i / 100)].reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(1.02)); // the week-result glyph overshoots
      final sheet = [for (var i = 1; i < 100; i++) Motion.sheetCurve.transform(i / 100)].reduce((a, b) => a > b ? a : b);
      expect(sheet, lessThan(1.005)); // the sheet never lifts off the bottom edge
    });

    testWidgets('reduceMotion follows MediaQuery.disableAnimations', (tester) async {
      bool? seen;
      await tester.pumpWidget(still(Builder(builder: (c) => Text('${seen = reduceMotion(c)}', textDirection: TextDirection.ltr))));
      expect(seen, isTrue);
    });

    test('MotionMemo plays a key once', () {
      final m = MotionMemo();
      expect(m.first('a'), isTrue);
      expect(m.first('a'), isFalse);
      expect(m.seen('a'), isTrue);
    });
  });

  group('YqRing', () {
    testWidgets('drawIn sweeps from 0 once; later changes ease from the old value, never from 0', (tester) async {
      Widget ring(double v) => harness(Center(child: YqRing(value: v, drawIn: Motion.ringDraw)));
      await tester.pumpWidget(ring(0.6));
      expect(ringValue(tester), closeTo(0, 0.001));
      await tester.pump(const Duration(milliseconds: 450));
      final mid = ringValue(tester);
      expect(mid, greaterThan(0.05));
      expect(mid, lessThan(0.6));
      await tester.pumpAndSettle();
      expect(ringValue(tester), closeTo(0.6, 0.001));

      await tester.pumpWidget(ring(0.8));
      await tester.pump();
      expect(ringValue(tester), closeTo(0.6, 0.01)); // starts where it was
      await tester.pump(const Duration(milliseconds: 100));
      expect(ringValue(tester), greaterThan(0.6));
      await tester.pumpAndSettle();
      expect(ringValue(tester), closeTo(0.8, 0.001));
    });

    testWidgets('without drawIn the value is there at once', (tester) async {
      await tester.pumpWidget(harness(const Center(child: YqRing(value: 0.4))));
      expect(ringValue(tester), closeTo(0.4, 0.001));
    });

    testWidgets('reduce-motion: the end state at once, no glint, and it settles', (tester) async {
      await tester.pumpWidget(harness(still(const Center(child: YqRing(value: 0.7, drawIn: Motion.ringDraw, glint: true)))));
      expect(ringValue(tester), closeTo(0.7, 0.001));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpAndSettle();
      // Only the ring's own painter: no glint layer was built.
      expect(find.descendant(of: find.byType(YqRing), matching: find.byType(CustomPaint)), findsOneWidget);
    });

    testWidgets('the glint plays once when it turns on, then rests', (tester) async {
      Widget ring(bool g) => harness(Center(child: YqRing(value: 1, glint: g)));
      await tester.pumpWidget(ring(false));
      expect(find.descendant(of: find.byType(YqRing), matching: find.byType(CustomPaint)), findsOneWidget);
      await tester.pumpWidget(ring(true));
      await tester.pump();
      expect(find.descendant(of: find.byType(YqRing), matching: find.byType(CustomPaint)), findsNWidgets(2));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(Motion.glint + Motion.standard);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('counting', () {
    testWidgets('CountUp reserves its final width from the first frame', (tester) async {
      await tester.pumpWidget(harness(const Center(child: CountUp(value: 1250, builder: _points))));
      final first = tester.getSize(find.byType(CountUp));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CountUp)), first);
      expect(find.text('1,250 نقطة'), findsWidgets);
      expect(find.bySemanticsLabel('1,250 نقطة'), findsOneWidget);
    });

    testWidgets('CountUp under reduce-motion is the final text', (tester) async {
      await tester.pumpWidget(harness(still(const Center(child: CountUp(value: 42)))));
      expect(find.text('42'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('YqRollingNumber rolls in, then rolls only the digits that change', (tester) async {
      Widget n(int v) => harness(Center(child: YqRollingNumber(value: v, style: const TextStyle(fontSize: 30))));
      await tester.pumpWidget(n(128));
      expect(find.bySemanticsLabel('128'), findsOneWidget);
      await tester.pumpAndSettle();
      for (final d in ['1', '2', '8']) {
        expect(find.text(d), findsOneWidget);
      }
      await tester.pumpWidget(n(129));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('8'), findsOneWidget); // leaving
      expect(find.text('9'), findsOneWidget); // arriving
      await tester.pumpAndSettle();
      expect(find.text('8'), findsNothing);
      expect(find.bySemanticsLabel('129'), findsOneWidget);
    });

    testWidgets('YqRollingNumber under reduce-motion is plain text', (tester) async {
      await tester.pumpWidget(harness(still(const Center(child: YqRollingNumber(value: 7, style: TextStyle())))));
      expect(find.text('7'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('one-time moments', () {
    testWidgets('YqFlip turns to the back face and settles', (tester) async {
      Widget f(bool back) => harness(Center(child: YqFlip(showBack: back, front: const Text('أمام'), back: const Text('خلف'))));
      await tester.pumpWidget(f(false));
      expect(find.text('أمام'), findsOneWidget);
      await tester.pumpWidget(f(true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('أمام'), findsOneWidget); // still turning away
      await tester.pumpAndSettle();
      expect(find.text('خلف'), findsOneWidget);
      expect(find.text('أمام'), findsNothing);
    });

    testWidgets('YqFlip under reduce-motion swaps at once', (tester) async {
      await tester.pumpWidget(harness(still(const Center(child: YqFlip(showBack: true, front: Text('أمام'), back: Text('خلف'))))));
      expect(find.text('خلف'), findsOneWidget);
      expect(find.byType(Transform), findsNothing);
    });

    testWidgets('sheen, pulse, line, slide and dot all come to rest (pumpAndSettle completes)', (tester) async {
      await tester.pumpWidget(
        harness(
          const Column(
            children: [
              YqSheen(child: SizedBox(width: 40, height: 40)),
              YqPulse(active: true, child: SizedBox(width: 40, height: 40)),
              YqDrawLine(),
              YqSlideIn(delay: Duration(milliseconds: 120), child: Text('ترتيبك 4')),
              YqShiftIn(rows: 2, child: Text('صف')),
              YqBreathingDot(),
            ],
          ),
        ),
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.text('ترتيبك 4'), findsOneWidget);
    });

    testWidgets('under reduce-motion they start at rest', (tester) async {
      await tester.pumpWidget(
        harness(
          still(
            const Column(
              children: [
                YqSheen(child: SizedBox(width: 40, height: 40)),
                YqPulse(active: true, child: SizedBox(width: 40, height: 40)),
                YqDrawLine(),
                YqSlideIn(child: Text('ترتيبك 4')),
                YqBreathingDot(),
              ],
            ),
          ),
        ),
      );
      expect(tester.binding.transientCallbackCount, 0);
      final slide = tester.widget<Opacity>(find.ancestor(of: find.text('ترتيبك 4'), matching: find.byType(Opacity)).first);
      expect(slide.opacity, 1);
    });

    testWidgets('YqFadeSwap: 200 ms cross-fade from skeleton to content', (tester) async {
      Widget s(bool ready) => harness(
            Center(
              child: YqFadeSwap(
                child: ready ? const Text('محتوى', key: ValueKey('c')) : const SizedBox(key: ValueKey('s'), width: 10, height: 10),
              ),
            ),
          );
      await tester.pumpWidget(s(false));
      await tester.pumpWidget(s(true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('s')), findsOneWidget);
      expect(find.text('محتوى'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const ValueKey('s')), findsNothing);
    });
  });

  group('YqPlayRing', () {
    Widget ring({required bool playing, bool orbit = true, double progress = 0.3, VoidCallback? onPressed}) => harness(
          Center(child: YqPlayRing(playing: playing, progress: progress, orbit: orbit, onPressed: onPressed ?? () {})),
        );

    testWidgets('the orbit turns while playing and its ticker stops on pause', (tester) async {
      await tester.pumpWidget(ring(playing: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(find.bySemanticsLabel('إيقاف مؤقت'), findsOneWidget);

      await tester.pumpWidget(ring(playing: false));
      await tester.pump(Motion.standard + const Duration(milliseconds: 50)); // the glyph morphs back
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.bySemanticsLabel('تشغيل'), findsOneWidget);
      await tester.pumpAndSettle(); // nothing left running
    });

    testWidgets('off-screen (TickerMode off) the orbit stops', (tester) async {
      await tester.pumpWidget(
        harness(TickerMode(enabled: false, child: Center(child: YqPlayRing(playing: true, progress: 0.5, orbit: true, onPressed: () {})))),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('reduce-motion: no orbit, and a tap still plays', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        harness(still(Center(child: YqPlayRing(playing: true, progress: 0.5, orbit: true, onPressed: () => taps++)))),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tap(find.byType(YqPlayRing));
      expect(taps, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('the progress ring follows progress', (tester) async {
      await tester.pumpWidget(ring(playing: false, orbit: false, progress: 0.25));
      expect(ringValue(tester), closeTo(0.25, 0.001));
      await tester.pumpWidget(ring(playing: false, orbit: false, progress: 0.75));
      await tester.pumpAndSettle();
      expect(ringValue(tester), closeTo(0.75, 0.001));
    });
  });

  group('YqLiveLevel', () {
    double barHeight(WidgetTester tester, int i) => tester.getSize(find.byKey(ValueKey('yq-live-bar-$i'))).height;

    testWidgets('bars follow the real amplitude, newest in the centre', (tester) async {
      final levels = StreamController<double>();
      addTearDown(levels.close);
      await tester.pumpWidget(harness(Center(child: YqLiveLevel(levels: levels.stream, bars: 7))));
      final rest = barHeight(tester, 3);
      expect(rest, closeTo(28 * YqLiveLevel.floor, 0.01));
      levels.add(0.9);
      await tester.pump();
      await tester.pump(YqLiveLevel.ease);
      expect(barHeight(tester, 3), greaterThan(20));
      expect(barHeight(tester, 0), closeTo(rest, 0.01)); // older samples (silence) at the edges
      levels.add(0.0);
      await tester.pump();
      await tester.pump(YqLiveLevel.ease);
      expect(barHeight(tester, 3), closeTo(rest, 0.01));
      expect(barHeight(tester, 2), greaterThan(rest)); // the last word spreads outward
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.transientCallbackCount, 0); // between samples nothing runs
    });

    testWidgets('reduce-motion: a still rest shape that does not listen', (tester) async {
      final levels = StreamController<double>.broadcast();
      addTearDown(levels.close);
      await tester.pumpWidget(harness(still(Center(child: YqLiveLevel(levels: levels.stream)))));
      expect(levels.hasListener, isFalse);
      final h = barHeight(tester, 2);
      levels.add(1);
      await tester.pump();
      expect(barHeight(tester, 2), h);
    });
  });
}

String _points(String n) => '$n نقطة';
