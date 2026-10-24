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
import '../../core/widgets/ambient_background.dart';
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
import '../prayer/domain/prayer_clock.dart';
import '../prayer/presentation/prayer_labels.dart';
import '../quran/domain/quran_data.dart';
import '../quran/presentation/quran_index_screen.dart';
import '../quran/presentation/reader_screen.dart';
import 'widgets/home_tiles.dart';
import 'widgets/liquid_orb.dart';
import 'widgets/progress_ring.dart';
import 'widgets/sky_arc.dart';

/// `07 · Home` (spec §5.9) — today at a glance, with live tools.
///
/// Order is by what people reach for: the next prayer, where they stopped reading, then working
/// widgets (a live Qibla compass and a tasbeeh counter) and the day's progress. Everything but the
/// challenge numbers is local, so the screen never waits on the network. Sections rise in once,
/// staggered, on first open (not on every tab switch; skipped with reduced motion).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final challenge = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.challenge)));
    final sections = <Widget>[
      const _Header(),
      const _PrayerHero(),
      const _ContinueReading(),
      _SectionTitle(t.homeToolsTitle),
      const _Pair(QiblaTile(), TasbeehTile()),
      const _Pair(_WirdTile(), _StreakTile()),
      const _AzkarNow(),
      if (challenge) const _ChallengeCard(),
      _SectionTitle(t.servicesTitle),
      const _Services(),
    ];
    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: YqColors.lapis,
          onRefresh: () async {
            ref.invalidate(challengeControllerProvider);
            ref.invalidate(hijriTodayProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.m, YqSpace.gutter, 140),
            itemCount: sections.length,
            separatorBuilder: (_, i) => SizedBox(height: sections[i + 1] is _SectionTitle ? YqSpace.xl : YqSpace.m),
            itemBuilder: (_, i) => _Reveal(order: i, child: sections[i]),
          ),
        ),
      ),
    );
  }
}

/// Rises and fades in once, staggered by [order].
class _Reveal extends StatelessWidget {
  const _Reveal({required this.order, required this.child});
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final start = (order * 0.07).clamp(0.0, 0.6);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
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

/// Two equal tiles side by side.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: a), const SizedBox(width: YqSpace.m), Expanded(child: b)],
        ),
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
                AsyncData(value: final h?) => Text('${h.hijriDay} ${h.monthNameAr} ${h.hijriYear} · $place', style: text.bodySmall),
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
class _PrayerHero extends ConsumerWidget {
  const _PrayerHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    final ramadan = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.ramadan)));
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return YqTicker(
      now: clock,
      interval: const Duration(seconds: 15),
      builder: (context, now) {
        final today = repo.today(s, now);
        final friday = today.weekday == DateTime.friday;
        final times = repo.forDate(s, today, ramadan: ramadan);
        final moment = repo.moment(s, now, ramadan: ramadan);
        final shown = moment.current ?? moment.next;
        final name = prayerLabel(t, shown, friday: friday);
        final at = YqFormat.time(repo.local(s, moment.current != null ? moment.currentAt! : moment.at), s.locale);
        final left = YqCountdown.format(moment.at.difference(now.toUtc()));

        final instant = now.toUtc();
        final prayers = [for (final p in obligatory) times.of(p)];
        final yesterday = repo.forDate(s, DateTime(today.year, today.month, today.day - 1), ramadan: ramadan);
        final tomorrow = repo.forDate(s, DateTime(today.year, today.month, today.day + 1), ramadan: ramadan);
        final position = skyPosition(prayers, yesterday.isha, tomorrow.fajr, instant);
        final nextIndex = prayers.where((x) => !x.isAfter(instant)).length;
        final phase = instant.isBefore(times.fajr) || !instant.isBefore(times.isha)
            ? SkyPhase.night
            : instant.isBefore(times.sunrise.add(const Duration(minutes: 40)))
                ? SkyPhase.dawn
                : instant.isBefore(times.asr)
                    ? SkyPhase.day
                    : instant.isBefore(times.maghrib)
                        ? SkyPhase.golden
                        : SkyPhase.dusk;

        return Semantics(
          button: true,
          container: true,
          excludeSemantics: true,
          label: moment.isPrayerTime ? t.homePrayerNow(name) : t.homeHeroA11y(name, at, left),
          onTap: () => context.go('/prayer'),
          child: GlassTap(
            onTap: () => context.go('/prayer'),
            child: AnimatedContainer(
              duration: YqMotion.slow,
              curve: YqMotion.ease,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(YqRadii.hero),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: skyColors(phase)),
                border: Border.all(color: const Color(0xE6FFFFFF)),
                boxShadow: const [BoxShadow(color: Color(0x2E0F1A36), blurRadius: 34, spreadRadius: -14, offset: Offset(0, 16))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.nextPrayer,
                              style: text.labelSmall?.copyWith(color: YqColors.goldText, fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                            Text(
                              moment.isPrayerTime ? t.homePrayerNow(name) : name,
                              style: text.headlineLarge?.copyWith(fontSize: moment.isPrayerTime ? 24 : 36, height: 1.2),
                            ),
                            if (!moment.isPrayerTime) Text('$at · ${t.adhanIn}', style: text.bodySmall?.copyWith(fontSize: 13)),
                          ],
                        ),
                      ),
                      if (!moment.isPrayerTime)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: RepaintBoundary(
                            child: YqCountdown(
                              target: moment.at,
                              now: () => clock().toUtc(),
                              style: YqText.numeral.copyWith(fontSize: 30, fontWeight: FontWeight.w500, color: YqColors.ink, height: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  RepaintBoundary(
                    child: SizedBox(
                      height: 72,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: position),
                        duration: YqMotion.slow,
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => CustomPaint(
                          painter: SkyArcPainter(position: v, nextIndex: nextIndex, night: phase == SkyPhase.night, rtl: rtl),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final p in obligatory)
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                prayerLabel(t, p, friday: friday),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: p == shown ? YqColors.ink : YqColors.muted,
                                  fontWeight: p == shown ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                              Text(
                                YqFormat.time(repo.local(s, times.of(p)), s.locale, suffix: false),
                                textDirection: TextDirection.ltr,
                                style: YqText.numberSmall.copyWith(
                                  fontSize: 12,
                                  color: p == shown ? YqColors.ink : YqColors.muted,
                                  fontWeight: p == shown ? FontWeight.w500 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
    final surahPages =
        (surah.number < QuranData.surahCount ? quran.surah(surah.number + 1).startPage : QuranData.pageCount + 1) - surah.startPage;
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
                  Text(t.homeReadingMeta(surahName, page, quran.juzOf(first)), style: text.bodySmall?.copyWith(color: YqColors.gold200)),
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

/// Today's wird as a glass orb that fills like water as pages are read.
class _WirdTile extends ConsumerWidget {
  const _WirdTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final wird = ref.watch(todayWirdProvider).valueOrNull;
    final today = ref.watch(prayerRepositoryProvider).today(s, ref.watch(clockProvider)());
    final iso = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final done = wird != null && wird.date == iso ? wird.count : 0;
    final goal = s.wirdGoalPages;
    final shown = done.clamp(0, goal);
    final complete = goal > 0 && done >= goal;
    return GlassTap(
      onTap: () => context.go('/quran'),
      semanticLabel: '${t.dailyWird}، ${t.pagesOf(shown, goal)}',
      child: LiquidGlass(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            LiquidOrb(level: goal == 0 ? 0 : done / goal, size: 50, complete: complete, child: const YqIcon(YqIcons.quran, size: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.dailyWird,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child:
                        Text(t.pagesOf(shown, goal), maxLines: 1, style: YqText.numberSmall.copyWith(fontSize: 13, color: YqColors.lapis)),
                  ),
                  Text(
                    complete ? t.homeWirdDone : t.homeWirdLeft(YqFormat.number(goal - shown)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: complete ? YqColors.success : YqColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Streak: days in a row, as a ring that fills over each week.
class _StreakTile extends ConsumerWidget {
  const _StreakTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final summary = ref.watch(challengeControllerProvider).valueOrNull;
    final streak = summary?.streak ?? 0;
    final week = streak == 0 ? 0.0 : ((streak - 1) % 7 + 1) / 7;
    return GlassTap(
      onTap: () => context.go('/challenge'),
      semanticLabel: t.streakDays(streak),
      child: LiquidGlass(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ProgressRing(
              value: week,
              size: 48,
              stroke: 5,
              color: YqColors.gold,
              track: const Color(0x2EC6A867),
              child: Text(YqFormat.number(streak), style: YqText.numberSmall.copyWith(fontSize: 15, color: YqColors.goldDeep)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      t.streakDays(streak),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (summary == null || !summary.todayComplete)
                    Text(
                      t.homeStreakHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, height: 1.3, color: YqColors.goldText),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The azkar that fit the time of day: morning from Fajr until Dhuhr, evening after.
class _AzkarNow extends ConsumerWidget {
  const _AzkarNow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final now = ref.watch(clockProvider)().toUtc();
    final times = repo.forDate(s, repo.today(s, now));
    final morning = !now.isBefore(times.fajr) && now.isBefore(times.dhuhr);
    final title = morning ? t.azkarMorning : t.azkarEvening;
    return GlassTap(
      onTap: () => context.push('/home/azkar?set=${morning ? 'morning' : 'evening'}'),
      semanticLabel: title,
      child: LiquidGlass(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: morning ? const [Color(0xFFFFF3D6), YqColors.goldLight] : const [YqColors.sky100, YqColors.sky400],
                ),
              ),
              child: Center(child: YqIcon(YqIcons.azkar, size: 22, tone: morning ? YqIconTone.gold : YqIconTone.active)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(t.homeAzkarHint, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: YqColors.muted),
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
                    style: const TextStyle(fontSize: 12, color: YqColors.goldDeep),
                  ),
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
