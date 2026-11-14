import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/format.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/controls.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_ring.dart';
import '../../../../core/widgets/yq_states.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../listen/presentation/listen_controller.dart';
import '../../../recite/domain/recitation.dart';
import '../../../recite/presentation/asr_model_sheet.dart';
import '../../../recite/presentation/recite_controller.dart';
import '../../domain/passage.dart';
import '../../domain/quran_data.dart';

/// Plays one ayah once — the way to hear a «تنبيه» again (the user's reciter, then it pauses).
Future<void> playAyahOnce(WidgetRef ref, AyahRef a) async {
  final listen = ref.read(listenControllerProvider.notifier);
  final before = ref.read(listenControllerProvider);
  await listen.playAyahThenPause(a);
  listen.restoreRepeat(before);
}

/// Asks for the microphone once («نستمع لتلاوتك على جهازك فقط»). True when listening may start.
Future<bool> reciteRationale(BuildContext context, WidgetRef ref) async {
  final c = ref.read(reciteControllerProvider.notifier);
  if (await c.rationaleSeen()) return true;
  if (!context.mounted) return false;
  final t = AppLocalizations.of(context);
  final ok = await showYqSheet<bool>(
    context,
    builder: (s) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.mic_none_rounded, size: 40, color: YqColors.lapis),
        const SizedBox(height: YqSpace.m),
        Text(t.reciteMicRationale, textAlign: TextAlign.center, style: Theme.of(s).textTheme.titleMedium),
        const SizedBox(height: YqSpace.xs),
        Text(t.asrSheetWords, textAlign: TextAlign.center, style: Theme.of(s).textTheme.bodySmall?.copyWith(color: YqColors.muted)),
        const SizedBox(height: YqSpace.l),
        YqButton(label: t.reciteStart, onPressed: () => Navigator.of(s).pop(true)),
        const SizedBox(height: YqSpace.s),
        YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(s).pop(false)),
      ],
    ),
  );
  if (ok != true) return false;
  await c.markRationaleSeen();
  return true;
}

/// «تسميع» over the page (spec §5.12): the microphone in a ring of how much is recited, the state
/// («يستمع إليك»), «{ayat} آيات · {notes} ملاحظات · {helps} مساعدات», a ring per ayah, pause /
/// «متابعة», «إنهاء», «إظهار النص», and each «تنبيه» (a tap plays that ayah once). Copy says «تنبيه»,
/// never «خطأ», and that it checks the words, not tajweed. A haptic tick marks each completed ayah.
class ReciteStrip extends ConsumerStatefulWidget {
  const ReciteStrip({super.key, required this.quran, required this.passage});

  final QuranData quran;

  /// What is recited: the session's passage, else the page's (`Passage.ofPage`).
  final Passage passage;

  @override
  ConsumerState<ReciteStrip> createState() => _ReciteStripState();
}

class _ReciteStripState extends ConsumerState<ReciteStrip> {
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(ReciteStrip old) {
    super.didUpdateWidget(old);
    if (old.passage != widget.passage) _prepare();
  }

  /// The page shows the passage hidden as soon as the layer opens (not only once listening).
  void _prepare() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = ref.read(reciteControllerProvider);
        if (s.listening || s.phase == RecitePhase.checking) return;
        if (s.passage == null || (s.passage != widget.passage && !s.retrying)) {
          ref.read(reciteControllerProvider.notifier).prepare(widget.passage, widget.quran);
        }
      });

  Future<void> _toggle() async {
    final c = ref.read(reciteControllerProvider.notifier);
    final s = ref.read(reciteControllerProvider);
    switch (s.phase) {
      case RecitePhase.listening:
        return c.pause();
      case RecitePhase.paused:
        return c.resume();
      case RecitePhase.checking:
        return;
      case RecitePhase.idle || RecitePhase.done:
        if (!await ensureReciteModel(context, ref)) return;
        if (!mounted || !await reciteRationale(context, ref)) return;
        await c.start(widget.passage, widget.quran);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(reciteControllerProvider);
    final c = ref.read(reciteControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    // A light tick for each ayah completed (the system's haptic setting applies).
    ref.listen(reciteControllerProvider.select((r) => r.recited), (prev, next) {
      if (prev != null && next > prev) HapticFeedback.selectionClick();
    });
    final p = s.progress;
    final notes = s.notes;
    final label = switch (s.phase) {
      RecitePhase.listening => s.live ? t.reciteListening : t.asrReciteThenCheck,
      RecitePhase.checking => t.asrChecking,
      RecitePhase.paused => t.asrPause,
      _ => t.reciteStart,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ReciteMic(
              available: s.available,
              listening: s.listening,
              progress: s.progressValue,
              level: s.listening ? ref.watch(_levelProvider).valueOrNull ?? 0 : 0,
              onTap: _toggle,
            ),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (s.denied)
                    Text(t.asrMicDenied, style: text.bodySmall?.copyWith(color: YqColors.goldText))
                  else if (s.phase == RecitePhase.checking)
                    const Padding(
                      padding: EdgeInsets.only(top: YqSpace.xs),
                      child: YqSkeleton(child: YqSkeletonBox(width: 120, height: 8)),
                    )
                  else if (s.listening && !s.live)
                    Text(t.asrReciteThenCheckHint, style: const TextStyle(fontSize: 12, color: YqColors.muted))
                  else if (s.started)
                    Text(
                      t.asrSummary(YqFormat.number(s.recited), YqFormat.number(notes.length), YqFormat.number(s.helps)),
                      style: const TextStyle(fontSize: 12, color: YqColors.muted),
                    )
                  else
                    Text(t.asrWordsOnly, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                ],
              ),
            ),
            if (s.listening || s.phase == RecitePhase.paused) YqButton.text(label: t.asrFinish, onPressed: c.finish),
          ],
        ),
        if (p != null && p.ayat.length > 1) ...[
          const SizedBox(height: YqSpace.s),
          _AyahRings(progress: p.ayat.map(p.ayahProgress).toList(), refs: p.ayat),
        ],
        const SizedBox(height: YqSpace.xs),
        Row(
          children: [
            Expanded(child: YqSwitch(label: t.asrShowText, value: s.showText, onChanged: c.setShowText)),
          ],
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: YqSpace.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final w in notes)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: YqSpace.s),
                    child: _NoteChip(word: w, onTap: () => playAyahOnce(ref, w.ayah)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

final _levelProvider = StreamProvider.autoDispose<double>((ref) => ref.watch(recitationEngineProvider).level);

/// One ring per ayah of the passage, filling as the voice moves through it; gold once recited.
class _AyahRings extends StatelessWidget {
  const _AyahRings({required this.progress, required this.refs});
  final List<double> progress;
  final List<AyahRef> refs;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < progress.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: YqSpace.xs),
              child: Semantics(
                label: progress[i] >= 1 ? t.asrAyahDone(YqFormat.number(refs[i].ayah)) : null,
                child: YqRing(value: progress[i], size: 14, stroke: 2, gold: progress[i] >= 1),
              ),
            ),
        ],
      ),
    );
  }
}

/// The microphone as an orb inside a ring of how much of the passage is recited: ink at rest,
/// lapis while listening, breathing gently with the voice level; a shimmering disc while the
/// device is still being asked. Under reduce motion the level never moves anything.
class ReciteMic extends StatelessWidget {
  const ReciteMic({super.key, required this.available, required this.listening, required this.progress, this.level = 0, required this.onTap});
  final bool? available;
  final bool listening;
  final double progress;
  final double level;
  final VoidCallback onTap;

  static const size = 52.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (available == null) return const YqSkeleton(child: YqSkeletonBox.circle(size));
    final reduce = MediaQuery.disableAnimationsOf(context);
    final halo = reduce || !listening ? 0.0 : level.clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: listening ? t.reciteStop : t.reciteStart,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: YqRing(
          value: progress,
          // Gold only once the whole passage is recited.
          gold: progress >= 1,
          size: size,
          stroke: 3,
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : YqMotion.fast,
            width: size - 12,
            height: size - 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listening ? YqColors.lapis : YqColors.navy,
              boxShadow: halo <= 0 ? null : [BoxShadow(color: YqColors.sky.withValues(alpha: 0.5 * halo), blurRadius: 4 + 10 * halo)],
            ),
            child: Icon(listening ? Icons.pause_rounded : Icons.mic_rounded, color: YqColors.goldLight, size: 22),
          ),
        ),
      ),
    );
  }
}

class _NoteChip extends StatelessWidget {
  const _NoteChip({required this.word, required this.onTap});
  final WordResult word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label = word.mark == WordMark.warn ? t.reciteWarn(word.word) : t.asrSkipped(word.word);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YqRadii.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: YqSpace.touch - 8),
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
          decoration: BoxDecoration(
            color: YqColors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(YqRadii.pill),
            border: Border.all(color: YqColors.line),
          ),
          alignment: Alignment.center,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: YqColors.muted)),
        ),
      ),
    );
  }
}
