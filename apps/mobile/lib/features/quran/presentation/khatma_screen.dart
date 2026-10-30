import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/zoned.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/liquid_orb.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/khatma.dart';
import '../domain/quran_data.dart';
import 'quran_index_screen.dart';
import 'quran_providers.dart';
import 'reader_screen.dart';

/// `24 · Khatma` (spec §5.30): the plan, today's portion, ahead/behind, the week's reading and past
/// khatmas. Everything on the device.
class KhatmaScreen extends ConsumerWidget {
  const KhatmaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final plan = ref.watch(khatmaProvider);
    final k = plan.valueOrNull;
    final active = k != null && !k.finished;
    return Scaffold(
      body: YqCanvas(
        stage: YqStage(
          gold: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(title: t.khatmaTitle, subtitle: t.khatmaSubtitle, back: true, large: true),
              const SizedBox(height: YqSpace.xl),
              if (plan.isLoading) const SizedBox(height: 180) else _Moment(plan: k),
            ],
          ),
        ),
        children: [
          if (active) ...[
            _TodayCard(plan: k),
            const SizedBox(height: YqSpace.l),
          ] else if (!plan.isLoading) ...[
            LiquidGlass(
              child: YqEmptyState(
                icon: YqIcons.quran,
                // The stage caption already carries the hint (or the finished line); don't say it twice.
                title: k?.finished == true ? t.khatmaDoneTitle : t.khatmaEmptyTitle,
                actionLabel: t.khatmaStart,
                onAction: () => showKhatmaSetup(context, ref),
              ),
            ),
            const SizedBox(height: YqSpace.l),
          ],
          const _WeekCard(),
          const SizedBox(height: YqSpace.l),
          const _History(),
          if (active) ...[
            const SizedBox(height: YqSpace.l),
            YqGroup(
              children: [
                YqListRow(
                  leading: const YqIconTile(YqIcons.settings),
                  title: t.khatmaEdit,
                  onTap: () => showKhatmaSetup(context, ref, editing: k),
                ),
                YqListRow(
                  title: t.khatmaEnd,
                  titleColor: YqColors.goldText,
                  onTap: () async {
                    final ok = await showYqSheet<bool>(
                      context,
                      builder: (c) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(t.khatmaEndConfirm, style: Theme.of(c).textTheme.titleMedium),
                          const SizedBox(height: YqSpace.l),
                          YqButton(label: t.khatmaEnd, onPressed: () => Navigator.of(c).pop(true)),
                          TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text(t.cancel)),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(readingRepositoryProvider).saveKhatma(null);
                      ref.invalidate(khatmaProvider);
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _today(WidgetRef ref) {
  final s = ref.watch(settingsProvider);
  return Zoned.isoDate(Zoned.today(s.placeOrDefault.timezone, ref.watch(clockProvider)()));
}

/// Pages of today's wird that also count towards the plan.
int _readToday(WidgetRef ref, Khatma k, String today) {
  final wird = ref.watch(todayWirdProvider).valueOrNull;
  if (wird == null || wird.date != today) return 0;
  return wird.pages.where(k.read.contains).length;
}

DateTime _date(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

class _Moment extends ConsumerWidget {
  const _Moment({required this.plan});
  final Khatma? plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final k = plan;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final today = _today(ref);
    final done = k?.finished == true ? 0 : (k?.done ?? 0);
    final caption = switch (k) {
      null => t.khatmaEmptyHint,
      final k when k.finished => t.khatmaDoneBody,
      final k when k.targetDate != null =>
        t.khatmaTarget(YqFormat.dayMonth(_date(k.targetDate!), locale), YqFormat.number(k.daysLeft(today))),
      final k => t.khatmaProjected(YqFormat.dayMonth(_date(k.projectedFinish(today)), locale)),
    };
    return Column(
      children: [
        YqRing(
          value: done / Khatma.total,
          size: 150,
          stroke: 9,
          gold: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${YqFormat.number((done / Khatma.total * 100).round())}%', style: YqMoment.numeral(size: 38)),
              Text(t.khatmaPagesDone(YqFormat.number(done)), style: const TextStyle(fontSize: 12, color: YqColors.muted)),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.m),
        Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: YqColors.goldText)),
      ],
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.plan});
  final Khatma plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final today = _today(ref);
    final read = _readToday(ref, plan, today);
    final target = plan.dailyTarget(today, readToday: read);
    final from = plan.nextPage ?? Khatma.total;
    final to = (from + (target - read).clamp(1, target) - 1).clamp(from, Khatma.total);
    final balance = plan.balance(today);
    final status = balance >= 0
        ? (balance == 0 ? t.khatmaOnTrack : t.khatmaAhead(YqFormat.number(balance)))
        : t.khatmaBehind(YqFormat.number(-balance));
    return LiquidGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child: LiquidOrb(
                  level: target == 0 ? 1 : (read / target).clamp(0.0, 1.0),
                  size: 64,
                  complete: read >= target,
                  child: Text(
                    '${YqFormat.number(read)}/${YqFormat.number(target)}',
                    textDirection: TextDirection.ltr,
                    style: YqText.numberSmall.copyWith(fontSize: 14, color: YqColors.ink),
                  ),
                ),
              ),
              const SizedBox(width: YqSpace.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.khatmaToday, style: Theme.of(context).textTheme.titleMedium),
                    Text(t.khatmaPortion(YqFormat.number(from), YqFormat.number(to))),
                    Text(
                      t.khatmaPortionCount(YqFormat.number(target), YqFormat.number(read)),
                      style: const TextStyle(fontSize: 12, color: YqColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.m),
          Text(status, style: TextStyle(fontSize: 13, color: balance >= 0 ? YqColors.success : YqColors.goldText)),
          const SizedBox(height: YqSpace.m),
          YqButton(label: t.khatmaReadNow, onPressed: () => context.push('/quran/read/$from')),
        ],
      ),
    );
  }
}

/// The week: seven bars (pages a day), totals and the reading streak.
class _WeekCard extends ConsumerWidget {
  const _WeekCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final stats = ref.watch(readingStatsProvider).valueOrNull;
    if (stats == null) return const SizedBox.shrink();
    final s = ref.watch(settingsProvider);
    final today = Zoned.today(s.placeOrDefault.timezone, ref.watch(clockProvider)());
    final week = stats.week(today);
    final bars = stats.lastSeven(today);
    final peak = bars.fold<int>(1, (m, v) => v > m ? v : m);
    final streak = stats.streak(today);
    return LiquidGlass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.khatmaWeek, style: Theme.of(context).textTheme.titleMedium)),
              if (streak > 1) Text(t.khatmaStreak(YqFormat.number(streak)), style: const TextStyle(color: YqColors.goldText, fontSize: 13)),
            ],
          ),
          Text(
            t.khatmaWeekSummary(YqFormat.number(week.pages), YqFormat.number(week.minutes), YqFormat.number(week.activeDays)),
            style: const TextStyle(fontSize: 13, color: YqColors.muted),
          ),
          const SizedBox(height: YqSpace.m),
          Semantics(
            label: t.khatmaWeekSummary(YqFormat.number(week.pages), YqFormat.number(week.minutes), YqFormat.number(week.activeDays)),
            excludeSemantics: true,
            child: SizedBox(
              height: 76,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (i, v) in bars.indexed)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedContainer(
                              duration: YqMotion.slow,
                              curve: YqMotion.ease,
                              height: v == 0 ? 3 : 6 + 40 * v / peak,
                              decoration: BoxDecoration(
                                color: i == 6 ? YqColors.gold : (v == 0 ? YqColors.line : YqColors.sky),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _shortDay(YqFormat.weekday(Zoned.addDays(today, -(6 - i)), s.locale), s.locale),
                              style: const TextStyle(fontSize: 10, color: YqColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «الاثنين» → «اثنين», «Monday» → «Mon» — fits under a bar.
String _shortDay(String day, String locale) {
  if (locale == 'ar') return day.startsWith('ال') ? day.substring(2) : day;
  return day.characters.take(3).toString();
}

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final list = ref.watch(khatmaHistoryProvider).valueOrNull ?? const <KhatmaRecord>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YqHeading(t.khatmaHistory),
        YqGroup(
          children: [
            for (final r in list)
              YqListRow(
                dense: true,
                leading: const YqIconTile(YqIcons.quran, gold: true),
                title: t.khatmaRecord(
                  YqFormat.number(r.days),
                  YqFormat.dayMonth(_date(r.startedOn), locale),
                  YqFormat.fullDate(_date(r.finishedOn), locale),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The khatma orb for the Quran index: plan progress and today's part of it; tap → this screen.
class KhatmaOrb extends ConsumerWidget {
  const KhatmaOrb({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final k = ref.watch(khatmaProvider).valueOrNull;
    final active = k != null && !k.finished;
    final last = ref.watch(lastReadProvider).valueOrNull;
    final today = _today(ref);
    final String status;
    final double value;
    if (active) {
      final read = _readToday(ref, k, today);
      status = t.khatmaOrbStatus(
        YqFormat.number((k.progress * 100).round()),
        YqFormat.number(read),
        YqFormat.number(k.dailyTarget(today, readToday: read)),
      );
      value = k.progress;
    } else {
      final page = last?.page ?? 0;
      status = t.quranKhatmaStatus(YqFormat.number(page), YqFormat.number(QuranData.pageCount));
      value = page / QuranData.pageCount;
    }
    return YqOrb(
      title: t.quranKhatma,
      status: status,
      semanticLabel: '${t.quranKhatma}، $status',
      onTap: () => context.push('/quran/khatma'),
      disc: YqRing(
        value: value,
        gold: true,
        size: YqOrb.defaultSize - 12,
        stroke: 5,
        child: Text(
          '${YqFormat.number((value * 100).round())}%',
          style: YqText.numberSmall.copyWith(fontSize: 16, fontWeight: FontWeight.w500, color: YqColors.ink),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------ setup */

enum _Mode { date, pace }

/// «خطة الختمة»: by a date (7 · 15 · 30 · 60 days or any day) or a daily pace; start from the
/// beginning or from the last page read; optionally make the daily portion the wird goal.
Future<void> showKhatmaSetup(BuildContext context, WidgetRef ref, {Khatma? editing}) =>
    showYqSheet<void>(context, scrollable: true, builder: (_) => _Setup(editing: editing));

class _Setup extends ConsumerStatefulWidget {
  const _Setup({this.editing});
  final Khatma? editing;

  @override
  ConsumerState<_Setup> createState() => _SetupState();
}

class _SetupState extends ConsumerState<_Setup> {
  late _Mode _mode = widget.editing?.pagesPerDay != null ? _Mode.pace : _Mode.date;
  int _days = 30;
  DateTime? _customDate;
  late int _pace = widget.editing?.pagesPerDay ?? 5;
  bool _fromHere = false;
  bool _setWird = true;

  @override
  void initState() {
    super.initState();
    final target = widget.editing?.targetDate;
    if (target != null) _customDate = _date(target);
  }

  Future<void> _save() async {
    final s = ref.read(settingsProvider);
    final now = ref.read(clockProvider)();
    final todayDate = Zoned.today(s.placeOrDefault.timezone, now);
    final today = Zoned.isoDate(todayDate);
    final last = await ref.read(readingRepositoryProvider).lastRead();
    final carried = widget.editing?.read ?? (_fromHere && last != null ? {for (var p = 1; p < last.page; p++) p} : <int>{});
    final target = _mode == _Mode.date ? Zoned.isoDate(_customDate ?? Zoned.addDays(todayDate, _days - 1)) : null;
    final plan = Khatma(
      startedOn: widget.editing?.startedOn ?? today,
      targetDate: target,
      pagesPerDay: _mode == _Mode.pace ? _pace : null,
      read: carried,
    );
    await ref.read(readingRepositoryProvider).saveKhatma(plan);
    if (_setWird) {
      final daily = plan.dailyTarget(today).clamp(1, 60);
      await ref.read(settingsProvider.notifier).update((x) => x.copyWith(wirdGoalPages: daily));
    }
    ref.invalidate(khatmaProvider);
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final todayDate = Zoned.today(s.placeOrDefault.timezone, ref.watch(clockProvider)());
    final last = ref.watch(lastReadProvider).valueOrNull;
    final text = Theme.of(context).textTheme;
    final finish = _customDate ?? Zoned.addDays(todayDate, _days - 1);
    final preview = _mode == _Mode.date
        ? t.khatmaFinishOn(YqFormat.fullDate(finish, s.locale))
        : t.khatmaProjected(YqFormat.fullDate(Zoned.addDays(todayDate, (Khatma.total / _pace).ceil() - 1), s.locale));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.khatmaSetupTitle, style: text.titleLarge),
        const SizedBox(height: YqSpace.m),
        YqSegmented<_Mode>(
          segments: [(_Mode.date, t.khatmaByDate), (_Mode.pace, t.khatmaByPace)],
          selected: _mode,
          onChanged: (v) => setState(() => _mode = v),
        ),
        const SizedBox(height: YqSpace.m),
        if (_mode == _Mode.date)
          Wrap(
            spacing: YqSpace.s,
            runSpacing: YqSpace.s,
            children: [
              for (final d in const [7, 15, 30, 60])
                YqChip(
                  label: t.khatmaInDays(YqFormat.number(d)),
                  selected: _customDate == null && _days == d,
                  onTap: () => setState(() {
                    _days = d;
                    _customDate = null;
                  }),
                ),
              YqChip(
                label: _customDate == null ? t.khatmaPickDate : YqFormat.dayMonth(_customDate!, s.locale),
                selected: _customDate != null,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: finish,
                    firstDate: todayDate,
                    lastDate: Zoned.addDays(todayDate, 730),
                  );
                  if (picked != null) setState(() => _customDate = picked);
                },
              ),
            ],
          )
        else
          Wrap(
            spacing: YqSpace.s,
            runSpacing: YqSpace.s,
            children: [
              for (final p in const [2, 4, 5, 10, 20])
                YqChip(label: t.khatmaPerDay(YqFormat.number(p)), selected: _pace == p, onTap: () => setState(() => _pace = p)),
            ],
          ),
        const SizedBox(height: YqSpace.s),
        Text(preview, style: const TextStyle(color: YqColors.goldText)),
        if (widget.editing == null && last != null && last.page > 1) ...[
          const SizedBox(height: YqSpace.m),
          YqSegmented<bool>(
            segments: [(false, t.khatmaFromStart), (true, t.khatmaFromHere(YqFormat.number(last.page)))],
            selected: _fromHere,
            onChanged: (v) => setState(() => _fromHere = v),
          ),
        ],
        YqListRow(
          title: t.khatmaSetWird,
          trailing: YqSwitch(value: _setWird, onChanged: (v) => setState(() => _setWird = v), label: t.khatmaSetWird),
        ),
        const SizedBox(height: YqSpace.s),
        YqButton(label: widget.editing == null ? t.khatmaCreate : t.khatmaSave, onPressed: _save),
      ],
    );
  }
}
