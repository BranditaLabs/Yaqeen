import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/controls.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_ring.dart';
import '../../../../core/widgets/yq_states.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../listen/presentation/listen_controller.dart';
import '../../../recite/domain/recitation.dart';
import '../../../recite/presentation/recite_controller.dart';
import '../../domain/passage.dart';
import '../../domain/quran_data.dart';

/// Plays one ayah once — the way to hear a «تنبيه» again.
Future<void> playAyahOnce(WidgetRef ref, AyahRef a) =>
    ref.read(listenControllerProvider.notifier).open(a.surah, ayah: a.ayah, to: a.ayah, times: 1);

/// «تسميع» over the page: the microphone (a ring of how much is recited), «إظهار الآيات», and once
/// started «{ayat} آيات · {notes} ملاحظات» with each «تنبيه» — a tap plays that ayah once. Copy says
/// «تنبيه», never «خطأ».
class ReciteStrip extends ConsumerWidget {
  const ReciteStrip({super.key, required this.quran, required this.passage});

  final QuranData quran;

  /// What is recited: the session's passage, else the page's (`Passage.ofPage`).
  final Passage passage;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final c = ref.read(reciteControllerProvider.notifier);
    final s = ref.read(reciteControllerProvider);
    if (s.listening) return c.stop();
    if (!await c.rationaleSeen()) {
      if (!context.mounted) return;
      final ok = await _rationale(context);
      if (ok != true) return;
      await c.markRationaleSeen();
    }
    await c.start(passage, quran);
  }

  Future<bool?> _rationale(BuildContext context) {
    final t = AppLocalizations.of(context);
    return showYqSheet<bool>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mic_none_rounded, size: 40, color: YqColors.lapis),
          const SizedBox(height: YqSpace.m),
          Text(t.reciteMicRationale, textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleMedium),
          const SizedBox(height: YqSpace.l),
          YqButton(label: t.reciteStart, onPressed: () => Navigator.of(c).pop(true)),
          const SizedBox(height: YqSpace.s),
          YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(reciteControllerProvider);
    final c = ref.read(reciteControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    if (s.available == false) return Text(t.reciteUnavailable, style: text.bodySmall);
    final notes = s.notes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ReciteMic(
              available: s.available,
              listening: s.listening,
              progress: s.progress,
              onTap: () => _toggle(context, ref),
            ),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.listening ? t.reciteListening : t.reciteStart, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  if (s.started)
                    Text(
                      t.qsReciteSummary(YqFormat.number(s.recited), YqFormat.number(notes.length)),
                      style: const TextStyle(fontSize: 12, color: YqColors.muted),
                    ),
                ],
              ),
            ),
            YqSwitch(label: t.reciteShowAyat, value: s.showAyat, onChanged: c.setShowAyat),
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

/// The microphone as an orb inside a ring of how much of the passage is recited: ink at rest,
/// lapis while listening; a shimmering disc while the device is still being asked. The ring never
/// pulses (a static ring under reduce-motion and otherwise).
class ReciteMic extends StatelessWidget {
  const ReciteMic({super.key, required this.available, required this.listening, required this.progress, required this.onTap});
  final bool? available;
  final bool listening;
  final double progress;
  final VoidCallback onTap;

  static const size = 52.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (available == null) return const YqSkeleton(child: YqSkeletonBox.circle(size));
    final reduce = MediaQuery.disableAnimationsOf(context);
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
            duration: reduce ? Duration.zero : YqMotion.base,
            width: size - 12,
            height: size - 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: listening ? YqColors.lapis : YqColors.navy),
            child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: YqColors.goldLight, size: 22),
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
    return Semantics(
      button: true,
      label: t.reciteWarn(word.word),
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
          child: Text(t.reciteWarn(word.word), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: YqColors.muted)),
        ),
      ),
    );
  }
}
