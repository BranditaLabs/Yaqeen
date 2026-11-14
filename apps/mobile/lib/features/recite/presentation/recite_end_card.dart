import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/quran_data.dart';
import '../domain/recitation.dart';
import '../domain/recite_progress.dart';

/// What the user chose on the end card.
enum ReciteEndAction { done, retryFlagged, grade }

/// The «تسميع» end card (spec §5.12): ayat · notes · helps · time; each flagged word (tap → that
/// ayah once from the user's reciter); «سمّع الملاحظات فقط»; in a hifz/review session the grade
/// sheet follows («متابعة إلى التقييم»). Never says «خطأ»: notes are «تنبيه» and «لم تُسمَع».
Future<ReciteEndAction?> showReciteEndCard(
  BuildContext context, {
  required ReciteProgress progress,
  required ValueChanged<AyahRef> onPlay,
  bool graded = false,
}) =>
    showYqSheet<ReciteEndAction>(
      context,
      scrollable: true,
      builder: (_) => ReciteEndCard(progress: progress, onPlay: onPlay, graded: graded),
    );

class ReciteEndCard extends StatelessWidget {
  const ReciteEndCard({super.key, required this.progress, required this.onPlay, this.graded = false});
  final ReciteProgress progress;
  final ValueChanged<AyahRef> onPlay;
  final bool graded;

  static String clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${YqFormat.number(m)}:${YqFormat.number(s ~/ 10)}${YqFormat.number(s % 10)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final notes = progress.flagged;
    final clean = notes.isEmpty && progress.helps == 0;
    Widget stat(String value, String label) => Expanded(
          child: Semantics(
            label: '$label $value',
            excludeSemantics: true,
            child: Column(
              children: [
                Text(value, style: text.headlineSmall?.copyWith(color: YqColors.ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: YqSpace.xs),
                Text(label, style: text.labelMedium?.copyWith(color: YqColors.muted)),
              ],
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_rounded, size: 40, color: clean ? YqColors.gold : YqColors.lapis),
        const SizedBox(height: YqSpace.s),
        Text(t.asrEndTitle, textAlign: TextAlign.center, style: text.titleLarge),
        const SizedBox(height: YqSpace.l),
        Row(
          children: [
            stat(YqFormat.number(progress.recitedAyat), t.asrStatAyat),
            stat(YqFormat.number(notes.length), t.asrStatNotes),
            stat(YqFormat.number(progress.helps), t.asrStatHelps),
            stat(clock(progress.elapsed), t.asrStatTime),
          ],
        ),
        const SizedBox(height: YqSpace.l),
        if (notes.isEmpty)
          Text(t.asrEndNoNotes, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: YqColors.muted))
        else ...[
          Text(t.asrEndNotesTitle, style: text.titleSmall),
          const SizedBox(height: YqSpace.s),
          Wrap(
            spacing: YqSpace.s,
            runSpacing: YqSpace.s,
            children: [for (final w in notes) _NoteChip(word: w, onTap: () => onPlay(w.ayah))],
          ),
        ],
        const SizedBox(height: YqSpace.s),
        Text(t.asrWordsOnly, textAlign: TextAlign.center, style: text.bodySmall?.copyWith(color: YqColors.muted)),
        const SizedBox(height: YqSpace.l),
        if (notes.isNotEmpty) ...[
          YqButton.secondary(label: t.asrRetryNotes, onPressed: () => Navigator.of(context).pop(ReciteEndAction.retryFlagged)),
          const SizedBox(height: YqSpace.s),
        ],
        YqButton(
          label: graded ? t.asrToGrade : t.asrDone,
          onPressed: () => Navigator.of(context).pop(graded ? ReciteEndAction.grade : ReciteEndAction.done),
        ),
      ],
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
      label: '$label · ${t.asrPlayAyah(YqFormat.number(word.ayah.ayah))}',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YqRadii.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: YqSpace.touch),
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
          decoration: BoxDecoration(
            color: YqColors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(YqRadii.pill),
            border: Border.all(color: YqColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded, size: 18, color: YqColors.lapis),
              const SizedBox(width: YqSpace.xs),
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: YqColors.muted)),
              const SizedBox(width: YqSpace.xs),
              Text('· ${YqFormat.number(word.ayah.ayah)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: YqColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
