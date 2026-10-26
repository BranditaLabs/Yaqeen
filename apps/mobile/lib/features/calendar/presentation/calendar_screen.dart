import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/zoned.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../core/widgets/yq_timeline.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../challenge/domain/challenge_models.dart';
import '../../challenge/presentation/challenge_controller.dart';
import '../../challenge/presentation/challenge_screen.dart';

const hijriMonthsEn = [
  'Muharram', 'Safar', 'Rabiʿ al-Awwal', 'Rabiʿ al-Thani', 'Jumada al-Ula', 'Jumada al-Akhirah',
  'Rajab', 'Shaʿban', 'Ramadan', 'Shawwal', 'Dhu al-Qaʿdah', 'Dhu al-Hijjah', //
];

String hijriMonthName(CalendarCell c, String locale) =>
    locale == 'ar' ? c.hijriMonthNameAr : hijriMonthsEn[(c.hijriMonth - 1).clamp(0, 11)];

final calendarMonthProvider = FutureProvider.autoDispose.family<ChallengeCalendar, String>(
  (ref, month) => ref.read(challengeRepositoryProvider).calendar(month),
);

String statusLabel(AppLocalizations t, CalendarCell c) => switch (c.challenge?.status) {
      null => t.calOutside,
      DayStatus.done => t.calDone,
      DayStatus.partial => t.calPartial,
      DayStatus.qada => t.calQada,
      DayStatus.missed => t.calMissed,
      DayStatus.today => t.calToday,
      DayStatus.future => t.calFuture,
    };

String specialLabel(AppLocalizations t, SpecialDay d) => switch (d) {
      SpecialDay.whiteDay => t.calWhiteDays,
      SpecialDay.friday => t.calFriday,
      SpecialDay.monThu => t.calMonThu,
      SpecialDay.ramadan => t.calRamadan,
      SpecialDay.eidFitr => t.calEidFitr,
      SpecialDay.eidAdha => t.calEidAdha,
      SpecialDay.arafah => t.calArafah,
      SpecialDay.ashura => t.calAshura,
    };

/// `18 · Calendar of Yaqeen` (spec §5.21). Week starts Saturday; missed days are slate, never red.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    final today = Zoned.today(s.placeOrDefault.timezone, ref.read(clockProvider)());
    _month = DateTime(today.year, today.month);
  }

  String get _key => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  void _shift(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cal = ref.watch(calendarMonthProvider(_key));
    final locale = ref.watch(settingsProvider.select((s) => s.locale));

    final c = cal.valueOrNull;
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        lights: AmbientBackground.goldLights,
        bottom: YqSpace.xxl,
        stage: YqStage(
          compact: true,
          gold: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(back: true, title: t.challengeCalendar, backLabel: t.calendarBack),
              const SizedBox(height: YqSpace.l),
              Row(
                children: [
                  GlassIconButton(
                    tooltip: t.calendarPrev,
                    size: 40,
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left_rounded, color: YqColors.ink),
                  ),
                  Expanded(
                    child: c == null
                        ? Text('${YqFormat.month(_month.month, locale)} ${_month.year}', textAlign: TextAlign.center)
                        : _MonthHeader(cal: c, locale: locale, month: _month),
                  ),
                  GlassIconButton(
                    tooltip: t.calendarNext,
                    size: 40,
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right_rounded, color: YqColors.ink),
                  ),
                ],
              ),
            ],
          ),
        ),
        children: [
          ...cal.when(
            loading: () => [const YqSkeleton(child: YqSkeletonBox(height: 360, radius: YqRadii.card))],
            error: (_, __) => [YqErrorState(onRetry: () => ref.invalidate(calendarMonthProvider(_key)))],
            data: (c) => [
              if (c.enrolled) ...[_Journey(cal: c, locale: locale), const SizedBox(height: YqSpace.xl)],
              LiquidGlass(
                padding: const EdgeInsets.fromLTRB(YqSpace.s, YqSpace.m, YqSpace.s, YqSpace.s),
                child: _Grid(cal: c, onTap: (cell) => _daySheet(context, c, cell)),
              ),
              const SizedBox(height: YqSpace.m),
              const _Legend(),
            ],
          ),
          const SizedBox(height: YqSpace.l),
          Text(t.calFooter, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _daySheet(BuildContext context, ChallengeCalendar cal, CalendarCell cell) async {
    await showYqSheet<void>(context, scrollable: true, builder: (_) => _DaySheet(cal: cal, cell: cell, monthKey: _key));
  }
}

/// The journey as complications: the year as a gold ring, the streak, the balance.
class _Journey extends StatelessWidget {
  const _Journey({required this.cal, required this.locale});
  final ChallengeCalendar cal;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final start = cal.startedOn == null ? null : DateTime.parse(cal.startedOn!);
    final end = cal.endsOn == null ? null : DateTime.parse(cal.endsOn!);
    return Column(
      children: [
        YqOrbRow(
          orbs: [
            YqOrb(
              title: t.calendarJourney,
              status: t.dayOfTotal(cal.dayNumber, 365),
              statusColor: YqColors.goldText,
              disc: YqRing(
                value: cal.dayNumber / 365,
                gold: true,
                size: YqOrb.defaultSize - 12,
                stroke: 5,
                child: Text(
                  YqFormat.number(cal.dayNumber),
                  textDirection: TextDirection.ltr,
                  style: YqText.numberSmall.copyWith(fontSize: 22, fontWeight: FontWeight.w500, color: YqColors.ink),
                ),
              ),
            ),
            YqOrb(
              title: t.challengeStreak,
              status: t.streakDays(cal.streak),
              disc: const Center(child: YqIcon(YqIcons.streak, size: 30, tone: YqIconTone.gold)),
            ),
            YqOrb(
              title: t.profileBalance,
              status: t.challengePointsLabel(YqFormat.number(cal.balance)),
              glow: true,
              disc: YqOrb.number(YqFormat.number(cal.balance), size: 20, color: YqColors.goldDeep),
            ),
          ],
        ),
        if (start != null && end != null) ...[
          const SizedBox(height: YqSpace.m),
          Text(
            t.calendarStarted(YqFormat.fullDate(start, locale), YqFormat.fullDate(end, locale)),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.cal, required this.locale, required this.month});
  final ChallengeCalendar cal;
  final String locale;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final first = cal.days.isEmpty ? null : cal.days.first;
    final last = cal.days.isEmpty ? null : cal.days.last;
    String h(CalendarCell c) => '${hijriMonthName(c, locale)} ${c.hijriYear}'; // years are never digit-grouped
    final hijri = first == null ? '' : (first.hijriMonth == last!.hijriMonth ? h(first) : '${hijriMonthName(first, locale)} – ${h(last)}');
    return Column(
      children: [
        Text(hijri, textAlign: TextAlign.center, style: YqMoment.display(context, size: 28)),
        Text('${YqFormat.month(month.month, locale)} ${month.year}', style: text.bodySmall?.copyWith(fontSize: 13)),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.cal, required this.onTap});
  final ChallengeCalendar cal;
  final ValueChanged<CalendarCell> onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final heads = [t.calSat, t.calSun, t.calMon, t.calTue, t.calWed, t.calThu, t.calFri];
    // API weekday: 0 = Sunday … 6 = Saturday → column with Saturday first.
    int col(int weekday) => (weekday + 1) % 7;
    final lead = cal.days.isEmpty ? 0 : col(cal.days.first.weekday);
    final cells = <CalendarCell?>[...List.filled(lead, null), ...cal.days];
    return Column(
      children: [
        Row(
          children: [
            for (final h in heads)
              Expanded(
                child: Text(h, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: YqColors.muted)),
              ),
          ],
        ),
        const SizedBox(height: YqSpace.s),
        for (var r = 0; r < (cells.length / 7).ceil(); r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 0.9,
                    child: switch (r * 7 + c < cells.length ? cells[r * 7 + c] : null) {
                      final CalendarCell cell => _Cell(cell: cell, today: cell.gregorian == cal.today, onTap: () => onTap(cell)),
                      null => const SizedBox.shrink(),
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell, required this.today, required this.onTap});
  final CalendarCell cell;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final status = cell.challenge?.status;
    final outside = cell.challenge == null;
    final (Color? fill, Color? ring, Color ink) = switch (status) {
      DayStatus.done => (YqColors.lapis, null, YqColors.white),
      DayStatus.partial => (null, YqColors.lapis, YqColors.ink),
      DayStatus.qada => (YqColors.gold200, YqColors.gold, YqColors.goldDeep),
      DayStatus.missed => (null, YqColors.slate200, YqColors.slate700),
      _ => (null, null, outside ? YqColors.slate400 : YqColors.ink),
    };
    final greg = int.parse(cell.gregorian.substring(8));
    return Semantics(
      button: true,
      label: t.calCellA11y('${cell.hijriDay} ${cell.hijriMonthNameAr}', cell.gregorian, today ? t.calToday : statusLabel(t, cell)),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Opacity(
          opacity: outside ? 0.5 : 1,
          child: Center(
            // A luminous disc: filled for done (with a soft glow), ringed for partial, warm for
            // make-up, a hairline for missed — never red.
            child: AspectRatio(
              aspectRatio: 1,
              child: AnimatedContainer(
                duration: YqMotion.base,
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: today
                      ? Border.all(color: YqColors.ink, width: 1.8)
                      : ring == null
                          ? null
                          : Border.all(color: ring, width: status == DayStatus.missed ? 0.8 : 1.5),
                  boxShadow: status == DayStatus.done
                      ? const [BoxShadow(color: Color(0x591F3F94), blurRadius: 12, spreadRadius: -4, offset: Offset(0, 4))]
                      : status == DayStatus.qada
                          ? const [BoxShadow(color: Color(0x59C6A867), blurRadius: 12, spreadRadius: -4, offset: Offset(0, 4))]
                          : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      YqFormat.number(cell.hijriDay),
                      style: YqText.numberSmall.copyWith(fontSize: 15, height: 1.1, color: ink, fontWeight: today ? FontWeight.w700 : FontWeight.w600),
                    ),
                    Text(
                      YqFormat.number(greg),
                      style: YqText.numberSmall.copyWith(fontSize: 9, height: 1.1, color: fill == YqColors.lapis ? YqColors.sky200 : YqColors.muted),
                    ),
                    SizedBox(
                      height: 5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final d in cell.special.take(3))
                            Container(
                              width: 3.5,
                              height: 3.5,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: d == SpecialDay.whiteDay ? YqColors.sky400 : YqColors.gold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget dot(Color? fill, Color? ring, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration:
                  BoxDecoration(color: fill, shape: BoxShape.circle, border: ring == null ? null : Border.all(color: ring, width: 1.4)),
            ),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        );
    return Wrap(
      spacing: YqSpace.m,
      runSpacing: YqSpace.s,
      alignment: WrapAlignment.center,
      children: [
        dot(YqColors.lapis, null, t.calDone),
        dot(null, YqColors.lapis, t.calPartial),
        dot(YqColors.gold200, YqColors.gold, t.calQada),
        dot(null, YqColors.slate200, t.calMissed),
        dot(null, YqColors.ink, t.calToday),
      ],
    );
  }
}

class _DaySheet extends ConsumerStatefulWidget {
  const _DaySheet({required this.cal, required this.cell, required this.monthKey});
  final ChallengeCalendar cal;
  final CalendarCell cell;
  final String monthKey;

  @override
  ConsumerState<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<_DaySheet> {
  bool _makingUp = false;
  late Set<TaskKey> _done = {...?widget.cell.challenge?.completed};

  Future<void> _tick(TaskKey task) async {
    final t = AppLocalizations.of(context);
    setState(() => _done = {..._done, task});
    final r = await ref.read(challengeRepositoryProvider).complete(task, widget.cell.gregorian);
    if (!mounted) return;
    if (r.code != null) {
      setState(() => _done = {..._done}..remove(task));
      final msg = rejectionCopy(t, r.code!);
      if (msg != null) YqToast.show(context, msg);
    }
    ref.invalidate(calendarMonthProvider(widget.monthKey));
    ref.invalidate(challengeControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final tasks = ref.watch(challengeControllerProvider).valueOrNull?.tasks ?? const <ChallengeTask>[];
    final cell = widget.cell;
    final day = cell.challenge;
    final isToday = cell.gregorian == widget.cal.today;
    final canMakeUp = widget.cal.canMakeUp(cell);
    final greg = DateTime.parse(cell.gregorian);
    final total = day?.status == DayStatus.qada || canMakeUp ? widget.cal.qadaDayPoints : widget.cal.dailyTotal;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${cell.hijriDay} ${hijriMonthName(cell, locale)} ${cell.hijriYear}', style: YqMoment.display(context, size: 26)),
        Text(YqFormat.weekdayDayMonth(greg, locale), style: text.bodySmall),
        if (cell.special.isNotEmpty) ...[
          const SizedBox(height: YqSpace.s),
          Wrap(
            spacing: YqSpace.s,
            children: [for (final d in cell.special) Chip(label: Text(specialLabel(t, d)), visualDensity: VisualDensity.compact)],
          ),
        ],
        if (day != null) ...[
          const SizedBox(height: YqSpace.m),
          Text(
            t.calScore(isToday ? t.calToday : statusLabel(t, cell), day.points, total),
            style: text.titleSmall?.copyWith(color: YqColors.lapis),
          ),
          const SizedBox(height: YqSpace.s),
          YqTimeline(
            timeWidth: 0,
            stops: [
              for (final task in tasks)
                YqStop(
                  title: locale == 'ar' ? task.labelAr : task.labelEn,
                  done: _done.contains(task.key),
                  highlight: _makingUp && !_done.contains(task.key),
                  trailing: Text(t.pointsPlus(YqFormat.number(task.points)), style: YqText.numberSmall.copyWith(color: YqColors.goldText)),
                  onTap: _makingUp && !_done.contains(task.key) ? () => _tick(task.key) : null,
                ),
            ],
          ),
          for (final b in day.bonuses)
            Padding(
              padding: const EdgeInsets.only(top: YqSpace.xs),
              child: Text(
                switch (b) {
                  BonusKind.whiteDaysFast => t.calBonusWhite,
                  BonusKind.monThuFast => t.calBonusMonThu,
                  BonusKind.fridayKahf => t.calBonusKahf,
                },
                style: text.bodySmall?.copyWith(color: YqColors.goldText),
              ),
            ),
          const SizedBox(height: YqSpace.l),
          if (canMakeUp && !_makingUp)
            YqButton(label: t.calMakeUp, onPressed: () => setState(() => _makingUp = true))
          else if (_makingUp)
            Text(t.calMakeUpHint, textAlign: TextAlign.center, style: text.bodySmall)
          else if (isToday)
            YqButton(
              label: t.calFinishToday,
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/challenge');
              },
            ),
        ] else ...[
          const SizedBox(height: YqSpace.m),
          Text(t.calOutside, style: text.bodySmall),
        ],
      ],
    );
  }
}
