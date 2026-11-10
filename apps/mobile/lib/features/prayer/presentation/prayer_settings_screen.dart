import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../calendar/data/hijri_today.dart';
import '../domain/prayer_calculator.dart';
import '../domain/prayer_clock.dart';
import 'city_picker_sheet.dart';
import 'prayer_labels.dart';

/// Prayer settings after onboarding (spec §6.2, §6.4, §6.10): place, calculation method (every one,
/// the recommended first), Asr school, high-latitude rule, per-prayer minute adjustments and the
/// personal Hijri offset. Method, Asr and the offset sync (PATCH /v1/me/settings); the rest stays
/// on the device. Every change re-plans the local reminders.
class PrayerSettingsScreen extends ConsumerWidget {
  const PrayerSettingsScreen({super.key});

  /// Per-prayer adjustments stay within ± half an hour.
  static const maxAdjust = 30;

  static PrayerAdjustments adjusted(PrayerAdjustments a, PrayerName p, int delta) {
    int v(PrayerName q) => q == p ? (a.of(q) + delta).clamp(-maxAdjust, maxAdjust) : a.of(q);
    return PrayerAdjustments(
      fajr: v(PrayerName.fajr),
      sunrise: v(PrayerName.sunrise),
      dhuhr: v(PrayerName.dhuhr),
      asr: v(PrayerName.asr),
      maghrib: v(PrayerName.maghrib),
      isha: v(PrayerName.isha),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final recommended = CalcMethod.recommendedFor(s.placeOrDefault.country);
    final methods = [recommended, ...CalcMethod.values.where((m) => m != recommended)];
    final hijri = ref.watch(hijriTodayProvider).valueOrNull;

    return Scaffold(
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.prayerSettingsTitle)),
        children: [
          YqGroup(
            children: [
              YqListRow(
                leading: const YqIconTile(YqIcons.location),
                title: s.placeOrDefault.name(s.locale),
                subtitle: t.locationTitle,
                trailing: YqButton.text(
                  label: t.locationChange,
                  onPressed: () async {
                    final place = await showCityPicker(context);
                    if (place != null && context.mounted) await savePlace(context, ref, place);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.l),
          YqSection(
            title: t.prayerSetupMethod,
            child: RadioGroup<CalcMethod>(
              groupValue: s.method,
              onChanged: (m) => ctl.update((x) => x.copyWith(method: m)),
              child: Column(
                children: [
                  for (final m in methods) ...[
                    if (m != methods.first) const YqDivider(),
                    YqListRow(
                      dense: true,
                      title: methodLabel(t, m),
                      subtitle: m == recommended ? t.methodRecommended : null,
                      trailing: Radio<CalcMethod>(value: m),
                      onTap: () => ctl.update((x) => x.copyWith(method: m)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: YqSpace.l),
          YqSection(
            title: t.prayerSetupAsr,
            child: YqSegmented<AsrSchool>(
              segments: [(AsrSchool.standard, t.asrStandard), (AsrSchool.hanafi, t.asrHanafi)],
              selected: s.asr,
              onChanged: (v) => ctl.update((x) => x.copyWith(asr: v)),
            ),
          ),
          const SizedBox(height: YqSpace.l),
          YqSection(
            title: t.prayerSettingsHighLat,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.prayerSettingsHighLatDetail, style: text.bodySmall),
                const SizedBox(height: YqSpace.m),
                YqSegmented<HighLatitudeRule>(
                  segments: [
                    (HighLatitudeRule.twilightAngle, t.highLatTwilight),
                    (HighLatitudeRule.middleOfTheNight, t.highLatMiddle),
                    (HighLatitudeRule.seventhOfTheNight, t.highLatSeventh),
                  ],
                  selected: s.highLatitude,
                  onChanged: (v) => ctl.update((x) => x.copyWith(highLatitude: v), sync: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: YqSpace.l),
          YqSection(
            title: t.prayerSettingsAdjust,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.prayerSettingsAdjustDetail, style: text.bodySmall),
                const SizedBox(height: YqSpace.s),
                for (final p in displayOrder)
                  _AdjustRow(
                    label: prayerLabel(t, p),
                    minutes: s.adjustments.of(p),
                    onChange: (delta) => ctl.update((x) => x.copyWith(adjustments: adjusted(x.adjustments, p, delta)), sync: false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: YqSpace.l),
          YqSection(
            title: t.hijriOffsetTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.hijriOffsetDetail, style: text.bodySmall),
                const SizedBox(height: YqSpace.m),
                YqSegmented<int>(
                  segments: [(-1, t.hijriOffsetMinus), (0, t.hijriOffsetNone), (1, t.hijriOffsetPlus)],
                  selected: s.hijriOffsetDays.clamp(-1, 1),
                  onChanged: (v) => ctl.update((x) => x.copyWith(hijriOffsetDays: v)),
                ),
                if (hijri != null) ...[
                  const SizedBox(height: YqSpace.s),
                  Text(
                    t.hijriOffsetPreview(hijri.label(s.locale)),
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(color: YqColors.lapis),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: YqSpace.l),
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
      ),
    );
  }
}

/// «الفجر   −  +2 د  +» — one minute per tap, earlier or later.
class _AdjustRow extends StatelessWidget {
  const _AdjustRow({required this.label, required this.minutes, required this.onChange});
  final String label;
  final int minutes;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final value = minutes == 0 ? YqFormat.number(0) : '${minutes > 0 ? '+' : '−'}${t.minutesShort(minutes.abs())}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YqSpace.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500))),
          GlassIconButton(
            tooltip: t.prayerAdjustEarlier(label),
            onPressed: minutes > -PrayerSettingsScreen.maxAdjust ? () => onChange(-1) : null,
            icon: const Icon(Icons.remove_rounded, color: YqColors.ink),
          ),
          SizedBox(
            width: 64,
            child: Text(
              value,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: YqText.numberSmall.copyWith(color: minutes == 0 ? YqColors.muted : YqColors.lapis),
            ),
          ),
          GlassIconButton(
            tooltip: t.prayerAdjustLater(label),
            onPressed: minutes < PrayerSettingsScreen.maxAdjust ? () => onChange(1) : null,
            icon: const Icon(Icons.add_rounded, color: YqColors.ink),
          ),
        ],
      ),
    );
  }
}
