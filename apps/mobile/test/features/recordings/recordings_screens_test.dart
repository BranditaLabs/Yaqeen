import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yaqeen/core/widgets/yq_live_level.dart';
import 'package:yaqeen/core/widgets/yq_states.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/presentation/mushaf_page.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/recordings/data/recording_drafts.dart';
import 'package:yaqeen/features/recordings/domain/recording_models.dart';
import 'package:yaqeen/features/recordings/presentation/listener_sheet.dart';
import 'package:yaqeen/features/recordings/presentation/recorder_controller.dart';
import 'package:yaqeen/features/recordings/presentation/recorder_screen.dart';
import 'package:yaqeen/features/recordings/presentation/recordings_section.dart';
import 'package:yaqeen/features/recordings/presentation/verse_picker_screen.dart';
import 'package:yaqeen/features/recordings/presentation/verse_words_view.dart';

import '../../helpers/harness.dart';
import 'recordings_rig.dart';

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget page(Widget child, RecordingsRig rig, {String locale = 'ar', bool still = false, List<Override> extra = const []}) => harness(
      still ? Builder(builder: (context) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child)) : child,
      locale: locale,
      kv: rig.kv,
      overrides: [...rig.overrides, mushafLayoutProvider.overrideWith((_) async => null), ...extra],
    );

Iterable<VerseWord> looks(WidgetTester tester, WordLook look) => tester.widgetList<VerseWord>(find.byType(VerseWord)).where((w) => w.look == look);

void main() {
  setUpAll(() => RecorderController.countInStep = const Duration(milliseconds: 5));

  group('verse swipe picker', () {
    testWidgets('a swipe across the page selects a range in one surah, with the estimate', (tester) async {
      phone(tester);
      final rig = RecordingsRig();
      await tester.pumpWidget(page(const VersePickerScreen(), rig));
      await tester.pumpAndSettle();
      expect(find.byType(MushafPage), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-pick-panel')), findsNothing);
      // Al-Fatihah: drag from the first lines of the text to its last.
      final text = find.descendant(of: find.byType(MushafPage), matching: find.byType(RichText)).last;
      final r = tester.getRect(text);
      // A finger moving down the page in small steps, from between two lines to the sixth ayah.
      final start = Offset(r.center.dx, r.top + r.height * 0.12);
      final g = await tester.startGesture(start);
      for (var y = start.dy; y <= r.top + r.height * 0.7; y += 12) {
        await g.moveTo(Offset(r.center.dx, y));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-pick-panel')), findsOneWidget);
      // The first ayah reached anchors the range (the down was between lines).
      expect(find.text('سورة الفاتحة · الآيات 2–6'), findsOneWidget);
      expect(find.textContaining('≈'), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-continue')), findsOneWidget);
    });

    testWidgets('handles adjust the ends; a clearly long range is blocked and trims to fit', (tester) async {
      phone(tester);
      final rig = RecordingsRig();
      await tester.pumpWidget(page(const VersePickerScreen(initial: Passage(112, 2, 3)), rig));
      await tester.pumpAndSettle();
      expect(find.text('سورة الإخلاص · الآيات 2–3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-start-less')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rec-end-more')));
      await tester.pumpAndSettle();
      expect(find.text('سورة الإخلاص · الآيات 1–4'), findsOneWidget);
      expect(find.text('≈ 7 ث'), findsOneWidget); // 15 words at 2.2 a second

      await tester.pumpWidget(page(const VersePickerScreen(key: ValueKey('kursi'), initial: Passage(2, 255, 257)), rig));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-fit-blocked')), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-continue')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('rec-trim')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-fit-blocked')), findsNothing);
      expect(find.byKey(const ValueKey('rec-continue')), findsOneWidget);
    });
  });

  group('listener', () {
    final id = recFixture('member_recordings.json')['items'][0]['id'] as String;
    Map<String, Object?> member({List<Map<String, int>>? words, bool mine = false, bool commentsOn = true}) => {
          ...memberRecordingsFixture()['items'][0] as Map<String, dynamic>,
          'surah': 112,
          'fromAyah': 1,
          'toAyah': 1,
          'durationMs': 4000,
          'mine': mine,
          'commentsOn': commentsOn,
          'words': words ??
              [
                {'ayah': 1, 'index': 0, 'startMs': 0, 'endMs': 400},
                {'ayah': 1, 'index': 1, 'startMs': 400, 'endMs': 800},
                {'ayah': 1, 'index': 2, 'startMs': 800, 'endMs': 1200},
                {'ayah': 1, 'index': 3, 'startMs': 1200, 'endMs': 1600},
              ],
        };
    Map<String, Object?> comment(String cid, {bool mine = false}) => {
          'id': cid,
          'author': {
            'handle': mine ? 'me-1' : 'sara-1180',
            'name': mine ? 'أنا' : 'سارة',
            'avatar': {'kind': 'initial'},
            'level': {'level': 2, 'progress': 0.3},
            'points': null,
            'rank': null,
            'me': mine,
          },
          'text': mine ? 'تلاوة خاشعة' : 'ما شاء الله',
          'createdAt': '2026-11-14T08:10:00.000Z',
          'mine': mine,
          'canDelete': mine,
        };
    const c1 = '11111111-1111-4111-8111-111111111111';
    const c2 = '22222222-2222-4222-8222-222222222222';

    Future<RecordingsRig> open(WidgetTester tester, {Map<String, ApiRoute> routes = const {}, Map<String, Object?>? rec}) async {
      phone(tester);
      final rig = RecordingsRig(routes: {
        'GET /v1/recordings/$id/comments': (_) => jsonResponse({
              'items': [comment(c1, mine: true), comment(c2)],
              'nextCursor': null,
              'commentsOn': true,
            }),
        ...routes,
      });
      // The audio is already on the phone (no file IO inside the fake clock).
      File('${rig.dir.path}/recordings/cache/$id.m4a')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final target = ListenTarget.member(PublicRecording.fromJson(rec ?? member()));
      await tester.pumpWidget(
        page(
          Scaffold(
            body: Builder(
              builder: (context) => Center(child: TextButton(onPressed: () => showRecordingListener(context, target), child: const Text('open'))),
            ),
          ),
          rig,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return rig;
    }

    testWidgets('words light up following the timings while it plays (karaoke)', (tester) async {
      final rig = await open(tester);
      expect(looks(tester, WordLook.lit), isEmpty);
      await tester.tap(find.byKey(const ValueKey('rec-listener-play')));
      await tester.pump();
      expect(rig.audio.opened.single.path, endsWith('$id.m4a'));
      rig.audio.advance(const Duration(milliseconds: 900));
      await tester.pump();
      expect(looks(tester, WordLook.lit).map((w) => w.text), hasLength(2));
      expect(looks(tester, WordLook.current), hasLength(1));
      rig.audio.advance(const Duration(milliseconds: 1000));
      await tester.pump();
      expect(looks(tester, WordLook.lit), hasLength(4));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('reactions: one per member, change it, tap again to take it back', (tester) async {
      final rig = await open(tester, routes: {
        'PUT /v1/recordings/$id/reaction': (_) => jsonResponse({
              'reactions': {'mashallah': 3, 'barakallah': 3, 'ahsant': 1},
              'myReaction': 'barakallah',
            }),
        'DELETE /v1/recordings/$id/reaction': (_) => jsonResponse({
              'reactions': {'mashallah': 3, 'barakallah': 2, 'ahsant': 1},
              'myReaction': null,
            }),
      });
      Semantics pill(String code) => tester.widget<Semantics>(find.descendant(of: find.byKey(ValueKey('rec-react-$code')), matching: find.byType(Semantics)).first);
      expect(pill('mashallah').properties.selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('rec-react-barakallah')));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('PUT /v1/recordings/$id/reaction'));
      expect(pill('barakallah').properties.selected, isTrue);
      expect(pill('mashallah').properties.selected, isFalse);
      expect(pill('barakallah').properties.label, 'بارك الله فيك، 3');
      await tester.tap(find.byKey(const ValueKey('rec-react-barakallah')));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('DELETE /v1/recordings/$id/reaction'));
      expect(pill('barakallah').properties.selected, isFalse);
    });

    testWidgets('comments: a refused comment explains why; the rate limit too; delete and report', (tester) async {
      var attempt = 0;
      final rig = await open(tester, routes: {
        'POST /v1/recordings/$id/comments': (_) => ++attempt == 1
            ? errorResponse(400, 'comment_rejected', details: {'problem': 'link'})
            : errorResponse(429, 'comment_rate_limited'),
        'DELETE /v1/recordings/$id/comments/$c1': (_) => http.Response('', 204),
        'POST /v1/recordings/$id/comments/$c2/report': (_) => http.Response('', 204),
      });
      expect(find.byKey(const ValueKey('rec-comment-$c1')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('rec-composer')), 'زوروا example.com');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rec-composer-send')));
      await tester.pumpAndSettle();
      expect(find.text('لا يمكن نشر هذا التعليق · الروابط غير مسموحة'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-composer-send')));
      await tester.pumpAndSettle();
      expect(find.text('علّقت كثيراً. انتظر قليلاً.'), findsOneWidget);

      // Delete my own comment.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('rec-comment-$c1')), matching: find.byIcon(Icons.more_vert_rounded)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-comment-delete')));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('DELETE /v1/recordings/$id/comments/$c1'));
      expect(find.byKey(const ValueKey('rec-comment-$c1')), findsNothing);

      // Report another member's comment: it leaves this view.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('rec-comment-$c2')), matching: find.byIcon(Icons.more_vert_rounded)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-comment-delete')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('rec-comment-report')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-reason-inappropriate')));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('POST /v1/recordings/$id/comments/$c2/report'));
      expect(find.byKey(const ValueKey('rec-comment-$c2')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('comments off: a note instead of the composer', (tester) async {
      await open(tester, rec: member(commentsOn: false), routes: {
        'GET /v1/recordings/$id/comments': (_) => jsonResponse({'items': <Object>[], 'nextCursor': null, 'commentsOn': false}),
      });
      expect(find.byKey(const ValueKey('rec-composer')), findsNothing);
      expect(find.byKey(const ValueKey('rec-composer-off')), findsOneWidget);
    });

    testWidgets('own recording: counts only, no reacting', (tester) async {
      final rig = await open(tester, rec: member(mine: true));
      await tester.tap(find.byKey(const ValueKey('rec-react-ahsant')));
      await tester.pumpAndSettle();
      expect(rig.calls.where((c) => c.contains('reaction')), isEmpty);
      expect(find.text('تفاعلات الأعضاء مع تلاوتك'), findsOneWidget);
    });
  });

  group('profile section', () {
    Widget section(RecordingsRig rig) => page(const Scaffold(body: SingleChildScrollView(child: RecordingsSection())), rig);

    testWidgets('shaped skeleton while loading, then the cards with their status lines', (tester) async {
      phone(tester);
      final gate = Completer<void>();
      final rig = RecordingsRig(routes: {
        'GET /v1/me/recordings': (_) async {
          await gate.future;
          return jsonResponse(recFixture('my_recordings.json'));
        },
      });
      await tester.pumpWidget(section(rig));
      await tester.pump();
      expect(find.byType(RecordingsSkeleton), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RecordingCard), findsNWidgets(3));
      expect(find.byKey(const ValueKey('rec-status-approved')), findsOneWidget);
      expect(find.text('منشورة'), findsOneWidget);
      expect(find.text('قيد الفحص…'), findsOneWidget);
      expect(find.text('لم تطابق الآيات المختارة'), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-limit')), findsOneWidget); // 3 of 3
      expect(find.byKey(const ValueKey('rec-new')), findsNothing);
      // A rejected recording offers to record again.
      expect(find.text('أعد التسجيل'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30)); // the processing poll's timer
    });

    testWidgets('empty: one quiet row; a guest sees only the takes on this phone', (tester) async {
      phone(tester);
      final rig = RecordingsRig(routes: {'GET /v1/me/recordings': (_) => jsonResponse({'items': <Object>[], 'leftToday': 10})});
      await tester.pumpWidget(section(rig));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-empty')), findsOneWidget);
      expect(find.text('سجّل تلاوتك لآيات تحبها (30 ثانية)'), findsOneWidget);

      final guest = RecordingsRig(signedIn: false);
      await guest.kv.write(
        RecordingDrafts.key,
        '[{"id":"d1","s":112,"f":1,"t":4,"ms":7000,"path":"x.m4a","vis":"private","c":true,"at":"2026-11-14T10:00:00.000Z","state":"local"}]',
      );
      await tester.pumpWidget(section(guest));
      await tester.pumpAndSettle();
      expect(guest.calls, isEmpty);
      expect(find.byType(DraftCard), findsOneWidget);
      expect(find.textContaining('سجّل الدخول لحفظها في حسابك'), findsOneWidget);
    });

    testWidgets('menu: move down and delete (two steps)', (tester) async {
      phone(tester);
      final items = recFixture('my_recordings.json');
      final first = (items['items'] as List)[0]['id'];
      final rig = RecordingsRig(routes: {
        'GET /v1/me/recordings': (_) => jsonResponse(items),
        'PATCH /v1/me/recordings/$first': (_) => jsonResponse({...(items['items'] as List)[0] as Map<String, dynamic>, 'position': 2}),
        'DELETE /v1/me/recordings/$first': (_) => http.Response('', 204),
      });
      await tester.pumpWidget(section(rig));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('rec-menu-$first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-move-down')));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('PATCH /v1/me/recordings/$first'));
      await tester.tap(find.byKey(ValueKey('rec-menu-$first')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('rec-delete')));
      await tester.tap(find.byKey(const ValueKey('rec-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-delete-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-delete-confirm')));
      await tester.pumpAndSettle();
      expect(rig.calls, contains('DELETE /v1/me/recordings/$first'));
      expect(find.byType(RecordingCard), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('sharing a private one answers community_required with the join sheets', (tester) async {
      phone(tester);
      final items = recFixture('my_recordings.json');
      final rejected = (items['items'] as List)[2] as Map<String, dynamic>;
      final private = {...rejected, 'status': 'private_ready', 'rejectReason': null};
      final rig = RecordingsRig(routes: {
        'GET /v1/me/recordings': (_) => jsonResponse({'items': [private], 'leftToday': 7}),
        'PATCH /v1/me/recordings/${private['id']}': (_) => errorResponse(403, 'community_required'),
      });
      await tester.pumpWidget(section(rig));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('rec-menu-${private['id']}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-vis-members')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-gate-board')), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-gate-league')), findsOneWidget);
    });
  });

  group('recorder', () {
    testWidgets('reduce motion: a still pill and still bars, the ring counts; review settles', (tester) async {
      phone(tester);
      final rig = RecordingsRig();
      await tester.pumpWidget(page(const RecorderScreen(passage: Passage(112, 1, 4)), rig, still: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-mic-body')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-start')));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byKey(const ValueKey('rec-live-pill')), findsOneWidget);
      rig.recorder.take!.emit(ms: 4000, level: 0.9);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle(); // nothing loops under reduce motion
      final fade = tester.widget<FadeTransition>(find.descendant(of: find.byKey(const ValueKey('rec-live-pill')), matching: find.byType(FadeTransition)));
      expect(fade.opacity.value, 1);
      expect(find.byType(YqLiveLevel), findsOneWidget);
      expect(find.text('26 ث متبقية'), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-mode-pacing')), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('rec-stop')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rec-review')), findsOneWidget);
      expect(find.byKey(const ValueKey('rec-save')), findsOneWidget);
      expect(find.byType(YqFadeSwap), findsWidgets);
    });

    testWidgets('a refused microphone explains and opens Settings', (tester) async {
      phone(tester);
      final rig = RecordingsRig();
      rig.recorder.allowed = false;
      await tester.pumpWidget(page(const RecorderScreen(passage: Passage(112, 1, 4)), rig, locale: 'en'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-start')));
      await tester.pumpAndSettle();
      expect(find.text('Microphone access is off. Open Settings and allow it for Yaqeen.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rec-open-settings')));
      expect(rig.recorder.settingsOpened, 1);
    });
  });
}
