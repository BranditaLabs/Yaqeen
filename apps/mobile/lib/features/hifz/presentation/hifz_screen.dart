import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/quran_data.dart';
import '../domain/hifz_plan.dart';
import '../domain/review_scheduler.dart';
import 'hifz_controller.dart';

String hifzGoalLabel(AppLocalizations t, HifzGoal g) => switch (g) {
      HifzGoal.amma => t.hifzGoalAmma,
      HifzGoal.tabarak => t.hifzGoalTabarak,
      HifzGoal.kahf => t.hifzGoalKahf,
      HifzGoal.all => t.hifzGoalAll,
    };

/// `22 · Hifz plan` (spec §5.25). Everything here stays on the device.
class HifzScreen extends ConsumerStatefulWidget {
  const HifzScreen({super.key});

  @override
  ConsumerState<HifzScreen> createState() => _HifzScreenState();
}

class _HifzScreenState extends ConsumerState<HifzScreen> {
  final _steps = <int>{};

  DateTime get _today {
    final n = ref.read(clockProvider)().toLocal();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final plan = ref.watch(hifzControllerProvider);
    final quran = ref.watch(quranDataProvider);

    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: AmbientBackground(
        child: SafeArea(
          child: switch ((plan, quran)) {
            (AsyncError(), _) || (_, AsyncError()) => YqErrorState(onRetry: () => ref.invalidate(hifzControllerProvider)),
            (AsyncData(value: final p), AsyncData(value: final q)) => _body(context, t, p, q),
            _ => const Center(child: CircularProgressIndicator(color: YqColors.lapis)),
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations t, HifzPlan? plan, QuranData q) {
    final text = Theme.of(context).textTheme;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final header = YqTopBar(
      title: t.hifzTitle,
      backLabel: t.hifzBack,
      actions: [if (plan != null) TextButton(onPressed: () => showHifzPlanSheet(context, plan), child: Text(t.hifzEdit))],
    );
    if (plan == null) {
      return YqPage(
        header: header,
        children: [
          const SizedBox(height: YqSpace.xxl),
          LiquidGlass(
            child: YqEmptyState(
              icon: YqIcons.bookmark,
              title: t.hifzStart,
              hint: t.hifzStartHint,
              actionLabel: t.hifzStart,
              onAction: () => showHifzPlanSheet(context, null),
            ),
          ),
        ],
      );
    }

    final today = _today;
    final portion = plan.today(q);
    final due = plan.due(today);
    final upcoming = plan.upcoming(today).take(3).toList();
    final finish = plan.finishEstimate(q, today);
    final doneToday = plan.memorisedToday(today);
    final ctl = ref.read(hifzControllerProvider.notifier);
    final reciteOn = ref.watch(remoteConfigProvider).isOn(Flags.recite);

    return YqPage(
      header: header,
      children: [
        LiquidGlass(
          padding: const EdgeInsets.all(YqSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(hifzGoalLabel(t, plan.goal), style: text.titleLarge)),
                  Text('${YqFormat.number((plan.progress(q) * 100).floor())} %', style: YqText.numeral.copyWith(fontSize: 24)),
                ],
              ),
              const SizedBox(height: YqSpace.m),
              YqProgressLine(value: plan.progress(q), height: 6),
              const SizedBox(height: YqSpace.s),
              Text(
                finish == null ? t.hifzComplete : t.hifzFinish(YqFormat.fullDate(finish, locale)),
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.l),
        if (portion != null)
          YqSection(
            title: t.hifzToday,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.hifzRange(q.surah(portion.surah).nameAr, portion.from, portion.to), style: text.titleSmall),
                const SizedBox(height: YqSpace.s),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Text(
                    [
                      for (var a = portion.from; a <= portion.to; a++)
                        '${q.text(AyahRef(portion.surah, a))} ﴿${YqFormat.toArabicIndic(a)}﴾',
                    ].join(' '),
                    textAlign: TextAlign.justify,
                    style: YqText.quran(size: 22, height: 2.1, color: YqColors.ink),
                  ),
                ),
                const SizedBox(height: YqSpace.m),
                for (final (i, label) in [t.hifzStepListen, t.hifzStepRepeat, t.hifzStepTest].indexed)
                  // ListTiles paint on the nearest Material; the glass card sits above the page colour.
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      value: _steps.contains(i) || doneToday,
                      onChanged: doneToday ? null : (v) => setState(() => v! ? _steps.add(i) : _steps.remove(i)),
                      title: Text(label, style: text.bodyMedium),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: YqColors.lapis,
                      dense: true,
                    ),
                  ),
                const SizedBox(height: YqSpace.s),
                if (reciteOn)
                  YqButton(
                    label: t.hifzReciteNow,
                    onPressed: () => context.push('/quran/recite/${portion.surah}?from=${portion.from}&to=${portion.to}&hifz=1'),
                  )
                else
                  YqButton.secondary(
                    label: t.ayahListen,
                    icon: const YqIcon(YqIcons.listen, size: 18),
                    onPressed: () => context.push('/quran/listen/${portion.surah}?ayah=${portion.from}'),
                  ),
                const SizedBox(height: YqSpace.s),
                YqButton.secondary(label: t.hifzMarkDone, onPressed: doneToday ? null : ctl.memoriseToday),
              ],
            ),
          )
        else
          LiquidGlass(child: YqEmptyState(icon: YqIcons.streak, title: t.hifzComplete)),
        const SizedBox(height: YqSpace.l),
        YqSection(
          title: t.hifzReview,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (due.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: YqSpace.s),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: YqColors.success, size: 20),
                      const SizedBox(width: YqSpace.s),
                      Text(t.hifzReviewDone, style: text.bodyMedium),
                    ],
                  ),
                ),
              for (final p in due) _ReviewCard(portion: p, quran: q, today: today, onRate: (g) => ctl.rate(p.id, g)),
              for (final p in upcoming)
                YqListRow(
                  dense: true,
                  title: t.hifzRange(q.surah(p.surah).nameAr, p.from, p.to),
                  trailing: _Tag(
                    p.review.due.difference(today).inDays == 1 ? t.hifzTomorrow : t.hifzInDays(p.review.due.difference(today).inDays),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.l),
        _HeatStrip(plan: plan, today: today),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.gold = false});
  final String label;
  final bool gold;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.s, vertical: 3),
        decoration: BoxDecoration(color: gold ? YqColors.gold100 : YqColors.sky100, borderRadius: BorderRadius.circular(YqRadii.pill)),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: gold ? YqColors.goldText : YqColors.lapis)),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.portion, required this.quran, required this.today, required this.onRate});
  final HifzPortion portion;
  final QuranData quran;
  final DateTime today;
  final ValueChanged<ReviewGrade> onRate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final ago = today.difference(portion.memorisedOn).inDays;
    final last = today.difference(portion.lastReview ?? portion.memorisedOn).inDays;
    // A passage rated «صعبة» comes back with a 1-day interval — it needs work.
    final needsWork = portion.review.reps > 0 && portion.review.intervalDays == 1;
    final prev = portion.review.intervalDays;
    return Container(
      margin: const EdgeInsets.only(bottom: YqSpace.m),
      padding: const EdgeInsets.all(YqSpace.l),
      decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(YqRadii.tile)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.hifzRange(quran.surah(portion.surah).nameAr, portion.from, portion.to), style: text.titleSmall)),
              _Tag(needsWork ? t.hifzNeedsWork : t.hifzDueToday, gold: needsWork),
            ],
          ),
          const SizedBox(height: YqSpace.xs),
          Text(t.hifzMemorisedAgo(ago, last), style: text.bodySmall),
          const SizedBox(height: YqSpace.m),
          Text(t.hifzHowWasIt, style: text.labelMedium),
          const SizedBox(height: YqSpace.s),
          Row(
            children: [
              for (final (g, label) in [
                (ReviewGrade.hard, t.hifzHard),
                (ReviewGrade.good, t.hifzGood(ReviewScheduler.nextInterval(ReviewGrade.good, prev))),
                (ReviewGrade.easy, t.hifzEasy(ReviewScheduler.nextInterval(ReviewGrade.easy, prev))),
              ]) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onRate(g),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: g == ReviewGrade.hard ? YqColors.goldText : YqColors.lapis,
                      side: const BorderSide(color: YqColors.line),
                      padding: const EdgeInsets.symmetric(vertical: YqSpace.m, horizontal: YqSpace.xs),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(YqRadii.chip)),
                    ),
                    child: Text(label, textAlign: TextAlign.center, style: text.labelMedium?.copyWith(color: null)),
                  ),
                ),
                if (g != ReviewGrade.easy) const SizedBox(width: YqSpace.s),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatStrip extends StatelessWidget {
  const _HeatStrip({required this.plan, required this.today});
  final HifzPlan plan;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final n = plan.activeInLast(14, today);
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return LiquidGlass(
      padding: const EdgeInsets.all(YqSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.hifzStrip(n), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: YqSpace.s),
          Semantics(
            excludeSemantics: true,
            child: Row(
              children: [
                for (var i = 13; i >= 0; i--)
                  Expanded(
                    child: Container(
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: plan.activeDays.contains(iso(today.subtract(Duration(days: i)))) ? YqColors.lapis : YqColors.sky100,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «خطتي» — goal and daily amount, with a live finish estimate.
Future<void> showHifzPlanSheet(BuildContext context, HifzPlan? current) => showYqSheet<void>(
      context,
      scrollable: true,
      builder: (_) => _PlanSheet(current: current),
    );

class _PlanSheet extends ConsumerStatefulWidget {
  const _PlanSheet({this.current});
  final HifzPlan? current;

  @override
  ConsumerState<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends ConsumerState<_PlanSheet> {
  late HifzGoal _goal = widget.current?.goal ?? HifzGoal.amma;
  late int _perDay = widget.current?.perDay ?? 5;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final q = ref.watch(quranDataProvider).valueOrNull;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    if (q == null) return const SizedBox(height: 200);
    final now = ref.read(clockProvider)().toLocal();
    final preview = (widget.current ?? HifzPlan(goal: _goal, perDay: _perDay)).copyWith(goal: _goal, perDay: _perDay);
    final finish = preview.finishEstimate(q, now);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.hifzPlanSheet, style: text.titleLarge),
        const SizedBox(height: YqSpace.m),
        Material(
          type: MaterialType.transparency,
          child: RadioGroup<HifzGoal>(
            groupValue: _goal,
            onChanged: (g) => setState(() => _goal = g ?? _goal),
            child: Column(
              children: [
                for (final g in HifzGoal.values)
                  RadioListTile<HifzGoal>(
                    value: g,
                    activeColor: YqColors.lapis,
                    contentPadding: EdgeInsets.zero,
                    title: Text(hifzGoalLabel(t, g), style: text.titleSmall),
                    subtitle: Text(
                      g == HifzGoal.kahf ? t.quranAyahCount(g.ayat(q)) : t.hifzGoalMeta(g.surahs.length, g.ayat(q)),
                      style: text.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: YqSpace.m),
        Text(t.hifzPerDay, style: text.labelLarge),
        Row(
          children: [
            IconButton(
              tooltip: '−',
              onPressed: _perDay > HifzPlan.minPerDay ? () => setState(() => _perDay--) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded, color: YqColors.lapis),
            ),
            Expanded(child: Text(t.hifzPerDayValue(_perDay), textAlign: TextAlign.center, style: text.titleMedium)),
            IconButton(
              tooltip: '+',
              onPressed: _perDay < HifzPlan.maxPerDay ? () => setState(() => _perDay++) : null,
              icon: const Icon(Icons.add_circle_outline_rounded, color: YqColors.lapis),
            ),
          ],
        ),
        Text(
          finish == null ? t.hifzComplete : t.hifzFinish(YqFormat.fullDate(finish, locale)),
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
        const SizedBox(height: YqSpace.l),
        YqButton(
          label: t.hifzSavePlan,
          onPressed: () async {
            await ref.read(hifzControllerProvider.notifier).savePlan(_goal, _perDay);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
