import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/level.dart';

/// The six levels, the person's own in lapis, a gold dot on each level already reached, and the
/// rule that spending points never lowers a level.
Future<void> showLevelLadderSheet(BuildContext context, CardLevel current) =>
    showYqSheet<void>(context, scrollable: true, builder: (_) => LevelLadder(current: current));

class LevelLadder extends StatelessWidget {
  const LevelLadder({super.key, required this.current});
  final CardLevel current;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.pfLadderTitle, style: text.titleLarge)),
        const SizedBox(height: YqSpace.m),
        for (var i = cardLevels.length - 1; i >= 0; i--)
          _Rung(
            level: i + 1,
            name: locale == 'ar' ? cardLevels[i].$2 : cardLevels[i].$3,
            from: cardLevels[i].$1,
            current: current.level == i + 1,
            reached: current.level >= i + 1,
          ),
        const SizedBox(height: YqSpace.m),
        Text(t.pfLadderNote, style: text.bodySmall?.copyWith(height: 1.6)),
      ],
    );
  }
}

class _Rung extends StatelessWidget {
  const _Rung({required this.level, required this.name, required this.from, required this.current, required this.reached});
  final int level;
  final String name;
  final int from;
  final bool current;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final points = t.pfLadderFrom(YqFormat.number(from));
    return Semantics(
      container: true,
      selected: current,
      label: [t.lvlCaption(YqFormat.number(level), name), points, if (current) t.pfLadderCurrent].reduce(t.pfSemanticsJoin),
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: YqMotion.base,
        constraints: const BoxConstraints(minHeight: YqSpace.touch + 8),
        margin: const EdgeInsets.only(bottom: YqSpace.xs),
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.s),
        decoration: BoxDecoration(
          color: current ? YqColors.lapis.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(YqRadii.chip),
          border: Border.all(color: current ? YqColors.lapis.withValues(alpha: 0.35) : YqColors.line.withValues(alpha: 0)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: current ? YqColors.lapis : YqColors.white,
                border: Border.all(color: current ? YqColors.lapis : YqColors.line, width: 1.5),
              ),
              child: Text(
                YqFormat.number(level),
                style: YqText.numeral.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: current ? YqColors.white : YqColors.ink),
              ),
            ),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: current ? YqColors.lapis : YqColors.ink),
                  ),
                  Text(current ? '${t.pfLadderCurrent} · $points' : points, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                ],
              ),
            ),
            // Gold only for what was earned: a small dot on each level reached.
            if (reached)
              Container(
                key: const ValueKey('ladder-reached'),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: YqColors.gold),
              ),
          ],
        ),
      ),
    );
  }
}
