import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/config_controller.dart';
import '../../../../core/config/remote_config.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/settings/settings_controller.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_states.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../listen/presentation/listen_controller.dart';
import '../../../listen/presentation/now_playing_screen.dart';
import '../../data/session_store.dart';
import '../../domain/passage.dart';
import '../../domain/quran_session.dart';
import 'active_session.dart';
import 'session_start_sheet.dart';

/// Home and the Quran index enter the reader through here (spec §5.9, §5.11).

/// A session that can still be resumed («أكمل جلستك · ص {page}»), or null. Stale ones are dropped.
/// Only a session starting or ending re-checks it — not every page turn of the open reader. While a
/// reader holds a session it is that one (valid by construction: nothing is read or cleared); once
/// the reader lets go, the check waits for the session's last writes.
final quranResumeProvider = FutureProvider.autoDispose<QuranSession?>((ref) async {
  final id = ref.watch(activeSessionProvider.select((s) => s?.id));
  final active = ref.read(activeSessionProvider);
  if (id != null && active != null) return active;
  await ref.read(activeSessionProvider.notifier).flushed();
  return loadValidSession(ref.read);
});

/// The page a saved session reopens on.
int sessionPage(QuranSession s) => s.page ?? surahStartPage(s.passage.surah);

/// `/quran/read/<page>?session=resume`: the reader picks the saved session up where it was.
String resumeLocation(QuranSession s, {QuranMode? mode}) =>
    '/quran/read/${sessionPage(s)}?session=resume${mode != null && mode != QuranMode.read ? '&mode=${mode.name}' : ''}';

/// «استبدال التشغيل الحالي؟» — asked before a session takes over another surah's recitation.
Future<bool> confirmReplacePlayback(BuildContext context) async {
  final t = AppLocalizations.of(context);
  final ok = await showYqSheet<bool>(
    context,
    builder: (c) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.qsReplacePlaybackTitle, style: Theme.of(c).textTheme.titleLarge),
        const SizedBox(height: YqSpace.l),
        YqButton(label: t.qsReplace, onPressed: () => Navigator.of(c).pop(true)),
        const SizedBox(height: YqSpace.s),
        YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
      ],
    ),
  );
  return ok ?? false;
}

/// Something else is reciting another surah (not a reciter sample).
bool playingOtherSurah(ListenState l, int surah) =>
    l.status == ListenStatus.ready && l.playing && l.sampleOf == null && l.surah != surah;

/// The wird orb: today's wird session resumes; otherwise «ابدأ وردك» (pages left from the page last
/// read, «مع التلاوة») starts one in the reader.
Future<void> startWirdSession(BuildContext context, WidgetRef ref) async {
  final resume = await ref.read(quranResumeProvider.future);
  if (!context.mounted) return;
  if (resume != null && resume.kind == QuranSessionKind.wird) {
    await context.push(resumeLocation(resume, mode: resume.mode));
    return;
  }
  final q = await ref.read(quranDataProvider.future);
  final last = await ref.read(readingRepositoryProvider).lastRead();
  final wird = await ref.read(readingRepositoryProvider).wird();
  if (!context.mounted) return;
  final today = sessionToday(ref.read);
  final goal = ref.read(settingsProvider).wirdGoalPages;
  final done = wird?.date == today ? wird!.count : 0;
  final page = (last?.page ?? 1).clamp(1, 604);
  final listenOn = ref.read(remoteConfigProvider).isOn(Flags.listen);
  final pages = wirdSessionPages(done: done, goal: goal);
  final choice = await showSessionStartSheet(context, pages: pages, page: page, listenOn: listenOn);
  if (choice == null || !context.mounted) return;
  var audio = choice.audio;
  final passage = Passage.ofPage(q, page);
  if (audio && playingOtherSurah(ref.read(listenControllerProvider), passage.surah)) {
    audio = await confirmReplacePlayback(context);
    if (!context.mounted) return;
  }
  final session = QuranSession.start(
    QuranSessionKind.wird,
    passage,
    now: ref.read(clockProvider)(),
    day: today,
    mode: audio ? QuranMode.listen : QuranMode.read,
    page: page,
    planKey: await sessionPlanKey(ref.read, QuranSessionKind.wird),
    // Measured from where today's count stands now: after the goal is met, «{pages} صفحات» more.
    goal: done + pages,
  );
  await ref.read(quranSessionStoreProvider).save(session);
  ref.invalidate(quranResumeProvider);
  if (context.mounted) await context.push(resumeLocation(session, mode: session.mode));
}

/// A general «استماع» entry (Home's continue-reading play, the index): the reader listening, with the
/// player open, on what plays or the resume point, else [fallbackSurah].
Future<void> openQuranListen(BuildContext context, WidgetRef ref, {required int fallbackSurah}) => pushListen(context, ref, fallbackSurah);
