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

/// `07 · Home` (spec §5.9) — today at a glance. Everything but the challenge numbers is local, so
/// the screen never waits on the network.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: YqColors.lapis,
          onRefresh: () async {
            ref.invalidate(challengeControllerProvider);
            ref.invalidate(hijriTodayProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.m, YqSpace.gutter, 140),
            children: [
              const _Header(),
              const SizedBox(height: YqSpace.m),
              const _NextPrayerCard(),
              const SizedBox(height: YqSpace.m),
              const _ContinueReading(),
              const SizedBox(height: YqSpace.m),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _WirdCard()),
                  SizedBox(width: YqSpace.m),
                  Expanded(child: _StreakCard()),
                ],
              ),
              if (ref.watch(remoteConfigProvider).isOn(Flags.challenge)) ...[const SizedBox(height: YqSpace.m), const _ChallengeCard()],
              const SizedBox(height: YqSpace.l),
              Text(t.servicesTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: YqSpace.m),
              const _Services(),
            ],
          ),
        ),
      ),
    );
  }
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
                _ => Text(place, style: text.bodySmall),
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

class _NextPrayerCard extends ConsumerWidget {
  const _NextPrayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    final ramadan = ref.watch(remoteConfigProvider).isOn(Flags.ramadan);

    // Ticks every second only while visible; pauses in the background (YqTicker).
    return YqTicker(
      now: clock,
      builder: (context, now) {
        final today = repo.today(s, now);
        final friday = today.weekday == DateTime.friday;
        final times = repo.forDate(s, today, ramadan: ramadan);
        final moment = repo.moment(s, now, ramadan: ramadan);
        final shown = moment.current ?? moment.next;
        final name = prayerLabel(t, shown, friday: friday);
        final at = YqFormat.time(repo.local(s, moment.current != null ? moment.currentAt! : moment.at), s.locale);
        final left = YqCountdown.format(moment.at.difference(now.toUtc()));
        return Semantics(
          button: true,
          container: true,
          excludeSemantics: true,
          label: moment.isPrayerTime ? t.homePrayerNow(name) : t.homeHeroA11y(name, at, left),
          onTap: () => context.go('/prayer'),
          child: GlassTap(
            onTap: () => context.go('/prayer'),
            child: LiquidGlass(
              radius: YqRadii.hero,
              tone: GlassTone.gold,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const YqIcon(YqIcons.prayer, size: 16, tone: YqIconTone.gold),
                                const SizedBox(width: 6),
                                Text(
                                  t.nextPrayer,
                                  style: text.labelSmall?.copyWith(color: YqColors.goldText, fontWeight: FontWeight.w500, fontSize: 12),
                                ),
                              ],
                            ),
                            Text(moment.isPrayerTime ? t.homePrayerNow(name) : name, style: text.headlineLarge),
                            if (!moment.isPrayerTime) Text('$at · ${t.adhanIn}', style: text.bodySmall?.copyWith(fontSize: 13)),
                          ],
                        ),
                      ),
                      if (!moment.isPrayerTime)
                        Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: Text(left, textDirection: TextDirection.ltr, style: YqText.numeral),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Color(0x247C6127)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final p in obligatory)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            decoration:
                                p == shown ? BoxDecoration(color: const Color(0x29C6A867), borderRadius: BorderRadius.circular(14)) : null,
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
                                  style: YqText.numberSmall.copyWith(fontSize: 12, color: p == shown ? YqColors.ink : YqColors.muted),
                                ),
                              ],
                            ),
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
                    style: const TextStyle(
                      fontFamily: YqFonts.display,
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

class _WirdCard extends ConsumerWidget {
  const _WirdCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final wird = ref.watch(todayWirdProvider).valueOrNull;
    final today = ref.watch(prayerRepositoryProvider).today(s, ref.watch(clockProvider)());
    final iso = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final done = wird != null && wird.date == iso ? wird.count : 0;
    final goal = s.wirdGoalPages;
    return GlassTap(
      onTap: () => context.go('/quran'),
      semanticLabel: '${t.dailyWird}، ${t.pagesOf(done, goal)}',
      child: LiquidGlass(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const YqIcon(YqIcons.quran, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(t.dailyWird, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              ],
            ),
            const SizedBox(height: 8),
            Text(t.pagesOf(done.clamp(0, goal), goal), style: YqText.numberSmall.copyWith(fontSize: 15, color: YqColors.lapis)),
            const SizedBox(height: 8),
            YqProgressLine(value: goal == 0 ? 0 : (done / goal).clamp(0, 1)),
          ],
        ),
      ),
    );
  }
}

class _StreakCard extends ConsumerWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final summary = ref.watch(challengeControllerProvider).valueOrNull;
    final streak = summary?.streak ?? 0;
    return LiquidGlass(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YqIcon(YqIcons.streak, size: 18, tone: YqIconTone.gold),
              const SizedBox(width: 8),
              Flexible(
                child: Text(t.streakDays(streak), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < streak.clamp(0, 7) ? YqColors.gold : const Color(0x297C6127),
                      borderRadius: BorderRadius.circular(YqRadii.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (summary != null && !summary.todayComplete) ...[
            const SizedBox(height: 8),
            Text(t.homeStreakHint, style: const TextStyle(fontSize: 11, color: YqColors.goldText)),
          ],
        ],
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
            Icon(
              Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
              color: YqColors.goldText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Services extends StatelessWidget {
  const _Services();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final items = [
      (YqIcons.azkar, t.servicesAzkar, '/home/azkar'),
      (YqIcons.dua, t.servicesDuas, '/home/duas'),
      (YqIcons.qibla, t.servicesQibla, '/prayer/qibla'),
      (YqIcons.calendar, t.servicesCalendar, '/challenge/calendar'),
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
                  Text(label, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
