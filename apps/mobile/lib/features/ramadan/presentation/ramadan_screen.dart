import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/liquid_orb.dart';
import '../../../core/widgets/yq_countdown.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/ramadan.dart';
import 'ramadan_controller.dart';

/// `23 · Ramadan` (spec §5.27): the fasting clock on the stage, three orbs (today's fast,
/// taraweeh, the khatma), the month's imsakiyya and the khatma grid. All on-device.
class RamadanScreen extends ConsumerWidget {
  const RamadanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final status = ref.watch(ramadanStatusProvider);
    final days = ref.watch(ramadanDaysProvider).valueOrNull ?? const <RamadanDay>[];
    final now = ref.watch(clockProvider)();
    final today = ref.watch(prayerRepositoryProvider).today(s, now);

    final title = status.ramadanYear > 0 ? t.ramadanYearTitle('${status.ramadanYear}') : t.ramadanTitle;
    final subtitle = status.active
        ? '${t.ramadanDayOf(YqFormat.number(status.hijriDay))} · ${YqFormat.weekdayDayMonth(today, s.locale)}'
        : YqFormat.weekdayDayMonth(today, s.locale);

    return Scaffold(
      body: YqCanvas(
        stage: YqStage(
          gold: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(title: title, subtitle: subtitle, back: true, large: true),
              const SizedBox(height: YqSpace.xl),
              if (status.active) _FastClock(days: days) else _Approaching(days: days, today: today),
            ],
          ),
        ),
        children: [
          if (status.active) ...[
            const YqOrbRow(orbs: [_FastOrb(), _TaraweehOrb(), _KhatmaOrb()]),
            const SizedBox(height: YqSpace.xxl),
          ],
          YqHeading(t.ramadanImsakiyya),
          if (days.isEmpty) YqEmptyState(icon: YqIcons.calendar, title: t.ramadanEmpty) else _Imsakiyya(days: days, today: today),
          const SizedBox(height: YqSpace.s),
          Text(t.ramadanImsakNote, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
          if (status.active) ...[
            const SizedBox(height: YqSpace.xxl),
            const _Khatma(),
          ],
          const SizedBox(height: YqSpace.xl),
          YqGroup(
            children: [
              YqListRow(
                leading: const YqIconTile(YqIcons.adhan),
                title: t.ramadanReminders,
                onTap: () => context.push('/prayer/notifications'),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.m),
          Text(t.ramadanTrackerPrivate, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
        ],
      ),
    );
  }
}

/// The stage's moment: time to iftar while fasting, time to Fajr at night, with imsak beside it.
/// Re-plans every 15 s; only the countdown ticks each second.
class _FastClock extends ConsumerWidget {
  const _FastClock({required this.days});
  final List<RamadanDay> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    return YqTicker(
      now: clock,
      interval: const Duration(seconds: 15),
      builder: (context, now) {
        final d = repo.today(s, now);
        final tomorrowDate = DateTime(d.year, d.month, d.day + 1);
        final tomorrowIsRamadan = days.isEmpty || days.any((x) => x.date == tomorrowDate);
        final m = FastMoment.at(
          today: repo.forDate(s, d, ramadan: true),
          tomorrow: repo.forDate(s, tomorrowDate, ramadan: true),
          now: now,
          tomorrowIsRamadan: tomorrowIsRamadan,
        );
        String at(DateTime utc) => YqFormat.time(repo.local(s, utc), s.locale);
        final target = m.target;
        if (target == null) {
          return YqMoment(
            eyebrow: t.ramadanEidTomorrow,
            value: Text(t.ramadanAccepted, textAlign: TextAlign.center, style: YqMoment.display(context, size: 34)),
          );
        }
        final eyebrow = m.phase == FastPhase.fasting ? t.ramadanUntilIftar : t.ramadanUntilFajr;
        final caption = m.phase == FastPhase.fasting ? t.ramadanIftarAt(at(target)) : t.ramadanImsakAt(at(m.imsak!), at(target));
        return Semantics(
          container: true,
          excludeSemantics: true,
          label: '$eyebrow ${YqCountdown.format(target.difference(now.toUtc()))}. $caption',
          child: YqMoment(
            eyebrow: m.phase == FastPhase.evening ? '${t.ramadanAccepted} · $eyebrow' : eyebrow,
            value: RepaintBoundary(
              child: YqCountdown(target: target, now: () => clock().toUtc(), style: YqMoment.numeral(size: 52)),
            ),
            caption: Text(caption),
          ),
        );
      },
    );
  }
}

/// Sha'ban: «رمضان يقترب» and the days left when the calendar already knows the first of Ramadan.
class _Approaching extends StatelessWidget {
  const _Approaching({required this.days, required this.today});
  final List<RamadanDay> days;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final first = days.isEmpty ? null : days.first.date;
    final left = first?.difference(today).inDays;
    return YqMoment(
      eyebrow: t.ramadanApproaching,
      value: Text(
        left != null && left > 0 ? t.ramadanInDays(left) : t.ramadanSoon,
        textAlign: TextAlign.center,
        style: YqMoment.display(context, size: 40),
      ),
    );
  }
}

String? _bonusLabel(AppLocalizations t, WidgetRef ref, RamadanTrack track) {
  final p = bonusPointsFor(ref.watch(remoteConfigProvider), track);
  return p == null ? null : t.ramadanBonus(YqFormat.number(p));
}

/// Today's fast as liquid: fills from Fajr to Maghrib; tap marks (or un-marks) today as fasted.
class _FastOrb extends ConsumerWidget {
  const _FastOrb();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final status = ref.watch(ramadanStatusProvider);
    final log = ref.watch(ramadanLogProvider).valueOrNull ?? const RamadanLog();
    final done = log.fasted.contains(status.hijriDay);
    final bonus = _bonusLabel(t, ref, RamadanTrack.fast);
    return YqTicker(
      now: ref.watch(clockProvider),
      interval: const Duration(seconds: 30),
      builder: (context, now) {
        final d = repo.today(s, now);
        final m = FastMoment.at(
          today: repo.forDate(s, d, ramadan: true),
          tomorrow: repo.forDate(s, DateTime(d.year, d.month, d.day + 1), ramadan: true),
          now: now,
        );
        final statusText = done ? t.ramadanDone : (bonus ?? t.ramadanMark);
        return YqOrb(
          title: t.ramadanOrbFast,
          status: statusText,
          glow: done,
          onTap: () => _tick(ref, RamadanTrack.fast, status.hijriDay),
          semanticLabel: '${t.ramadanOrbFast}: $statusText',
          disc: LiquidOrb(
            level: m.progress,
            complete: done,
            size: YqOrb.defaultSize - 12,
            child: done ? const Icon(Icons.check_rounded, color: YqColors.lapis) : null,
          ),
        );
      },
    );
  }
}

class _TaraweehOrb extends ConsumerWidget {
  const _TaraweehOrb();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final status = ref.watch(ramadanStatusProvider);
    final log = ref.watch(ramadanLogProvider).valueOrNull ?? const RamadanLog();
    final done = log.taraweeh.contains(status.hijriDay);
    final count = log.taraweeh.length;
    final statusText = done ? t.ramadanDone : (_bonusLabel(t, ref, RamadanTrack.taraweeh) ?? t.ramadanMark);
    return YqOrb(
      title: t.ramadanOrbTaraweeh,
      status: statusText,
      glow: done,
      onTap: () => _tick(ref, RamadanTrack.taraweeh, status.hijriDay),
      semanticLabel: '${t.ramadanOrbTaraweeh}: ${t.ramadanNights(count)}، $statusText',
      disc: YqRing(
        value: count / 30,
        size: YqOrb.defaultSize - 12,
        stroke: 5,
        gold: true,
        child: Text(YqFormat.number(count), style: YqText.numberSmall.copyWith(fontSize: 20, color: YqColors.ink)),
      ),
    );
  }
}

/// The khatma ring; tap ticks the next juz.
class _KhatmaOrb extends ConsumerWidget {
  const _KhatmaOrb();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final log = ref.watch(ramadanLogProvider).valueOrNull ?? const RamadanLog();
    final next = log.nextJuz;
    final statusText = next == null ? t.ramadanKhatmaDone : t.ramadanJuz(YqFormat.number(next));
    return YqOrb(
      title: t.ramadanOrbKhatma,
      status: statusText,
      glow: log.khatmaDone,
      onTap: next == null ? null : () => _tick(ref, RamadanTrack.juz, next),
      semanticLabel: '${t.ramadanOrbKhatma}: ${t.ramadanKhatmaSub(YqFormat.number(log.juz.length))}',
      disc: YqRing(
        value: log.khatmaProgress,
        size: YqOrb.defaultSize - 12,
        stroke: 5,
        child: const YqIcon(YqIcons.quran, size: 26),
      ),
    );
  }
}

void _tick(WidgetRef ref, RamadanTrack track, int value) {
  HapticFeedback.selectionClick();
  ref.read(ramadanLogProvider.notifier).toggle(track, value);
}

/// The month at a glance: day · date · imsak · Fajr · Maghrib. Today is lifted; past days recede.
class _Imsakiyya extends ConsumerWidget {
  const _Imsakiyya({required this.days, required this.today});
  final List<RamadanDay> days;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    String at(DateTime utc) => YqFormat.time(repo.local(s, utc), s.locale, suffix: false);
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: YqColors.muted);
    return LiquidGlass(
      padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.s),
      child: Column(
        children: [
          _row(
            cells: [t.ramadanColDay, t.ramadanColDate, t.ramadanColImsak, t.prayerFajr, t.prayerMaghrib],
            style: head,
          ),
          for (final d in days)
            Builder(
              builder: (context) {
                final times = repo.forDate(s, d.date, ramadan: true);
                final isToday = d.date == today;
                final past = d.date.isBefore(today);
                return Container(
                  decoration:
                      isToday ? BoxDecoration(color: const Color(0x1A1F3F94), borderRadius: BorderRadius.circular(YqRadii.chip)) : null,
                  child: Semantics(
                    label: isToday ? t.ramadanTodayTag : null,
                    child: _row(
                      cells: [
                        YqFormat.number(d.hijriDay),
                        YqFormat.dayMonth(d.date, s.locale),
                        at(times.fajr.subtract(const Duration(minutes: imsakMinutes))),
                        at(times.fajr),
                        at(times.maghrib),
                      ],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                        color: past ? YqColors.muted : YqColors.ink,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  static Widget _row({required List<String> cells, required TextStyle style}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: YqSpace.xs),
        child: Row(
          children: [
            SizedBox(width: 28, child: Text(cells[0], style: style)),
            Expanded(flex: 3, child: Text(cells[1], style: style, overflow: TextOverflow.ellipsis)),
            for (final c in cells.skip(2)) Expanded(flex: 2, child: Text(c, style: style, textAlign: TextAlign.center)),
          ],
        ),
      );
}

/// Thirty juz as chips — the month's khatma, ticked in any order.
class _Khatma extends ConsumerWidget {
  const _Khatma();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final log = ref.watch(ramadanLogProvider).valueOrNull ?? const RamadanLog();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YqHeading(t.ramadanKhatmaTitle),
        Text(t.ramadanKhatmaSub(YqFormat.number(log.juz.length)), style: const TextStyle(color: YqColors.muted)),
        const SizedBox(height: YqSpace.m),
        Wrap(
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            for (var j = 1; j <= RamadanLog.juzCount; j++)
              YqChip(
                label: YqFormat.number(j),
                selected: log.juz.contains(j),
                semanticLabel: t.ramadanJuz(YqFormat.number(j)),
                onTap: () => ref.read(ramadanLogProvider.notifier).toggle(RamadanTrack.juz, j),
              ),
          ],
        ),
      ],
    );
  }
}
