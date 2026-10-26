import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/design/living_sky.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/liquid_orb.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_timeline.dart';
import '../../../core/widgets/yq_countdown.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/prayer_calculator.dart';
import '../domain/prayer_clock.dart';
import '../domain/qibla.dart';
import '../../home/widgets/orbs.dart';
import 'city_picker_sheet.dart';
import 'prayer_labels.dart';

/// `13 · Prayer times` (spec §5.15). Computed on-device; swipe for other days.
class PrayerScreen extends ConsumerStatefulWidget {
  const PrayerScreen({super.key});

  @override
  ConsumerState<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends ConsumerState<PrayerScreen> {
  /// Page 1000 = today; earlier pages are previous days.
  static const _todayPage = 1000;
  final _pages = PageController(initialPage: _todayPage);
  int _page = _todayPage;
  Place? _moved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTravel());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Auto-located users: if the device is now > 25 km away, offer to update (spec §5.15, §6.4).
  Future<void> _checkTravel() async {
    final s = ref.read(settingsProvider);
    final place = s.place;
    if (place == null || !place.auto) return;
    final location = ref.read(locationServiceProvider);
    final fix = await location.current();
    if (fix == null || haversineKm(fix.lat, fix.lng, place.lat, place.lng) <= 25) return;
    final detected = await detectPlace(ref);
    if (mounted && detected != null) setState(() => _moved = detected);
  }

  Future<void> _changePlace() async {
    final place = await showCityPicker(context);
    if (place != null) await ref.read(settingsProvider.notifier).update((s) => s.copyWith(place: place));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final now = ref.watch(clockProvider)();
    final today = repo.today(s, now);
    final date = DateTime(today.year, today.month, today.day + (_page - _todayPage));
    final place = s.placeOrDefault;

    return YqCanvas(
      stage: YqStage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YqStageBar(
              title: t.prayerTitle,
              large: true,
              subtitle: '${YqFormat.weekdayDayMonth(date, s.locale)} · ${methodLabel(t, s.method)}',
              actions: [_LocationChip(label: place.name(s.locale), onTap: _changePlace)],
            ),
            const SizedBox(height: YqSpace.xl),
            const _NextPrayer(),
          ],
        ),
      ),
      children: [
        if (_moved case final moved?) ...[
          _TravelBanner(
            city: moved.name(s.locale),
            onUpdate: () async {
              await ref.read(settingsProvider.notifier).update((x) => x.copyWith(place: moved));
              setState(() => _moved = null);
            },
          ),
          const SizedBox(height: YqSpace.l),
        ],
        const YqOrbRow(orbs: [QiblaOrb(), _DaylightOrb(), _AlertsOrb()]),
        const SizedBox(height: YqSpace.xxl),
        YqHeading(
          _page == _todayPage ? t.prayerToday : YqFormat.weekdayDayMonth(date, s.locale),
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlassIconButton(
                tooltip: t.prayerPrevDay,
                size: 40,
                onPressed: () => _pages.previousPage(duration: YqMotion.base, curve: YqMotion.ease),
                icon: const Icon(Icons.chevron_left_rounded, color: YqColors.ink),
              ),
              const SizedBox(width: YqSpace.s),
              GlassIconButton(
                tooltip: t.prayerNextDay,
                size: 40,
                onPressed: () => _pages.nextPage(duration: YqMotion.base, curve: YqMotion.ease),
                icon: const Icon(Icons.chevron_right_rounded, color: YqColors.ink),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 6 * _DayTimes.rowHeight,
          child: PageView.builder(
            controller: _pages,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (context, page) {
              final d = DateTime(today.year, today.month, today.day + (page - _todayPage));
              return _DayTimes(date: d, page: page - _todayPage);
            },
          ),
        ),
        const SizedBox(height: YqSpace.m),
        YqGroup(
          children: [
            YqListRow(
              leading: const YqIconTile(YqIcons.adhan),
              title: t.prayerNotificationsLink,
              onTap: () => context.push('/prayer/notifications'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The stage's moment: the next prayer in large type, its adhan time and the live countdown, over
/// the day arc. Re-plans every 15 s; only the countdown ticks each second.
class _NextPrayer extends ConsumerWidget {
  const _NextPrayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    final ramadan = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.ramadan)));
    return YqTicker(
      now: clock,
      interval: const Duration(seconds: 15),
      builder: (context, now) {
        final friday = repo.today(s, now).weekday == DateTime.friday;
        final moment = repo.moment(s, now, ramadan: ramadan);
        final shown = moment.current ?? moment.next;
        final name = prayerLabel(t, shown, friday: friday);
        final at = YqFormat.time(repo.local(s, moment.current != null ? moment.currentAt! : moment.at), s.locale);
        final arc = dayArcAt(s, repo, now, ramadan: ramadan);
        return Column(
          children: [
            Semantics(
              container: true,
              excludeSemantics: true,
              label: moment.isPrayerTime ? t.homePrayerNow(name) : t.homeHeroA11y(name, at, YqCountdown.format(moment.at.difference(now.toUtc()))),
              child: YqMoment(
                eyebrow: moment.isPrayerTime ? t.prayerPrayingNow : t.nextPrayer,
                value: Text(name, style: YqMoment.display(context, size: 52)),
                caption: moment.isPrayerTime
                    ? Text(at)
                    : Column(
                        children: [
                          Text('$at · ${t.adhanIn}'),
                          const SizedBox(height: 4),
                          RepaintBoundary(
                            child: YqCountdown(target: moment.at, now: () => clock().toUtc(), style: YqMoment.numeral(size: 40)),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: YqSpace.s),
            DayArc(
              position: arc.position,
              nextIndex: arc.nextIndex,
              night: arc.night,
              height: 78,
              labels: [for (final p in obligatory) prayerLabel(t, p, friday: friday)],
              current: obligatory.indexOf(shown),
            ),
          ],
        );
      },
    );
  }
}

/// Daylight as liquid: the orb fills from sunrise to Maghrib (then from Maghrib to Fajr at night),
/// with the time left in the centre. Local, so it works offline; re-plans every 30 s.
class _DaylightOrb extends ConsumerWidget {
  const _DaylightOrb();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    return YqTicker(
      now: clock,
      interval: const Duration(seconds: 30),
      builder: (context, now) {
        final instant = now.toUtc();
        final today = repo.today(s, now);
        final times = repo.forDate(s, today);
        final day = !instant.isBefore(times.sunrise) && instant.isBefore(times.maghrib);
        late final DateTime from;
        late final DateTime to;
        if (day) {
          (from, to) = (times.sunrise, times.maghrib);
        } else if (instant.isBefore(times.sunrise)) {
          final yesterday = repo.forDate(s, DateTime(today.year, today.month, today.day - 1));
          (from, to) = (yesterday.maghrib, times.fajr);
        } else {
          final tomorrow = repo.forDate(s, DateTime(today.year, today.month, today.day + 1));
          (from, to) = (times.maghrib, tomorrow.fajr);
        }
        final span = to.difference(from).inSeconds;
        final level = span <= 0 ? 0.0 : (instant.difference(from).inSeconds / span).clamp(0.0, 1.0);
        final left = to.difference(instant);
        final leftLabel = left.isNegative ? '0:00' : '${left.inHours}:${(left.inMinutes % 60).toString().padLeft(2, '0')}';
        final until = t.prayerOrbUntil(prayerLabel(t, day ? PrayerName.maghrib : PrayerName.fajr));
        final title = day ? t.prayerOrbDay : t.prayerOrbNight;
        return YqOrb(
          title: title,
          status: until,
          semanticLabel: '$title، $leftLabel $until',
          disc: LiquidOrb(
            level: level,
            size: YqOrb.defaultSize - 12,
            child: Text(
              leftLabel,
              textDirection: TextDirection.ltr,
              style: YqText.numberSmall.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: YqColors.ink),
            ),
          ),
        );
      },
    );
  }
}

/// How many of the six alerts are on, as a ring. Tap → adhan & notifications.
class _AlertsOrb extends ConsumerWidget {
  const _AlertsOrb();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final modes = ref.watch(settingsProvider.select((s) => s.alertModes));
    final on = displayOrder.where((p) => modes[p] != AlertMode.silent).length;
    final total = displayOrder.length;
    final status = t.prayerOrbAlertsStatus(YqFormat.number(on), YqFormat.number(total));
    return YqOrb(
      title: t.prayerOrbAlerts,
      status: status,
      onTap: () => context.push('/prayer/notifications'),
      semanticLabel: '${t.prayerOrbAlerts}: $status',
      disc: YqRing(
        value: on / total,
        size: YqOrb.defaultSize - 12,
        stroke: 5,
        child: const YqIcon(YqIcons.adhan, size: 26),
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassTap(
      onTap: onTap,
      semanticLabel: '${AppLocalizations.of(context).locationTitle}: $label',
      child: LiquidGlass(
        radius: YqRadii.pill,
        highlight: false,
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const YqIcon(YqIcons.location, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelBanner extends StatelessWidget {
  const _TravelBanner({required this.city, required this.onUpdate});
  final String city;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return LiquidGlass(
      tone: GlassTone.gold,
      padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
      child: Row(
        children: [
          Expanded(child: Text(t.prayerTravelPrompt(city), style: const TextStyle(fontWeight: FontWeight.w500))),
          TextButton(onPressed: onUpdate, child: Text(t.prayerTravelUpdate)),
        ],
      ),
    );
  }
}

/// One day as a journey of six stops; today's passed prayers recede and the next one carries a
/// live countdown. [page] is days from today.
class _DayTimes extends ConsumerWidget {
  const _DayTimes({required this.date, required this.page});
  final DateTime date;
  final int page;

  static const rowHeight = 62.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    final times = repo.forDate(s, date);
    final friday = date.weekday == DateTime.friday;
    Widget day(DateTime now) {
      final instant = now.toUtc();
      final moment = page == 0 ? repo.moment(s, now) : null;
      final passed = page < 0 ? displayOrder.length : (page == 0 ? displayOrder.where((p) => !times.of(p).isAfter(instant)).length : 0);
      return YqTimeline(
        pastIndex: passed,
        stops: [
          for (final p in displayOrder)
            _stop(
              t,
              p,
              label: prayerLabel(t, p, friday: friday),
              time: YqFormat.time(repo.local(s, times.of(p)), s.locale),
              nextAt: moment?.next == p && repo.local(s, moment!.at).day == date.day ? moment.at : null,
              clock: clock,
            ),
        ],
      );
    }

    // Other days never change; today re-plans every 15 s (rolls over to the next prayer) while only
    // the countdown text itself ticks each second.
    if (page != 0) return day(clock());
    return YqTicker(now: clock, interval: const Duration(seconds: 15), builder: (context, now) => day(now));
  }

  YqStop _stop(
    AppLocalizations t,
    PrayerName p, {
    required String label,
    required String time,
    required DateTime? nextAt,
    required DateTime Function() clock,
  }) =>
      YqStop(
        time: time,
        title: label,
        highlight: nextAt != null,
        tag: nextAt != null ? t.homeNextTag : null,
        detail: nextAt == null
            ? null
            : YqTicker(
                now: clock,
                builder: (context, n) => Text(
                  t.prayerIn(YqCountdown.format(nextAt.difference(n.toUtc()))),
                  style: YqText.numberSmall.copyWith(color: YqColors.lapis, fontSize: 12),
                ),
              ),
        trailing: _Bell(prayer: p, label: label),
      );
}

/// The alert toggle on a prayer stop: tap toggles adhan ↔ off; long-press chooses the mode.
class _Bell extends ConsumerWidget {
  const _Bell({required this.prayer, required this.label});
  final PrayerName prayer;
  final String label;

  Future<void> _setMode(WidgetRef ref, AlertMode mode) =>
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(alertModes: {...s.alertModes, prayer: mode}), sync: false);

  Future<void> _modeSheet(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final current = ref.read(settingsProvider).alertModes[prayer]!;
    final picked = await showYqSheet<AlertMode>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.prayerModeSheet(label), style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: YqSpace.m),
          for (final m in AlertMode.values)
            YqListRow(
              title: alertLabel(t, m),
              trailing: m == current ? const Icon(Icons.check_rounded, color: YqColors.lapis) : const SizedBox.shrink(),
              onTap: () => Navigator.of(c).pop(m),
            ),
        ],
      ),
    );
    if (picked != null) await _setMode(ref, picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final mode = ref.watch(settingsProvider.select((s) => s.alertModes[prayer]!));
    final on = mode != AlertMode.silent;
    return Semantics(
      button: true,
      toggled: on,
      label: on ? t.prayerAlertOn(label) : t.prayerAlertOff(label),
      child: InkResponse(
        radius: 24,
        onTap: () {
          HapticFeedback.selectionClick();
          _setMode(ref, on ? AlertMode.silent : (prayer == PrayerName.sunrise ? AlertMode.notify : AlertMode.adhan));
        },
        onLongPress: () => _modeSheet(context, ref),
        child: AnimatedContainer(
          duration: YqMotion.base,
          width: YqSpace.touch,
          height: YqSpace.touch,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? const Color(0xB3FFFFFF) : const Color(0x00FFFFFF),
            border: Border.all(color: on ? const Color(0x331F3F94) : const Color(0x00FFFFFF)),
          ),
          child: Center(child: YqIcon(YqIcons.adhan, size: 20, tone: on ? YqIconTone.active : YqIconTone.idle)),
        ),
      ),
    );
  }
}
