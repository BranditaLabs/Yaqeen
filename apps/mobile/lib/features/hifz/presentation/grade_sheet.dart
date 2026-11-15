import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/review_scheduler.dart';

/// `GradeSheet` (spec §6.14): «كيف كانت المراجعة؟» with the guided test's suggestion pre-selected
/// («اقتراح: {grade}»); nothing is saved until «تأكيد». Returns the confirmed grade, or null.
///
/// [previousInterval] labels each grade with when the passage comes back; a [fresh] passage
/// (memorised today) always comes back tomorrow, whatever the grade.
Future<ReviewGrade?> showGradeSheet(BuildContext context, {required ReviewGrade suggestion, int previousInterval = 0, bool fresh = false}) =>
    showYqSheet<ReviewGrade>(
      context,
      builder: (_) => GradeSheet(suggestion: suggestion, previousInterval: previousInterval, fresh: fresh),
    );

/// The label of [g] on the review card and the grade sheet.
String gradeLabel(AppLocalizations t, ReviewGrade g, {int previousInterval = 0, bool fresh = false}) => switch (g) {
      ReviewGrade.hard => t.hifzHard,
      ReviewGrade.good => t.hifzGood(fresh ? 1 : ReviewScheduler.nextInterval(ReviewGrade.good, previousInterval)),
      ReviewGrade.easy => t.hifzEasy(fresh ? 1 : ReviewScheduler.nextInterval(ReviewGrade.easy, previousInterval)),
    };

class GradeSheet extends StatefulWidget {
  const GradeSheet({super.key, required this.suggestion, this.previousInterval = 0, this.fresh = false});
  final ReviewGrade suggestion;
  final int previousInterval;
  final bool fresh;

  @override
  State<GradeSheet> createState() => _GradeSheetState();
}

class _GradeSheetState extends State<GradeSheet> {
  late ReviewGrade _grade = widget.suggestion;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    String label(ReviewGrade g) => gradeLabel(t, g, previousInterval: widget.previousInterval, fresh: widget.fresh);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.hifzHowWasIt, style: text.titleLarge),
        const SizedBox(height: YqSpace.xs),
        Text(t.qsSuggestion(label(widget.suggestion)), style: text.bodyMedium?.copyWith(color: YqColors.muted)),
        const SizedBox(height: YqSpace.l),
        for (final g in ReviewGrade.values)
          Padding(
            padding: const EdgeInsets.only(bottom: YqSpace.s),
            child: Semantics(
              selected: g == _grade,
              button: true,
              child: OutlinedButton(
                onPressed: () => setState(() => _grade = g),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(YqSpace.touch),
                  foregroundColor: g == ReviewGrade.hard ? YqColors.goldText : YqColors.lapis,
                  backgroundColor: g == _grade ? YqColors.sky100 : null,
                  side: BorderSide(color: g == _grade ? YqColors.lapis : YqColors.line, width: g == _grade ? 1.5 : 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YqRadii.chip)),
                ),
                child: Text(label(g), style: text.labelLarge?.copyWith(color: null)),
              ),
            ),
          ),
        const SizedBox(height: YqSpace.s),
        YqButton(label: t.qsConfirm, onPressed: () => Navigator.of(context).pop(_grade)),
      ],
    );
  }
}
