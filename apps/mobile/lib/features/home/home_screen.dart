import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/config_controller.dart';
import '../../core/config/remote_config.dart';
import '../../core/di/providers.dart';
import '../../core/format.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/time/zoned.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/yq_countdown.dart';
import '../../core/widgets/yq_icon.dart';
import '../../core/widgets/yq_states.dart';
import '../../l10n/gen/app_localizations.dart';
import '../calendar/data/hijri_today.dart';
import '../challenge/presentation/challenge_controller.dart';
import '../notifications/presentation/inbox_screen.dart';
import '../onboarding/presentation/session_controller.dart';
import '../prayer/domain/prayer_calculator.dart';
import '../prayer/domain/prayer_clock.dart';
import '../prayer/presentation/prayer_labels.dart';
import '../quran/domain/quran_data.dart';
import '../quran/presentation/quran_index_screen.dart';
import '../quran/presentation/reader_screen.dart';
import '../ramadan/domain/ramadan.dart';
import '../ramadan/presentation/ramadan_controller.dart';
import '../routine/domain/routine.dart';
import '../routine/presentation/habit_picker.dart';
import 'widgets/orbs.dart';
import '../../core/design/living_sky.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/yq_rise.dart';
import '../../core/widgets/yq_stage.dart';
import '../../core/widgets/yq_timeline.dart';

/// `07 · Home` (spec §5.9) — "your day as a living canvas":
///
/// 1. **Sky stage** — edge to edge under the status bar: the greeting, then the moment itself —
///    next prayer in large type, the countdown, and the sun (a crescent at night) travelling the
///    day's arc under a sky that follows the time of day.
/// 2. **Complications** — three living orbs: Qibla (the Kaaba orbits the ring and reaches the top
///    when you face it), a misbaha you tap to count, and the wird filling like water.
/// 3. **Your day** — one vertical journey: Fajr → morning azkar → Dhuhr → Asr → evening azkar →
///    Maghrib → Isha. Past moments recede; a «now» marker carries what to do now (continue
///    reading); azkar glow while their window is open; the challenge closes the day.
/// 4. **Services** — the rest, one tap away.
///
/// Everything but the challenge numbers is local, so the screen never waits on the network.
/// Sections rise in once, staggered, on first open (not on tab switches; skipped with reduced motion).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return AmbientBackground(
      child: RefreshIndicator(
        color: YqColors.lapis,
        edgeOffset: MediaQuery.paddingOf(context).top,
        onRefresh: () async {
          ref.invalidate(challengeControllerProvider);
          ref.invalidate(hijriTodayProvider);
        },
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: YqRise(order: 0, child: _Sky())),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.xl, YqSpace.gutter, 140),
              sliver: SliverList.list(
                children: [
                  const YqRise(order: 1, child: _Complications()),
                  const _RamadanBand(),
                  const SizedBox(height: YqSpace.xxl),
                  YqRise(order: 2, child: _SectionTitle(t.homeDayTitle)),
                  const SizedBox(height: YqSpace.m),
                  const YqRise(order: 3, child: _Journey()),
                  const SizedBox(height: YqSpace.l),
                  YqRise(order: 4, child: _SectionTitle(t.servicesTitle)),
                  const SizedBox(height: YqSpace.m),
                  const YqRise(order: 5, child: _Services()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      );
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final now = ref.watch(clockProvider)();
    final repo = ref.watch(prayerRepositoryProvider);
    // «صباح الخير» before Dhuhr, «مساء الخير» after (spec §5.9).
    final dhuhr = repo.forDate(s, repo.today(s, now)).dhuhr;
    final morning = now.toUtc().isBefore(dhuhr);
    final hijri = ref.watch(hijriTodayProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final name = (session.displayName?.trim().isNotEmpty ?? false) && !session.isGuest ? session.displayName! : t.guestName;
    final place = s.placeOrDefault.name(s.locale);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(morning ? t.greetingMorning : t.greetingEvening, style: text.bodySmall?.copyWith(fontSize: 13)),
              Text(
                name,
                style: text.titleLarge?.copyWith(fontSize: 23, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              switch (hijri) {
                AsyncData(value: final h?) =>
                  Text('${h.hijriDay} ${h.monthNameAr} ${h.hijriYear} · $place', style: text.bodySmall),
                AsyncLoading() => const YqSkeleton(child: YqSkeletonBox(width: 160, height: 12)),
                _ => Text('${YqFormat.weekdayDayMonth(repo.local(s, now.toUtc()), s.locale)} · $place', style: text.bodySmall),
              },
            ],
          ),
        ),
        GlassIconButton(
          tooltip: t.homeSearch,
          onPressed: () => context.go('/quran?search=1'),
          icon: const YqIcon(YqIcons.search, size: 20, tone: YqIconTone.idle),
        ),
        const SizedBox(width: YqSpace.s),
        Stack(
          clipBehavior: Clip.none,
          children: [
            GlassIconButton(
              tooltip: t.homeInboxA11y(unread),
              onPressed: () => context.push('/home/inbox'),
              icon: const YqIcon(YqIcons.adhan, size: 20, tone: YqIconTone.idle),
            ),
            if (unread > 0)
              const PositionedDirectional(
                top: 8,
                end: 10,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: YqColors.gold, shape: BoxShape.circle),
                    child: SizedBox.square(dimension: 8),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Next-prayer hero as a "sky": the day drawn as an arc with the five prayers as stations and the
/// sun (a crescent after Maghrib) gliding along it in real time, under a sky that follows the time
/// of day. The card re-plans every 15 s; only the countdown text ticks each second, behind its own
/// repaint boundary, and the orb eases between positions.
class _Sky extends ConsumerWidget {
  const _Sky();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    final ramadan = ref.watch(ramadanStatusProvider.select((r) => r.active));
    return YqTicker(
      now: clock,
      interval: const Duration(seconds: 15),
      builder: (context, now) {
        final today = repo.today(s, now);
        final friday = today.weekday == DateTime.friday;
        final moment = repo.moment(s, now, ramadan: ramadan);
        final shown = moment.current ?? moment.next;
        final name = prayerLabel(t, shown, friday: friday);
        final at = YqFormat.time(repo.local(s, moment.current != null ? moment.currentAt! : moment.at), s.locale);
        final left = YqCountdown.format(moment.at.difference(now.toUtc()));

        final arc = dayArcAt(s, repo, now, ramadan: ramadan);

        return YqStage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              const SizedBox(height: YqSpace.xxl),
              Semantics(
                button: true,
                container: true,
                excludeSemantics: true,
                label: moment.isPrayerTime ? t.homePrayerNow(name) : t.homeHeroA11y(name, at, left),
                onTap: () => context.go('/prayer'),
                child: GlassTap(
                  onTap: () => context.go('/prayer'),
                  child: Column(
                    children: [
                      Text(
                        t.nextPrayer,
                        style: text.labelSmall
                            ?.copyWith(color: YqColors.goldText, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        moment.isPrayerTime ? t.homePrayerNow(name) : name,
                        textAlign: TextAlign.center,
                        style: text.headlineLarge
                            ?.copyWith(fontSize: moment.isPrayerTime ? 30 : 58, height: 1.15, fontWeight: FontWeight.w700),
                      ),
                      if (!moment.isPrayerTime) ...[
                        Text('$at · ${t.adhanIn}', style: text.bodySmall?.copyWith(fontSize: 13)),
                        const SizedBox(height: 6),
                        RepaintBoundary(
                          child: YqCountdown(
                            target: moment.at,
                            now: () => clock().toUtc(),
                            style: YqText.numeral.copyWith(
                                fontSize: 46, fontWeight: FontWeight.w300, color: YqColors.ink, height: 1, letterSpacing: 1,),
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      DayArc(
                        position: arc.position,
                        nextIndex: arc.nextIndex,
                        night: arc.night,
                        labels: [for (final p in obligatory) prayerLabel(t, p, friday: friday)],
                        current: obligatory.indexOf(shown),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The three living orbs, evenly spaced.
class _Complications extends ConsumerWidget {
  const _Complications();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final wird = ref.watch(todayWirdProvider).valueOrNull;
    final today = ref.watch(prayerRepositoryProvider).today(s, ref.watch(clockProvider)());
    final done = wird != null && wird.date == Zoned.isoDate(today) ? wird.count : 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: QiblaOrb()),
        const Expanded(child: TasbeehOrb()),
        Expanded(child: WirdOrb(done: done, goal: s.wirdGoalPages)),
      ],
    );
  }
}

/// «Your day»: the five prayers and the two azkar windows in order, with the «now» marker
/// carrying what to resume. Re-plans every 30 s (the marker moves as moments pass).
class _Journey extends ConsumerWidget {
  const _Journey();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    final challenge = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.challenge)));
    final ramadan = ref.watch(ramadanStatusProvider.select((r) => r.active));
    final hifzOn = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.hifz)));

    return YqTicker(
      now: clock,
      interval: const Duration(seconds: 30),
      builder: (context, now) {
        final today = repo.today(s, now);
        final friday = today.weekday == DateTime.friday;
        final times = repo.forDate(s, today, ramadan: ramadan);
        final instant = now.toUtc();
        String at(DateTime utc) => YqFormat.time(repo.local(s, utc), s.locale);

        final next = obligatory.where((p) => times.of(p).isAfter(instant)).firstOrNull;
        final morningOpen = !instant.isBefore(times.fajr) && instant.isBefore(times.dhuhr);
        final eveningOpen = !instant.isBefore(times.asr) && instant.isBefore(times.isha);

        YqStop prayer(PrayerName p) => YqStop(
              time: at(times.of(p)),
              title: prayerLabel(t, p, friday: friday),
              icon: p == PrayerName.fajr || p == PrayerName.isha ? YqIcons.prayer : YqIcons.adhan,
              highlight: p == next,
              tag: p == next ? t.homeNextTag : null,
            );
        YqStop azkar(bool morning, DateTime from, bool open) => YqStop(
              time: at(from),
              title: morning ? t.azkarMorning : t.azkarEvening,
              subtitle: open ? t.homeAzkarHint : null,
              icon: YqIcons.azkar,
              style: StopStyle.pill,
              goldTag: true,
              highlight: open,
              tag: open ? t.homeAzkarOpen : null,
              onTap: () => context.push('/home/azkar?set=${morning ? 'morning' : 'evening'}'),
            );

        // (moment, when it starts) in the day's order; azkar follow their opening prayer.
        final entries = <(YqStop, DateTime)>[
          (prayer(PrayerName.fajr), times.fajr),
          (azkar(true, times.fajr, morningOpen), times.fajr),
          (prayer(PrayerName.dhuhr), times.dhuhr),
          (prayer(PrayerName.asr), times.asr),
          (azkar(false, times.asr, eveningOpen), times.asr),
          (prayer(PrayerName.maghrib), times.maghrib),
          (prayer(PrayerName.isha), times.isha),
        ];

        // The user's routine (onboarding «متى يناسبك؟»): each habit at its resolved time, due from
        // then until the next prayer.
        final tzName = s.placeOrDefault.timezone;
        DateTime nextPrayerAfter(DateTime t) =>
            obligatory.map(times.of).where((x) => x.isAfter(t)).firstOrNull ?? t.add(const Duration(hours: 3));
        void habit(Habit h, RoutineSlot slot,
            {required String title, String? subtitle, bool done = false, required VoidCallback onTap,}) {
          final at = resolveSlot(slot, times, tzName);
          if (at == null) return;
          final due = !done && !instant.isBefore(at) && instant.isBefore(nextPrayerAfter(at));
          entries.add(
            (
              YqStop(
                time: YqFormat.time(repo.local(s, at), s.locale),
                title: title,
                subtitle: subtitle,
                icon: habitIcon(h),
                style: StopStyle.pill,
                highlight: due,
                tag: done ? t.homeRoutineDone : (due ? t.homeRoutineDue : null),
                onTap: onTap,
              ),
              at,
            ),
          );
        }

        final wird = ref.watch(todayWirdProvider).valueOrNull;
        final pages = wird != null && wird.date == Zoned.isoDate(today) ? wird.count : 0;
        final lastPage = ref.watch(lastReadProvider).valueOrNull?.page;
        habit(
          Habit.quran,
          s.quranSlot,
          title: t.homeRoutineQuran,
          subtitle: t.pagesOf(pages.clamp(0, s.wirdGoalPages), s.wirdGoalPages),
          done: s.wirdGoalPages > 0 && pages >= s.wirdGoalPages,
          onTap: () => lastPage == null ? context.go('/quran') : context.push('/quran/read/$lastPage'),
        );
        if (hifzOn) habit(Habit.hifz, s.hifzSlot, title: t.habitHifz, onTap: () => context.push('/quran/hifz'));
        habit(Habit.dhikr, s.dhikrSlot, title: t.habitDhikr, onTap: () => context.push('/home/azkar'));
        // Stable sort by time: at the same minute a prayer stays before what follows it.
        final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])]..sort((a, b) {
            final c = a.$2.$2.compareTo(b.$2.$2);
            return c != 0 ? c : a.$1.compareTo(b.$1);
          });
        entries
          ..clear()
          ..addAll(indexed.map((e) => e.$2));
        // «Now» sits after everything that has started (an open azkar window stays above it).
        final nowIndex = entries.where((e) => !e.$2.isAfter(instant)).length;

        return YqTimeline(
          stops: [for (final e in entries) e.$1],
          nowIndex: nowIndex,
          nowTime: at(instant),
          nowLabel: t.homeNow,
          nowChild: const _ContinueReading(),
          trailing: challenge ? const _ChallengeCard() : null,
        );
      },
    );
  }
}

class _ContinueReading extends ConsumerWidget {
  const _ContinueReading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final last = ref.watch(lastReadProvider).valueOrNull;
    final s = ref.watch(settingsProvider);
    final listenOn = ref.watch(remoteConfigProvider).isOn(Flags.listen);
    if (quran == null) return const YqSkeleton(child: YqSkeletonBox(height: 92, radius: YqRadii.card));

    final today = ref.watch(prayerRepositoryProvider).today(s, ref.watch(clockProvider)());
    // Friday: suggest al-Kahf unless it is already the current reading (a suggestion, not a badge).
    final kahf = today.weekday == DateTime.friday && last?.surah != 18;
    final page = kahf ? quran.surah(18).startPage : (last?.page ?? 1);
    final first = quran.firstOfPage(page);
    final surah = quran.surah(kahf ? 18 : first.surah);
    final surahPages = (surah.number < QuranData.surahCount ? quran.surah(surah.number + 1).startPage : QuranData.pageCount + 1) -
        surah.startPage;
    final progress = surahPages <= 0 ? 0.0 : ((page - surah.startPage + 1) / surahPages).clamp(0.0, 1.0);
    final surahName = surah.name(s.locale);

    return GlassTap(
      onTap: () => context.push('/quran/read/$page'),
      semanticLabel: '${t.continueReading}، ${t.homeReadingMeta(surahName, page, quran.juzOf(first))}',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: YqColors.navy,
          borderRadius: BorderRadius.circular(YqRadii.card),
          boxShadow: const [BoxShadow(color: Color(0x400A1530), blurRadius: 24, spreadRadius: -10, offset: Offset(0, 12))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kahf ? t.homeKahfSuggestion : (last == null ? t.homeStartReading : t.continueReading),
                    style: text.labelSmall?.copyWith(color: YqColors.goldLight, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    surahName,
                    // The brand display face is Arabic-only; Latin names use Amiri rather than the system font.
                    style: TextStyle(
                      fontFamily: s.locale == 'ar' ? YqFonts.display : YqFonts.naskh,
                      fontFamilyFallback: YqFonts.displayFallback,
                      fontSize: 30,
                      color: YqColors.goldLight,
                      height: 1.3,
                    ),
                  ),
                  Text(t.homeReadingMeta(surahName, page, quran.juzOf(first)),
                      style: text.bodySmall?.copyWith(color: YqColors.gold200),),
                  const SizedBox(height: 8),
                  YqProgressLine(value: progress, color: YqColors.gold, track: const Color(0x33E9D49E)),
                ],
              ),
            ),
            if (listenOn) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: t.homeListenTo(surahName),
                child: Semantics(
                  button: true,
                  label: t.homeListenTo(surahName),
                  excludeSemantics: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.push('/quran/listen/${surah.number}'),
                    child: Container(
                      width: YqSpace.touch,
                      height: YqSpace.touch,
                      decoration: const BoxDecoration(color: YqColors.goldLight, shape: BoxShape.circle),
                      child: const Center(child: Icon(Icons.play_arrow_rounded, color: YqColors.navy)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChallengeCard extends ConsumerWidget {
  const _ChallengeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final summary = ref.watch(challengeControllerProvider).valueOrNull;
    // Guests and the not-yet-enrolled get the join CTA (spec §5.9); offline keeps the last cached values.
    final join = !session.canEarnPoints || summary == null || !summary.enrolled;
    return GlassTap(
      onTap: () => context.go('/challenge'),
      semanticLabel: join ? t.homeJoin : t.challengeTitle,
      child: LiquidGlass(
        tone: GlassTone.gold,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          child: Row(
            children: [
              const YqIcon(YqIcons.challenge, size: 28, tone: YqIconTone.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(join ? t.homeJoin : t.challengeTitle, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      join ? t.homeJoinHint : t.challengeDay(summary.dayNumber, YqFormat.number(summary.balance)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: YqColors.goldDeep),
                    ),
                    if (!join) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const YqIcon(YqIcons.streak, size: 14, tone: YqIconTone.gold),
                          const SizedBox(width: 4),
                          Text(
                            t.streakDays(summary.streak),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: YqColors.goldText),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: YqColors.goldText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Services extends ConsumerWidget {
  const _Services();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final hifz = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.hifz)));
    // Qibla has its own live tile above, so the last slot is the hifz plan when it is on.
    final items = [
      (YqIcons.azkar, t.servicesAzkar, '/home/azkar'),
      (YqIcons.dua, t.servicesDuas, '/home/duas'),
      (YqIcons.calendar, t.servicesCalendar, '/challenge/calendar'),
      hifz ? (YqIcons.bookmark, t.quranHifzPlan, '/quran/hifz') : (YqIcons.qibla, t.servicesQibla, '/prayer/qibla'),
    ];
    return Row(
      children: [
        for (final (icon, label, route) in items)
          Expanded(
            child: GlassTap(
              onTap: () => context.push(route),
              semanticLabel: label,
              child: Column(
                children: [
                  SizedBox.square(
                    dimension: 60,
                    child: LiquidGlass(
                      radius: YqRadii.tile,
                      padding: EdgeInsets.zero,
                      highlight: false,
                      child: Center(child: YqIcon(icon)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Ramadan (or Sha'ban's countdown) as one gold band under the orbs: the day of the month and the
/// time to iftar / Fajr. Tap → the imsakiyya. Hidden outside the season or with the flag off.
class _RamadanBand extends ConsumerWidget {
  const _RamadanBand();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ramadanStatusProvider);
    if (!status.visible) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    return Padding(
      padding: const EdgeInsets.only(top: YqSpace.l),
      child: GlassTap(
        onTap: () => context.push('/prayer/ramadan'),
        semanticLabel: t.ramadanTitle,
        child: LiquidGlass(
          tone: GlassTone.gold,
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
          child: Row(
            children: [
              const YqIcon(YqIcons.calendar, size: 22, tone: YqIconTone.gold),
              const SizedBox(width: YqSpace.m),
              Expanded(
                child: Text(
                  status.active ? t.ramadanHomeChip(YqFormat.number(status.hijriDay)) : t.ramadanApproaching,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (status.active)
                YqTicker(
                  now: clock,
                  interval: const Duration(seconds: 30),
                  builder: (context, now) {
                    final d = repo.today(s, now);
                    final m = FastMoment.at(
                      today: repo.forDate(s, d, ramadan: true),
                      tomorrow: repo.forDate(s, DateTime(d.year, d.month, d.day + 1), ramadan: true),
                      now: now,
                    );
                    final target = m.target;
                    if (target == null) return const SizedBox.shrink();
                    final left = YqCountdown.format(target.difference(now.toUtc()));
                    return Text(
                      '${m.phase == FastPhase.fasting ? t.ramadanUntilIftar : t.ramadanUntilFajr} $left',
                      style: YqText.numberSmall.copyWith(color: YqColors.goldText, fontSize: 13),
                    );
                  },
                ),
              const SizedBox(width: YqSpace.xs),
              const Icon(Icons.chevron_right_rounded, color: YqColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
