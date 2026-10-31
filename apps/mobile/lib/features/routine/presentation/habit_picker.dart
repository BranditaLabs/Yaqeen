import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../prayer/domain/prayer_clock.dart';
import '../../prayer/presentation/prayer_labels.dart';
import '../domain/routine.dart';

String habitLabel(AppLocalizations t, Habit h) => switch (h) {
      Habit.quran => t.habitQuran,
      Habit.hifz => t.habitHifz,
      Habit.dhikr => t.habitDhikr,
    };

YqIcons habitIcon(Habit h) => switch (h) {
      Habit.quran => YqIcons.quran,
      Habit.hifz => YqIcons.bookmark,
      Habit.dhikr => YqIcons.azkar,
    };

/// One habit of the routine: after which prayer (or at a set time, or off), with today's real
/// time as a preview. Used by the onboarding routine step and by notification settings.
class HabitSlotCard extends ConsumerWidget {
  const HabitSlotCard({super.key, required this.habit, required this.slot, required this.onChanged, this.allowOff = true});

  final Habit habit;
  final RoutineSlot slot;
  final ValueChanged<RoutineSlot> onChanged;
  final bool allowOff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final repo = ref.watch(prayerRepositoryProvider);
    final today = repo.today(s, ref.watch(clockProvider)());
    final at = resolveSlot(slot, repo.forDate(s, today), s.placeOrDefault.timezone);
    final time = at == null ? null : YqFormat.time(repo.local(s, at), s.locale);
    final preview = switch (slot.kind) {
      SlotKind.off => t.slotOffPreview,
      SlotKind.afterPrayer => t.slotPreview(t.slotAfter(prayerLabel(t, slot.prayer!)), time!),
      SlotKind.at => time!,
    };

    Future<void> pickTime() async {
      final start = slot.kind == SlotKind.at ? slot.minutes : 21 * 60;
      final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: start ~/ 60, minute: start % 60));
      if (picked != null) onChanged(RoutineSlot.at(picked.hour * 60 + picked.minute));
    }

    return LiquidGlass(
      padding: const EdgeInsets.all(YqSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              YqIcon(habitIcon(habit), size: 20),
              const SizedBox(width: YqSpace.s),
              Expanded(child: Text(habitLabel(t, habit), style: Theme.of(context).textTheme.titleMedium)),
              Text(
                preview,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: slot.isOff ? YqColors.muted : YqColors.lapis),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.m),
          Wrap(
            spacing: YqSpace.s,
            runSpacing: YqSpace.s,
            children: [
              for (final p in obligatory)
                YqChip(
                  label: t.slotAfter(prayerLabel(t, p)),
                  selected: slot.kind == SlotKind.afterPrayer && slot.prayer == p,
                  onTap: () => onChanged(RoutineSlot.afterPrayer(p)),
                ),
              YqChip(label: t.slotAt, selected: slot.kind == SlotKind.at, onTap: pickTime),
              if (allowOff) YqChip(label: t.slotOff, selected: slot.isOff, onTap: () => onChanged(RoutineSlot.off)),
            ],
          ),
        ],
      ),
    );
  }
}
