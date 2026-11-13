import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/controls.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_ring.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../listen/presentation/downloads_controller.dart';
import '../../../listen/presentation/listen_controller.dart';
import '../../domain/quran_session.dart';
import 'active_session.dart';
import 'memorise_strip.dart' show memoriseRepeatGoal;
import 'quran_session_controller.dart';

/// Listening rounds of a guided «استماع ×3».
const guidedListenTimes = 3;

/// Whether recitation can't play here: no reciter, or the surah isn't reachable (offline, not
/// downloaded). A guided session then offers «تنزيل السورة» or «تخطَّ إلى التكرار».
bool noAudio(ListenState s) => s.status == ListenStatus.noReciter || s.status == ListenStatus.unavailable;

/// The running session over the dock's strip: stage dots and the stage («استماع ×3 · ×1 / 3»,
/// «تكرار ×10 · ×4 / 10», «اختبار» with «انتهيت»), or a reading goal «{done} / {goal}» on a thin
/// line. Gold only once the goal is met.
class SessionLine extends ConsumerWidget {
  const SessionLine({
    super.key,
    required this.session,
    this.onSkipToRepeat,
    this.onAudioReady,
    this.onFinished,
    this.onEcho,
    this.echoing = false,
  });

  final QuranSession session;
  final VoidCallback? onSkipToRepeat;

  /// The surah was downloaded: listening starts again.
  final VoidCallback? onAudioReady;

  /// «انتهيت» (the test is over: the grade sheet follows).
  final VoidCallback? onFinished;

  /// Echo practice for «تكرار ×10» (play an ayah, leave time to repeat it); null without audio.
  final VoidCallback? onEcho;
  final bool echoing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final progress = ref.watch(sessionProgressProvider);
    final text = Theme.of(context).textTheme;
    if (!session.kind.guided) {
      if (progress == null) return const SizedBox.shrink();
      final met = progress.goal > 0 && progress.done >= progress.goal;
      final label = t.qsSessionProgress(YqFormat.number(progress.done.clamp(0, progress.goal)), YqFormat.number(progress.goal));
      return Semantics(
        label: label,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.xs, vertical: YqSpace.xs),
          child: Row(
            children: [
              Text(label, style: text.labelMedium?.copyWith(color: met ? YqColors.goldText : YqColors.lapis, fontWeight: FontWeight.w700)),
              const SizedBox(width: YqSpace.s),
              Expanded(
                child: YqProgressLine(
                  value: progress.goal == 0 ? 0 : progress.done / progress.goal,
                  color: met ? YqColors.gold : YqColors.lapis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final listen = ref.watch(listenControllerProvider);
    final repeats = ref.watch(quranSessionControllerProvider.select((l) => l.repeats));
    final stage = session.stage;
    final (String label, String? round) = switch (stage) {
      SessionStage.listen => (
          t.qsListenTimes(YqFormat.number(guidedListenTimes)),
          t.qsRoundOf(YqFormat.number(listen.roundsDone.clamp(0, guidedListenTimes)), YqFormat.number(guidedListenTimes)),
        ),
      SessionStage.repeat => (
          t.qsRepeatTimes(YqFormat.number(memoriseRepeatGoal)),
          t.qsRoundOf(YqFormat.number(repeats.clamp(0, memoriseRepeatGoal)), YqFormat.number(memoriseRepeatGoal)),
        ),
      _ => (t.qsTest, null),
    };
    final missing = stage == SessionStage.listen && noAudio(listen);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StageDots(stage: stage),
            const SizedBox(width: YqSpace.s),
            Expanded(
              child: Text(
                round == null ? label : '$label · $round',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(color: YqColors.lapis, fontWeight: FontWeight.w700),
              ),
            ),
            if (stage == SessionStage.repeat && onEcho != null)
              IconButton(
                tooltip: t.qsRepeatTimes(YqFormat.number(memoriseRepeatGoal)),
                onPressed: onEcho,
                icon: Icon(echoing ? Icons.pause_rounded : Icons.replay_rounded, color: YqColors.lapis),
              ),
            if (stage == SessionStage.test && onFinished != null) YqButton.text(label: t.qsFinished, onPressed: onFinished),
          ],
        ),
        if (missing) _NoAudio(onSkip: onSkipToRepeat, onReady: onAudioReady),
      ],
    );
  }
}

/// «استماع · تكرار · اختبار» as three dots: passed and current lapis, the rest a hairline ring;
/// all gold once the session is done.
class StageDots extends StatelessWidget {
  const StageDots({super.key, required this.stage});
  final SessionStage stage;

  @override
  Widget build(BuildContext context) {
    final at = QuranSession.guidedStages.indexOf(stage);
    final done = stage == SessionStage.done;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < QuranSession.guidedStages.length; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsetsDirectional.only(end: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? YqColors.gold : (i <= at ? YqColors.lapis : YqColors.white.withValues(alpha: 0)),
              border: Border.all(color: done ? YqColors.gold : (i <= at ? YqColors.lapis : YqColors.line)),
            ),
          ),
      ],
    );
  }
}

/// «لا تلاوة على الجهاز»: «تنزيل السورة» on the download queue (a ring while it runs) or
/// «تخطَّ إلى التكرار».
class _NoAudio extends ConsumerWidget {
  const _NoAudio({this.onSkip, this.onReady});
  final VoidCallback? onSkip;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(listenControllerProvider);
    final r = s.reciter;
    final key = r == null ? null : surahDownloadKey(r.id, s.surah);
    final progress = key == null ? null : ref.watch(surahDownloadsProvider)[key];
    return Row(
      children: [
        Expanded(child: Text(t.qsNoAudio, style: Theme.of(context).textTheme.bodySmall)),
        if (r != null)
          progress != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.m),
                  child: Semantics(label: t.qsDownloadSurah, value: '${YqFormat.number((progress * 100).round())}%', child: YqRing(value: progress, size: 22, stroke: 2.4)),
                )
              : YqButton.text(
                  label: t.qsDownloadSurah,
                  onPressed: () async {
                    try {
                      await ref.read(downloadsControllerProvider.notifier).downloadSurah(r, s.surah);
                      onReady?.call();
                    } on Exception {
                      // The line stays: the user can try again or skip.
                    }
                  },
                ),
        if (onSkip != null) YqButton.text(label: t.qsSkipToRepeat, onPressed: onSkip),
      ],
    );
  }
}
