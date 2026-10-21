import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/ambient_background.dart';
import '../../core/widgets/controls.dart';
import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/yq_icon.dart';
import '../../l10n/gen/app_localizations.dart';

/// Sample state until the prayer, Quran and challenge repositories land.
class _HomeSample {
  static const name = 'أحمد';
  static const hijri = '8 جمادى الأولى 1448 · القاهرة';
  static const nextPrayerName = 'العصر';
  static const nextPrayerTime = '3:55';
  static const prayers = [('الفجر', '5:30'), ('الظهر', '12:40'), ('العصر', '3:55'), ('المغرب', '6:22'), ('العشاء', '7:40')];
  static const nextIndex = 2;
  static const surah = 'الكهف';
  static const page = 296;
  static const juz = 15;
  static const surahProgress = 0.42;
  static const wirdDone = 2;
  static const wirdTotal = 4;
  static const streak = 12;
  static const challengeDay = 47;
  static const points = 3240;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Duration _remaining = const Duration(hours: 1, minutes: 24, seconds: 10);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _remaining.inSeconds <= 0) return;
      setState(() => _remaining -= const Duration(seconds: 1));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.m, YqSpace.gutter, 140),
          children: [
            _Header(t: t),
            const SizedBox(height: YqSpace.m),
            _NextPrayerCard(t: t, remaining: _remaining),
            const SizedBox(height: YqSpace.m),
            _ContinueReading(t: t),
            const SizedBox(height: YqSpace.m),
            Row(
              children: [
                Expanded(child: _WirdCard(t: t)),
                const SizedBox(width: YqSpace.m),
                Expanded(child: _StreakCard(t: t)),
              ],
            ),
            const SizedBox(height: YqSpace.m),
            _ChallengeCard(t: t),
            const SizedBox(height: YqSpace.l),
            _Services(t: t),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.greetingEvening, style: text.bodySmall?.copyWith(fontSize: 13)),
              Text(_HomeSample.name, style: text.titleLarge?.copyWith(fontSize: 23)),
              Text(_HomeSample.hijri, style: text.bodySmall),
            ],
          ),
        ),
        GlassIconButton(
          tooltip: MaterialLocalizations.of(context).searchFieldLabel,
          onPressed: () => context.go('/quran'),
          icon: const YqIcon(YqIcons.search, size: 20, tone: YqIconTone.idle),
        ),
        const SizedBox(width: YqSpace.s),
        GlassIconButton(
          tooltip: 'Notifications',
          onPressed: () {},
          icon: const YqIcon(YqIcons.adhan, size: 20, tone: YqIconTone.idle),
        ),
      ],
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  const _NextPrayerCard({required this.t, required this.remaining});
  final AppLocalizations t;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassTap(
      onTap: () => context.go('/prayer'),
      semanticLabel: '${t.nextPrayer}: ${_HomeSample.nextPrayerName}',
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
                      Text(_HomeSample.nextPrayerName, style: text.headlineLarge),
                      Text('${_HomeSample.nextPrayerTime} · ${t.adhanIn}', style: text.bodySmall?.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Text(YqFormat.clock(remaining), textDirection: TextDirection.ltr, style: YqText.numeral),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0x247C6127)),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var i = 0; i < _HomeSample.prayers.length; i++)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: i == _HomeSample.nextIndex
                          ? BoxDecoration(color: const Color(0x29C6A867), borderRadius: BorderRadius.circular(14))
                          : null,
                      child: Column(
                        children: [
                          Text(
                            _HomeSample.prayers[i].$1,
                            style: TextStyle(
                              fontSize: 11,
                              color: i == _HomeSample.nextIndex ? YqColors.ink : YqColors.muted,
                              fontWeight: i == _HomeSample.nextIndex ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                          Text(
                            _HomeSample.prayers[i].$2,
                            textDirection: TextDirection.ltr,
                            style: YqText.numberSmall
                                .copyWith(fontSize: 12, color: i == _HomeSample.nextIndex ? YqColors.ink : YqColors.muted),
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
    );
  }
}

class _ContinueReading extends StatelessWidget {
  const _ContinueReading({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassTap(
      onTap: () => context.go('/quran'),
      semanticLabel: t.continueReading,
      child: LiquidGlass(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [YqColors.royal, YqColors.lapis, YqColors.midnight],
                ),
                boxShadow: const [BoxShadow(color: Color(0xB31F3F94), blurRadius: 18, spreadRadius: -10, offset: Offset(0, 10))],
              ),
              child: const Text(
                _HomeSample.surah,
                style: TextStyle(
                  fontFamily: YqFonts.display,
                  fontFamilyFallback: YqFonts.displayFallback,
                  fontSize: 17,
                  color: Color(0xFFF1E2B6),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.continueReading,
                    style: text.labelSmall?.copyWith(color: YqColors.lapis, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Text('سورة ${_HomeSample.surah}', style: text.titleLarge?.copyWith(fontSize: 17)),
                  Text('الصفحة ${_HomeSample.page} · الجزء ${_HomeSample.juz}', style: text.bodySmall),
                  const SizedBox(height: 6),
                  const YqProgressLine(value: _HomeSample.surahProgress),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: YqSpace.touch,
              height: YqSpace.touch,
              decoration: const BoxDecoration(color: YqColors.ink, shape: BoxShape.circle),
              child: const Center(child: YqIcon(YqIcons.play, size: 18, tone: YqIconTone.light)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WirdCard extends StatelessWidget {
  const _WirdCard({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const YqIcon(YqIcons.quran, size: 18),
              const SizedBox(width: 8),
              Text(t.dailyWird, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.pagesOf(_HomeSample.wirdDone, _HomeSample.wirdTotal),
            style: YqText.numberSmall.copyWith(fontSize: 15, color: YqColors.lapis),
          ),
          const SizedBox(height: 8),
          const YqProgressLine(value: _HomeSample.wirdDone / _HomeSample.wirdTotal),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
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
                child: Text(
                  t.streakDays(_HomeSample.streak),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
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
                      color: i < 6 ? YqColors.gold : const Color(0x297C6127),
                      borderRadius: BorderRadius.circular(YqRadii.pill),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    return GlassTap(
      onTap: () => context.go('/challenge'),
      semanticLabel: t.challengeTitle,
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
                  Text(t.challengeTitle, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    t.challengeDay(_HomeSample.challengeDay, YqFormat.number(_HomeSample.points)),
                    style: const TextStyle(fontSize: 12, color: YqColors.goldDeep),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: YqColors.goldText),
          ],
        ),
      ),
    );
  }
}

class _Services extends StatelessWidget {
  const _Services({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final items = [
      (YqIcons.azkar, t.servicesAzkar),
      (YqIcons.dua, t.servicesDuas),
      (YqIcons.qibla, t.servicesQibla),
      (YqIcons.calendar, t.servicesCalendar),
    ];
    return Row(
      children: [
        for (final (icon, label) in items)
          Expanded(
            child: GlassTap(
              onTap: () {},
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
