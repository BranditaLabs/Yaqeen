import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/motion.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_live_level.dart';
import '../../../core/widgets/yq_play_ring.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/passage.dart';
import '../../quran/domain/quran_data.dart';
import '../../recite/domain/recitation.dart';
import '../../recite/presentation/asr_model_sheet.dart';
import '../domain/client_check.dart';
import '../domain/recording_models.dart';
import '../domain/verse_selection.dart';
import 'recorder_controller.dart';
import 'recording_widgets.dart';
import 'recordings_providers.dart';
import 'share_gate.dart';
import 'verse_words_view.dart';

/// `/profile/recordings/record?surah=&from=&to=` — the live recorder and the review (APP_SPEC §5.24).
///
/// Full-screen porcelain stage: the chosen ayat large in the mushaf font, centred. «ابدأ» → 3-2-1 →
/// a breathing «مباشر» pill (lapis, never red), `YqLiveLevel` from the real microphone, a 30-second
/// ring round the stop button (stops by itself at 30 s with a haptic). Words light up as the phone's
/// recogniser hears them (a word not heard gets a quiet ink underline) and the view keeps the voice
/// in sight; without the model, or on a slow phone, the view moves with time as «دليل الإيقاع».
/// Review: play the take (`YqPlayRing`, karaoke from the on-device check), the check's advice,
/// re-record, who hears it, comments, «حفظ». Reduce motion: a still pill and bars, the ring still
/// counts, words light without animation.
class RecorderScreen extends ConsumerStatefulWidget {
  const RecorderScreen({super.key, required this.passage});
  final Passage passage;

  @override
  ConsumerState<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends ConsumerState<RecorderScreen> {
  Map<(int, int), int>? _index;

  RecorderController get _c => ref.read(recorderProvider(widget.passage).notifier);

  int _globalIndex(int ayah, int index) {
    final map = _index ??= {for (final (i, w) in _c.words.indexed) (w.ayah.ayah, w.index): i};
    return map[(ayah, index)] ?? -1;
  }

  Future<bool> _confirmDiscard() async {
    final s = ref.read(recorderProvider(widget.passage));
    // Saving: the take is on its way (upload or this phone) — leaving now could not take it back.
    if (s.phase == RecorderPhase.saving) return false;
    // Encoding has no clip yet, but the take is being written: it is discarded like one on review.
    final busy = s.phase == RecorderPhase.recording ||
        s.phase == RecorderPhase.countIn ||
        s.phase == RecorderPhase.encoding ||
        (s.clip != null && s.phase != RecorderPhase.saved);
    if (!busy) return true;
    final t = AppLocalizations.of(context);
    final ok = await showYqSheet<bool>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.recDiscardTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: YqSpace.l),
          YqButton(key: const ValueKey('rec-discard-yes'), label: t.recDiscard, onPressed: () => Navigator.of(context).pop(true)),
          const SizedBox(height: YqSpace.s),
          YqButton.text(label: t.cancel, onPressed: () => Navigator.of(context).pop(false), expand: true),
        ],
      ),
    );
    if (ok == true) await _c.discard();
    return ok == true;
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    var outcome = await _c.save();
    final err = ref.read(recorderProvider(widget.passage)).error;
    if (outcome == null && err != null && isShareGate(err) && mounted) {
      if (await showShareGate(context)) outcome = await _c.save();
    }
    if (outcome == null || !mounted) return;
    final message = switch (outcome) {
      SaveOutcome.uploaded => t.recSaved,
      SaveOutcome.queued => t.recSavedQueued,
      SaveOutcome.local => t.recSavedLocal,
      SaveOutcome.later => t.recSavedLater,
    };
    YqToast.show(context, message);
    context.go('/profile');
  }

  Future<void> _chooseVisibility(RecordingVisibility v) async {
    if (v != RecordingVisibility.private && !await ensureAccountForSharing(context, ref)) return;
    _c.setVisibility(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(recorderProvider(widget.passage));
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final p = widget.passage;
    // A link with a range past the surah: back to the picker on the nearest valid range.
    if (quran != null && checkedPassage(quran, p) != p) {
      final fixed = checkedPassage(quran, p);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.replace(fixed == null ? '/profile/recordings/new' : '/profile/recordings/new?surah=${fixed.surah}&from=${fixed.from}&to=${fixed.to}');
      });
      return const Scaffold(backgroundColor: YqColors.porcelain);
    }
    final ayat = quran == null ? const <(AyahRef, String)>[] : p.expected(quran);
    final words = _c.words;
    final total = words.length;

    // Which word is current, and how each word looks, in this phase.
    int? current;
    WordLook Function(int ayah, int index) lookOf = (_, __) => WordLook.plain;
    if (s.phase == RecorderPhase.recording || s.phase == RecorderPhase.encoding) {
      if (s.mode == FollowMode.live) {
        current = s.frontier < total ? s.frontier : null;
        lookOf = (a, i) {
          final g = _globalIndex(a, i);
          if (g < 0) return WordLook.plain;
          final m = g < s.marks.length ? s.marks[g] : null;
          if (m == WordMark.ok) return WordLook.lit;
          if (m == WordMark.warn || m == WordMark.skipped) return WordLook.skipped;
          if (g < s.frontier) return WordLook.lit;
          if (g == s.frontier) return WordLook.current;
          return WordLook.plain;
        };
      } else if (total > 0) {
        // The pacing guide: the expected place at a calm pace, a soft wash only.
        final est = estimateFor(total).inMilliseconds;
        final at = ((s.elapsed.inMilliseconds / (est <= 0 ? 1 : est)) * total).floor().clamp(0, total - 1);
        current = at;
        lookOf = (a, i) => _globalIndex(a, i) == at ? WordLook.current : WordLook.plain;
      }
    } else if (s.phase == RecorderPhase.review || s.phase == RecorderPhase.saving) {
      final play = ref.watch(recordingPlayerProvider);
      final check = s.check;
      if (check != null) {
        final started = play.isOf('take');
        lookOf = (a, i) {
          final k = Karaoke.lookAt(check.words, play.position, a, i, started: started);
          if (k != WordLook.plain) return k;
          final g = _globalIndex(a, i);
          final m = g >= 0 && g < check.marks.length ? check.marks[g] : null;
          return m != null && m != WordMark.ok && !started ? WordLook.skipped : WordLook.plain;
        };
        final cur = started ? Karaoke.currentAt(check.words, play.position) : null;
        if (cur != null) current = _globalIndex(cur.$1, cur.$2);
      }
    }
    final currentWord = current == null || current < 0 || current >= total ? null : (words[current].ayah.ayah, words[current].index);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) context.pop();
      },
      child: Scaffold(
        backgroundColor: YqColors.porcelain,
        body: AmbientBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: YqInsets.page,
                  child: Row(
                    children: [
                      YqBackButton(
                        onPressed: () async {
                          if (await _confirmDiscard() && context.mounted) context.pop();
                        },
                      ),
                      const SizedBox(width: YqSpace.m),
                      Expanded(child: VerseRefText(surah: p.surah, from: p.from, to: p.to, style: Theme.of(context).textTheme.titleMedium)),
                      if (s.phase == RecorderPhase.recording) const _LivePill(),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: YqSpace.gutter, vertical: YqSpace.xxl),
                          child: ayat.isEmpty
                              ? const YqSkeleton(child: YqSkeletonText(lines: 4, lineHeight: 28))
                              : VerseWordsView(
                                  key: const ValueKey('rec-verses'),
                                  ayat: ayat,
                                  lookOf: lookOf,
                                  current: currentWord,
                                  follow: true,
                                  fontSize: 30,
                                  semanticsLabel: t.recWordsA11y,
                                ),
                        ),
                      ),
                      if (s.phase == RecorderPhase.countIn) Positioned.fill(child: _CountIn(value: s.countIn)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(YqSpace.gutter, YqSpace.s, YqSpace.gutter, YqSpace.l),
                  child: YqFadeSwap(
                    alignment: Alignment.bottomCenter,
                    child: switch (s.phase) {
                      RecorderPhase.ready || RecorderPhase.denied => _ReadyPanel(key: const ValueKey('rec-ready'), state: s, controller: _c),
                      RecorderPhase.countIn => _RecordingPanel(key: const ValueKey('rec-recording'), state: s, controller: _c),
                      RecorderPhase.recording || RecorderPhase.encoding => _RecordingPanel(key: const ValueKey('rec-recording'), state: s, controller: _c),
                      RecorderPhase.review || RecorderPhase.saving || RecorderPhase.saved => _ReviewPanel(
                          key: const ValueKey('rec-review'),
                          state: s,
                          passage: p,
                          onAgain: _c.again,
                          onSave: _save,
                          onVisibility: _chooseVisibility,
                          onComments: _c.setComments,
                        ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «مباشر» / LIVE: a lapis pill whose dot breathes (opacity only) while the take runs (≤ 30 s);
/// still under reduce motion.
class _LivePill extends StatefulWidget {
  const _LivePill();

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c
        ..stop()
        ..value = 1;
    } else if (!_c.isAnimating) {
      // Bounded by the take itself (≤ 30 s): the pill leaves when recording stops.
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: t.recLive,
      child: Container(
        key: const ValueKey('rec-live-pill'),
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: 6),
        decoration: BoxDecoration(color: YqColors.lapis, borderRadius: BorderRadius.circular(YqRadii.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
              child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: YqColors.white, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 6),
            ExcludeSemantics(child: Text(t.recLive, style: const TextStyle(color: YqColors.white, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.4))),
          ],
        ),
      ),
    );
  }
}

/// 3 · 2 · 1 over the verses (a soft scale-in; at once under reduce motion).
class _CountIn extends StatelessWidget {
  const _CountIn({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ColoredBox(
      color: YqColors.porcelain.withValues(alpha: 0.82),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: motionOr(context, Motion.standard),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(scale: Tween<double>(begin: 1.25, end: 1).animate(CurvedAnimation(parent: a, curve: Motion.emphasisedCurve)), child: child),
            ),
            child: Text(
              YqFormat.number(value),
              key: ValueKey('rec-count-$value'),
              style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w300, color: YqColors.lapis, height: 1),
            ),
          ),
          const SizedBox(height: YqSpace.m),
          Text(t.recGetReady, style: const TextStyle(color: YqColors.muted)),
        ],
      ),
    );
  }
}

class _ReadyPanel extends ConsumerWidget {
  const _ReadyPanel({super.key, required this.state, required this.controller});
  final RecorderState state;
  final RecorderController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final denied = state.phase == RecorderPhase.denied;
    final note = state.tooShort ? t.recTooShort : (state.encodeFailed ? t.recEncodeFailed : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiquidGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.mic_none_rounded, color: YqColors.lapis),
                  const SizedBox(width: YqSpace.m),
                  Expanded(child: Text(denied ? t.recMicDenied : t.recMicBody, key: ValueKey(denied ? 'rec-denied' : 'rec-mic-body'), style: text.bodyMedium?.copyWith(height: 1.5))),
                ],
              ),
              if (note != null) ...[const SizedBox(height: YqSpace.s), InlineNote(note)],
              if (state.modelOffer && !denied) ...[
                const SizedBox(height: YqSpace.s),
                YqListRow(
                  dense: true,
                  title: t.recModelOffer,
                  onTap: () => ensureReciteModel(context, ref),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m),
        if (denied) ...[
          YqButton(key: const ValueKey('rec-open-settings'), label: t.recOpenSettings, onPressed: () => ref.read(voiceRecorderProvider).openSettings()),
          const SizedBox(height: YqSpace.s),
          YqButton.secondary(label: t.retry, onPressed: controller.begin),
        ] else
          _RecordButton(key: const ValueKey('rec-start'), recording: false, progress: 0, label: t.recStart, onTap: controller.begin),
      ],
    );
  }
}


class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({super.key, required this.state, required this.controller});
  final RecorderState state;
  final RecorderController controller;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final left = (state.left.inMilliseconds / 1000).ceil();
    final recording = state.phase == RecorderPhase.recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.phase != RecorderPhase.countIn) ...[
          Text(
            state.mode == FollowMode.live ? t.recFollowing : t.recPacingGuide,
            key: ValueKey('rec-mode-${state.mode.name}'),
            style: const TextStyle(fontSize: 12.5, color: YqColors.muted),
          ),
          const SizedBox(height: YqSpace.s),
          YqLiveLevel(key: const ValueKey('rec-level'), levels: controller.level, bars: 7, height: 32),
          const SizedBox(height: YqSpace.m),
        ],
        Semantics(
          label: t.recCountdownA11y(YqFormat.number(left)),
          excludeSemantics: true,
          child: _RecordButton(
            key: const ValueKey('rec-stop'),
            recording: true,
            progress: state.elapsed.inMilliseconds / kRecordingMaxMs,
            label: state.phase == RecorderPhase.encoding ? t.recSave : t.recTapToStop,
            onTap: recording ? () => controller.stop() : null,
          ),
        ),
        const SizedBox(height: YqSpace.s),
        Text(
          state.autoStopped ? t.recReachedLimit(YqFormat.number(kRecordingMaxMs ~/ 1000)) : t.recSecondsLeft(YqFormat.number(left)),
          key: const ValueKey('rec-left'),
          style: const TextStyle(fontSize: 13, color: YqColors.muted, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}

/// The record / stop button inside the 30-second ring.
class _RecordButton extends StatelessWidget {
  const _RecordButton({super.key, required this.recording, required this.progress, required this.label, required this.onTap});
  final bool recording;
  final double progress;
  final String label;
  final VoidCallback? onTap;

  static const size = 88.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: GlassTap(
            onTap: onTap,
            pressScale: 0.94,
            child: YqRing(
              value: progress.clamp(0.0, 1.0),
              change: Duration.zero,
              size: size,
              stroke: 4,
              color: YqColors.lapis,
              track: YqColors.lapis100.withValues(alpha: 0.6),
              child: Container(
                width: size - 22,
                height: size - 22,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: YqColors.white),
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: motionOr(context, Motion.standard),
                  curve: Motion.easeOut,
                  width: recording ? 24 : 30,
                  height: recording ? 24 : 30,
                  decoration: BoxDecoration(color: YqColors.lapis, borderRadius: BorderRadius.circular(recording ? 6 : 15)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: YqSpace.s),
        ExcludeSemantics(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: YqColors.ink))),
      ],
    );
  }
}

class _ReviewPanel extends ConsumerWidget {
  const _ReviewPanel({
    super.key,
    required this.state,
    required this.passage,
    required this.onAgain,
    required this.onSave,
    required this.onVisibility,
    required this.onComments,
  });

  final RecorderState state;
  final Passage passage;
  final VoidCallback onAgain;
  final VoidCallback onSave;
  final ValueChanged<RecordingVisibility> onVisibility;
  final ValueChanged<bool> onComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final play = ref.watch(recordingPlayerProvider);
    final clip = state.clip;
    final ms = clip?.duration.inMilliseconds ?? 0;
    final saving = state.phase == RecorderPhase.saving || state.phase == RecorderPhase.saved;
    final shared = state.visibility != RecordingVisibility.private;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiquidGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  YqPlayRing(
                    key: const ValueKey('rec-review-play'),
                    playing: play.isOf('take') && play.playing,
                    progress: play.progressOf('take', ms),
                    orbit: true,
                    onPressed: clip == null
                        ? null
                        : () => ref.read(recordingPlayerProvider.notifier).toggle('take', () async => File(clip.path), title: t.recTitle),
                  ),
                  const SizedBox(width: YqSpace.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.recReviewTitle, style: text.titleSmall),
                        Text(secondsText(t, ms), style: const TextStyle(color: YqColors.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: YqSpace.s),
              YqFadeSwap(
                child: state.checking
                    ? const YqSkeleton(key: ValueKey('rec-checking'), child: YqSkeletonLine(widthFactor: 0.7))
                    : _CheckAdvice(key: const ValueKey('rec-check'), check: state.check),
              ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m),
        Text(t.recWhoHears, style: text.titleSmall),
        const SizedBox(height: YqSpace.s),
        YqSegmented<RecordingVisibility>(
          segments: [for (final v in RecordingVisibility.values) (v, visibilityLabel(t, v))],
          selected: state.visibility,
          onChanged: saving ? (_) {} : onVisibility,
        ),
        const SizedBox(height: YqSpace.xs),
        Text(visibilityHint(t, state.visibility), style: const TextStyle(fontSize: 12, color: YqColors.muted)),
        if (shared)
          YqListRow(
            dense: true,
            title: t.recAllowComments,
            trailing: YqSwitch(label: t.recAllowComments, value: state.commentsOn, onChanged: saving ? (_) {} : onComments),
          ),
        if (state.error != null) ...[const SizedBox(height: YqSpace.s), InlineNote(failureText(t, state.error!))],
        const SizedBox(height: YqSpace.m),
        Row(
          children: [
            Expanded(child: YqButton.secondary(key: const ValueKey('rec-again'), label: t.recRerecord, onPressed: saving ? null : onAgain)),
            const SizedBox(width: YqSpace.s),
            Expanded(child: YqButton(key: const ValueKey('rec-save'), label: t.recSave, loading: saving, onPressed: saving ? null : onSave)),
          ],
        ),
      ],
    );
  }
}

/// The on-device check's advice (advisory, quiet ink; never «خطأ»).
class _CheckAdvice extends StatelessWidget {
  const _CheckAdvice({super.key, required this.check});
  final ClientCheck? check;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = check;
    if (c == null) return const SizedBox(width: double.infinity);
    final flagged = c.flaggedAyat;
    final line = switch (c.verdict) {
      ClientVerdict.clean => t.recCheckClean,
      ClientVerdict.mostly => flagged.length == 1 ? t.recCheckFlagged(YqFormat.number(flagged.single.ayah)) : t.recCheckFlaggedMany(YqFormat.number(flagged.length)),
      ClientVerdict.notMatching => t.recCheckNotMatching,
      ClientVerdict.unclear => t.recCheckUnclear,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(line, key: ValueKey('rec-verdict-${c.verdict.name}'), style: const TextStyle(fontWeight: FontWeight.w600, color: YqColors.ink, height: 1.5)),
        const SizedBox(height: 2),
        Text(t.recCheckAdvisory, style: const TextStyle(fontSize: 11.5, color: YqColors.muted, height: 1.5)),
      ],
    );
  }
}
