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
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_countdown.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/prayer_calculator.dart';
import '../domain/prayer_clock.dart';
import '../domain/qibla.dart';
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
    final bearing = qiblaBearing(place.lat, place.lng);

    return AmbientBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(YqSpace.gutter, YqSpace.m, YqSpace.gutter, 140),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text(t.prayerTitle, style: YqText.display.copyWith(fontSize: 28))),
                      Text(
                        '${YqFormat.weekdayDayMonth(date, s.locale)} · ${methodLabel(t, s.method)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: YqSpace.s),
                _LocationChip(label: place.name(s.locale), onTap: _changePlace),
              ],
            ),
            if (_moved case final moved?) ...[
              const SizedBox(height: YqSpace.m),
              _TravelBanner(
                city: moved.name(s.locale),
                onUpdate: () async {
                  await ref.read(settingsProvider.notifier).update((x) => x.copyWith(place: moved));
                  setState(() => _moved = null);
                },
              ),
            ],
            const SizedBox(height: YqSpace.l),
            GlassTap(
              onTap: () => context.push('/prayer/qibla'),
              semanticLabel: t.qiblaOpen,
              child: LiquidGlass(
                child: Row(
                  children: [
                    const YqIconTile(YqIcons.qibla, gold: true, size: 48),
                    const SizedBox(width: YqSpace.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.qiblaCardTitle(YqFormat.number(bearing.round())), style: Theme.of(context).textTheme.titleMedium),
                          Text(t.qiblaCardFrom(directionLabel(t, compassPoint(bearing))), style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Icon(
                      Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                      color: YqColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: YqSpace.l),
            Row(
              children: [
                Expanded(child: Text(t.prayerToday, style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: t.prayerPrevDay,
                  onPressed: () => _pages.previousPage(duration: YqMotion.base, curve: YqMotion.ease),
                  icon: Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: t.prayerNextDay,
                  onPressed: () => _pages.nextPage(duration: YqMotion.base, curve: YqMotion.ease),
                  icon: Icon(Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
                ),
              ],
            ),
            SizedBox(
              height: 6 * 64 + 2 * YqSpace.m,
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                itemBuilder: (context, page) {
                  final d = DateTime(today.year, today.month, today.day + (page - _todayPage));
                  return _DayTimes(date: d, isToday: page == _todayPage);
                },
              ),
            ),
            const SizedBox(height: YqSpace.m),
            YqSection(
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.xs),
              child: YqListRow(
                leading: const YqIconTile(YqIcons.adhan),
                title: t.prayerNotificationsLink,
                onTap: () => context.push('/prayer/notifications'),
              ),
            ),
          ],
        ),
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

/// The six rows for one day; today's next prayer is highlighted with a live countdown.
class _DayTimes extends ConsumerWidget {
  const _DayTimes({required this.date, required this.isToday});
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final clock = ref.watch(clockProvider);
    final times = repo.forDate(s, date);
    final friday = date.weekday == DateTime.friday;
    return YqTicker(
      now: clock,
      interval: const Duration(seconds: 1),
      builder: (context, now) {
        final moment = isToday ? repo.moment(s, now) : null;
        return LiquidGlass(
          padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.m),
          child: Column(
            children: [
              for (final p in displayOrder)
                _PrayerRow(
                  prayer: p,
                  label: prayerLabel(AppLocalizations.of(context), p, friday: friday),
                  time: YqFormat.time(repo.local(s, times.of(p)), s.locale),
                  next: moment?.next == p && repo.local(s, moment!.at).day == date.day ? moment.at.difference(now.toUtc()) : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PrayerRow extends ConsumerWidget {
  const _PrayerRow({required this.prayer, required this.label, required this.time, this.next});
  final PrayerName prayer;
  final String label;
  final String time;

  /// Time left when this is the next prayer.
  final Duration? next;

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
    final highlighted = next != null;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: YqSpace.m),
      decoration: highlighted
          ? BoxDecoration(
              color: const Color(0xB3FFFFFF),
              borderRadius: BorderRadius.circular(YqRadii.tile),
              border: Border.all(color: YqColors.lapis.withAlpha(90), width: 1.2),
              boxShadow: const [BoxShadow(color: Color(0x261F3F94), blurRadius: 16, spreadRadius: -8, offset: Offset(0, 6))],
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                color: highlighted ? YqColors.lapis : YqColors.ink,
              ),
            ),
          ),
          if (highlighted)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: YqSpace.m),
              child: Text(
                t.prayerIn(YqCountdown.format(next!)),
                textDirection: Directionality.of(context),
                style: YqText.numberSmall.copyWith(color: YqColors.lapis),
              ),
            ),
          Text(time, style: YqText.numberSmall.copyWith(fontSize: 16, color: YqColors.ink)),
          const SizedBox(width: YqSpace.s),
          Semantics(
            button: true,
            toggled: on,
            label: on ? t.prayerAlertOn(label) : t.prayerAlertOff(label),
            child: InkResponse(
              radius: 24,
              onTap: () {
                HapticFeedback.selectionClick();
                // Tap toggles adhan ↔ off; long-press chooses adhan / notify / silent.
                _setMode(ref, on ? AlertMode.silent : (prayer == PrayerName.sunrise ? AlertMode.notify : AlertMode.adhan));
              },
              onLongPress: () => _modeSheet(context, ref),
              child: SizedBox.square(
                dimension: YqSpace.touch,
                child: Center(child: YqIcon(YqIcons.adhan, size: 20, tone: on ? YqIconTone.active : YqIconTone.idle)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
