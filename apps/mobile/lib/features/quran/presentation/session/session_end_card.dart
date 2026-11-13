import 'package:flutter/material.dart';

import '../../../../core/format.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_ring.dart';
import '../../../../core/widgets/yq_states.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// What follows a session, offered on its end card.
enum SessionNext {
  /// A hifz review is due: «مراجعة مستحقّة».
  review,

  /// Today's hifz passage is waiting: «التالي: ابدأ الحلقة».
  hifz,

  /// The khatma portion by ear: «التالي: استمع إلى الحصّة».
  khatmaListen,
}

/// `SessionEndCard`: «أتممت جلستك» with the session's ring — gold, with one glint, only when its goal
/// was met — and the next step. Returns true when the user takes that next step.
Future<bool?> showSessionEndCard(BuildContext context, {required bool met, required int done, required int goal, SessionNext? next}) =>
    showYqSheet<bool>(context, builder: (_) => SessionEndCard(met: met, done: done, goal: goal, next: next));

class SessionEndCard extends StatelessWidget {
  const SessionEndCard({super.key, required this.met, required this.done, required this.goal, this.next});
  final bool met;
  final int done;
  final int goal;
  final SessionNext? next;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final step = switch (next) {
      SessionNext.review => t.qsReviewDue,
      SessionNext.hifz => t.qsNext(t.qsStartHalaqa),
      SessionNext.khatmaListen => t.qsNext(t.qsListenPortion),
      null => null,
    };
    final action = switch (next) {
      SessionNext.review => t.qsReview,
      SessionNext.hifz => t.qsStartHalaqa,
      SessionNext.khatmaListen => t.qsListenPortion,
      null => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: YqRing(
            value: goal == 0 ? 1 : done / goal,
            size: 72,
            stroke: 5,
            gold: met,
            glint: met,
            child: Text(
              '${YqFormat.number(done)}/${YqFormat.number(goal)}',
              textDirection: TextDirection.ltr,
              style: text.titleMedium?.copyWith(color: met ? YqColors.goldText : YqColors.ink),
            ),
          ),
        ),
        const SizedBox(height: YqSpace.m),
        Text(t.qsSessionDone, textAlign: TextAlign.center, style: text.titleLarge),
        if (step != null) ...[
          const SizedBox(height: YqSpace.xs),
          Text(step, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: YqColors.muted)),
        ],
        const SizedBox(height: YqSpace.l),
        if (action != null) ...[
          YqButton(label: action, onPressed: () => Navigator.of(context).pop(true)),
          const SizedBox(height: YqSpace.s),
          YqButton.secondary(label: t.close, onPressed: () => Navigator.of(context).pop(false)),
        ] else
          YqButton(label: t.close, onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
