import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/notifications/local_notifier.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../core/widgets/yq_timeline.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/data/consent_repository.dart';
import '../../prayer/domain/prayer_calculator.dart';
import '../../prayer/domain/prayer_clock.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../../routine/domain/routine.dart';
import '../../routine/presentation/habit_picker.dart';

/// `15 · Adhan & notifications` (spec §5.17). Every change re-plans the local schedule.
class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  Map<ConsentKind, bool> _consents = const {};

  @override
  void initState() {
    super.initState();
    _consents = ref.read(consentRepositoryProvider).all;
  }

  Future<void> _update(AppSettings Function(AppSettings s) change) => ref.read(settingsProvider.notifier).update(change, sync: false);

  /// Turning a worship alert on checks the OS permission first (spec §5.17).
  Future<bool> _ensurePermission() async {
    final ok = await ref.read(localNotificationsProvider).requestPermission();
    if (ok || !mounted) return ok;
    final t = AppLocalizations.of(context);
    await showYqSheet<void>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.notifPermissionTitle, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: YqSpace.s),
          Text(t.notifPermissionBody, style: Theme.of(c).textTheme.bodyMedium),
          const SizedBox(height: YqSpace.xl),
          YqButton(
            label: t.openSettings,
            onPressed: () {
              ref.read(deviceServicesProvider).openUrl(Uri.parse('app-settings:'));
              Navigator.of(c).pop();
            },
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _setConsent(ConsentKind kind, bool value) async {
    setState(() => _consents = {..._consents, kind: value});
    await ref.read(consentRepositoryProvider).set(kind, value, ConsentSource.settings);
  }

  Future<void> _cycle(PrayerName p, AlertMode current) async {
    final next = switch (current) {
      AlertMode.adhan => AlertMode.notify,
      AlertMode.notify => AlertMode.silent,
      AlertMode.silent => p == PrayerName.sunrise ? AlertMode.notify : AlertMode.adhan,
    };
    if (next != AlertMode.silent && !await _ensurePermission()) return;
    await _update((s) => s.copyWith(alertModes: {...s.alertModes, p: next}));
  }

  Future<void> _pickQuiet({required bool start}) async {
    final s = ref.read(settingsProvider);
    final m = start ? s.quietStartMinutes : s.quietEndMinutes;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (picked == null) return;
    final v = picked.hour * 60 + picked.minute;
    await _update((x) => start ? x.copyWith(quietStartMinutes: v) : x.copyWith(quietEndMinutes: v));
  }

  Widget _minuteChips(List<int> options, int selected, ValueChanged<int> onPick, AppLocalizations t) => Padding(
        padding: const EdgeInsets.only(bottom: YqSpace.m),
        child: Wrap(
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            for (final m in options) YqChip(label: t.minutesShort(m), selected: selected == m, onTap: () => onPick(m)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final text = Theme.of(context).textTheme;

    Widget toggle(String title, String detail, bool value, ValueChanged<bool> onChanged) => YqListRow(
          title: title,
          subtitle: detail,
          trailing: YqSwitch(value: value, onChanged: onChanged, label: title),
        );

    return Scaffold(
      body: YqCanvas(
            bottom: YqSpace.xxl,
            stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.notifSettingsTitle)),
            children: [
              // Today as the reminders will play out — it rearranges as anything below changes.
              YqHeading(t.notifTodayTitle),
              const _TodayReminders(),
              const SizedBox(height: YqSpace.xl),
              // The routine first: when each habit happens drives the Home timeline and these reminders.
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: YqSpace.s),
                child: Text(t.routineSettingsTitle, style: Theme.of(context).textTheme.titleMedium),
              ),
              HabitSlotCard(
                habit: Habit.quran,
                slot: s.quranSlot,
                allowOff: false,
                onChanged: (v) => _update((x) => x.copyWith(quranSlot: v)),
              ),
              if (ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.hifz)))) ...[
                const SizedBox(height: YqSpace.m),
                HabitSlotCard(habit: Habit.hifz, slot: s.hifzSlot, onChanged: (v) => _update((x) => x.copyWith(hifzSlot: v))),
              ],
              const SizedBox(height: YqSpace.m),
              HabitSlotCard(habit: Habit.dhikr, slot: s.dhikrSlot, onChanged: (v) => _update((x) => x.copyWith(dhikrSlot: v))),
              const SizedBox(height: YqSpace.xl),
              YqSection(
                title: t.notifEachPrayer,
                child: Column(
                  children: [
                    for (final p in displayOrder) ...[
                      if (p != displayOrder.first) const YqDivider(),
                      YqListRow(
                        dense: true,
                        title: prayerLabel(t, p),
                        trailing: _ModeChip(
                          mode: s.alertModes[p]!,
                          semanticLabel: t.alertModeA11y(prayerLabel(t, p), alertLabel(t, s.alertModes[p]!)),
                          onTap: () => _cycle(p, s.alertModes[p]!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.l),
              YqSection(
                title: t.notifVoice,
                child: RadioGroup<AdhanVoice>(
                  groupValue: s.adhanVoice,
                  onChanged: (v) => _update((x) => x.copyWith(adhanVoice: v)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (voice, title, detail) in [
                        (AdhanVoice.makkah, t.voiceMakkah, t.voiceMakkahDetail),
                        (AdhanVoice.madinah, t.voiceMadinah, null),
                        (AdhanVoice.calm, t.voiceCalm, null),
                        (AdhanVoice.takbir, t.voiceTakbir, t.voiceTakbirDetail),
                      ])
                        YqListRow(
                          dense: true,
                          title: title,
                          subtitle: detail,
                          trailing: Radio<AdhanVoice>(value: voice),
                          onTap: () => _update((x) => x.copyWith(adhanVoice: voice)),
                        ),
                      if (!PluginLocalNotifier.bundledAdhan) ...[
                        const SizedBox(height: YqSpace.s),
                        Text(t.voicePending, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: YqSpace.l),
              YqSection(
                title: t.notifBefore,
                child: Wrap(
                  spacing: YqSpace.s,
                  runSpacing: YqSpace.s,
                  children: [
                    for (final m in const [0, 5, 10, 15, 20])
                      YqChip(
                        label: m == 0 ? t.notifBeforeNone : t.minutesShort(m),
                        selected: s.preReminderMinutes == m,
                        onTap: () => _update((x) => x.copyWith(preReminderMinutes: m)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.l),
              YqSection(
                title: t.notifOther,
                child: Column(
                  children: [
                    toggle(t.notifMorning, t.notifMorningDetail, s.morningAzkar, (v) => _update((x) => x.copyWith(morningAzkar: v))),
                    const YqDivider(),
                    toggle(t.notifEvening, t.notifEveningDetail, s.eveningAzkar, (v) => _update((x) => x.copyWith(eveningAzkar: v))),
                    const YqDivider(),
                    toggle(t.notifKahf, t.notifKahfDetail, s.kahfFriday, (v) => _update((x) => x.copyWith(kahfFriday: v))),
                    const YqDivider(),
                    toggle(t.notifWird, t.notifWirdDetail, s.wirdMissing, (v) => _update((x) => x.copyWith(wirdMissing: v))),
                    const YqDivider(),
                    toggle(t.notifHifz, t.notifHifzDetail, s.hifzDue, (v) => _update((x) => x.copyWith(hifzDue: v))),
                  ],
                ),
              ),
              // Ramadan reminders are configurable whenever the season is switched on (also in Sha'ban);
              // they fire only on Ramadan days.
              if (ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.ramadan)))) ...[
                const SizedBox(height: YqSpace.l),
                YqSection(
                  title: t.notifSectionRamadan,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      toggle(
                        t.notifSuhoorRow,
                        t.notifSuhoorSub(YqFormat.number(s.suhoorMinutes)),
                        s.suhoorReminder,
                        (v) => _update((x) => x.copyWith(suhoorReminder: v)),
                      ),
                      if (s.suhoorReminder)
                        _minuteChips(
                          const [15, 30, 45, 60],
                          s.suhoorMinutes,
                          (m) => _update((x) => x.copyWith(suhoorMinutes: m)),
                          t,
                        ),
                      const YqDivider(),
                      toggle(
                        t.notifIftarRow,
                        t.notifIftarSub(YqFormat.number(s.iftarMinutes)),
                        s.iftarReminder,
                        (v) => _update((x) => x.copyWith(iftarReminder: v)),
                      ),
                      if (s.iftarReminder)
                        _minuteChips(
                          const [5, 10, 15, 30],
                          s.iftarMinutes,
                          (m) => _update((x) => x.copyWith(iftarMinutes: m)),
                          t,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: YqSpace.l),
              YqSection(
                title: t.notifChallengeSection,
                child: Column(
                  children: [
                    // Both rows mirror the `challenge_rewards` consent bucket; offers → `store_offers`.
                    toggle(
                      t.notifChallenge,
                      t.notifChallengeDetail,
                      _consents[ConsentKind.challengeRewards] ?? false,
                      (v) => _setConsent(ConsentKind.challengeRewards, v),
                    ),
                    const YqDivider(),
                    toggle(
                      t.notifRewards,
                      t.notifRewardsDetail,
                      _consents[ConsentKind.challengeRewards] ?? false,
                      (v) => _setConsent(ConsentKind.challengeRewards, v),
                    ),
                    const YqDivider(),
                    toggle(
                      t.notifOffers,
                      t.notifOffersDetail,
                      _consents[ConsentKind.storeOffers] ?? false,
                      (v) => _setConsent(ConsentKind.storeOffers, v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.l),
              YqSection(
                title: t.notifQuiet,
                action: YqSwitch(value: s.quietHours, onChanged: (v) => _update((x) => x.copyWith(quietHours: v)), label: t.notifQuiet),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t.notifQuietDetail, style: text.bodySmall),
                    const SizedBox(height: YqSpace.m),
                    Row(
                      children: [
                        Expanded(
                          child: YqButton.secondary(
                            label: '${t.notifQuietFrom} ${YqFormat.minutesOfDay(s.quietStartMinutes, s.locale)}',
                            onPressed: s.quietHours ? () => _pickQuiet(start: true) : null,
                          ),
                        ),
                        const SizedBox(width: YqSpace.m),
                        Expanded(
                          child: YqButton.secondary(
                            label: '${t.notifQuietTo} ${YqFormat.minutesOfDay(s.quietEndMinutes, s.locale)}',
                            onPressed: s.quietHours ? () => _pickQuiet(start: false) : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: YqSpace.l),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: YqSpace.s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const YqIcon(YqIcons.adhan, size: 16, tone: YqIconTone.idle),
                    const SizedBox(width: YqSpace.s),
                    Expanded(child: Text(t.notifFooter(methodLabel(t, s.method)), style: text.bodySmall)),
                  ],
                ),
              ),
            ],
      ),
    );
  }
}

/// Today's reminders as a journey: each prayer with its alert, the azkar windows and the routine
/// at their times; what has passed recedes. Read-only — the controls are below.
class _TodayReminders extends ConsumerWidget {
  const _TodayReminders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final now = ref.watch(clockProvider)();
    final times = repo.forDate(s, repo.today(s, now));
    final hifzOn = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.hifz)));
    String at(DateTime utc) => YqFormat.time(repo.local(s, utc), s.locale);
    final entries = <(YqStop, DateTime)>[
      for (final p in displayOrder)
        (
          YqStop(
            time: at(times.of(p)),
            title: prayerLabel(t, p),
            trailing: Text(
              alertLabel(t, s.alertModes[p]!),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: s.alertModes[p] == AlertMode.silent ? YqColors.slate400 : YqColors.lapis,
              ),
            ),
          ),
          times.of(p),
        ),
      if (s.morningAzkar) (YqStop(time: at(times.fajr), title: t.azkarMorning, icon: YqIcons.azkar, style: StopStyle.pill), times.fajr),
      if (s.eveningAzkar) (YqStop(time: at(times.asr), title: t.azkarEvening, icon: YqIcons.azkar, style: StopStyle.pill), times.asr),
    ];
    for (final (h, slot) in [(Habit.quran, s.quranSlot), if (hifzOn) (Habit.hifz, s.hifzSlot), (Habit.dhikr, s.dhikrSlot)]) {
      final when = resolveSlot(slot, times, s.placeOrDefault.timezone);
      if (when != null) entries.add((YqStop(time: at(when), title: habitLabel(t, h), icon: habitIcon(h), style: StopStyle.pill), when));
    }
    final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])]..sort((a, b) {
        final c = a.$2.$2.compareTo(b.$2.$2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    final instant = now.toUtc();
    return ExcludeSemantics(
      child: YqTimeline(
        pastIndex: indexed.where((e) => !e.$2.$2.isAfter(instant)).length,
        stops: [for (final e in indexed) e.$2.$1],
      ),
    );
  }
}

/// «أذان | تنبيه | صامت» — tap cycles.
class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode, required this.onTap, required this.semanticLabel});
  final AlertMode mode;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: YqChip(label: alertLabel(t, mode), selected: mode != AlertMode.silent, onTap: onTap),
    );
  }
}
