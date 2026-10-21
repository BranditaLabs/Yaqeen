import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/data/consent_repository.dart';

/// Inputs from other features that change the reminder schedule.
class ReminderInputs {
  const ReminderInputs({this.wirdDoneToday = false, this.hifzDue = const {}});
  final bool wirdDoneToday;
  final Set<DateTime> hifzDue;
}

/// Overridden by the reading/hifz features through [reminderInputsProvider] reads.
final reminderInputsProvider = FutureProvider<ReminderInputs>((_) async => const ReminderInputs());

/// Keeps the local notification schedule in sync (spec §6.5): re-plans when settings change and on
/// demand (start, resume, wird done, hifz rated). Also moves delivered reminders into the inbox.
class RemindersController extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.listen(settingsProvider, (prev, next) {
      if (prev != next) replan();
    });
    return null;
  }

  Future<void> replan() async {
    final s = ref.read(settingsProvider);
    final now = ref.read(clockProvider)();
    final inputs = await ref.read(reminderInputsProvider.future);
    final consents = ref.read(consentRepositoryProvider);
    final service = ref.read(reminderServiceProvider);
    await service.collectDelivered(s, now, lookupAppLocalizations(Locale(s.locale)));
    final plan = await service.replan(
      s,
      now: now,
      worshipConsent: consents.granted(ConsentKind.worshipReminders),
      wirdDone: inputs.wirdDoneToday,
      hifzDue: inputs.hifzDue,
      ramadan: ref.read(remoteConfigProvider).isOn(Flags.ramadan),
    );
    state = plan.replanBefore;
  }
}

final remindersControllerProvider = NotifierProvider<RemindersController, DateTime?>(RemindersController.new);
