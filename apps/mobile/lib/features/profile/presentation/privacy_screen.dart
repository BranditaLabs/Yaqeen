import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../backup/presentation/backup_widgets.dart';
import '../../notifications/presentation/reminders_controller.dart';
import '../../onboarding/data/consent_repository.dart';

/// «الخصوصية والموافقات» (`/profile/privacy`) — the same five switches as onboarding, recorded with
/// source `settings`, then the opt-in cloud backup (signed-in accounts only).
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  static const _notificationKinds = {ConsentKind.worshipReminders, ConsentKind.challengeRewards, ConsentKind.storeOffers};

  Future<void> _set(ConsentKind k, bool v) async {
    final consents = ref.read(consentRepositoryProvider);
    await consents.record(k, v, ConsentSource.settings);
    // The switch follows the tap; the event reaches the server in the background (queued offline).
    if (mounted) setState(() {});
    unawaited(consents.syncAll().catchError((Object _) {}));
    if (k == ConsentKind.adsMeasurement) {
      // ATT first (iOS), so the SDKs start with its answer.
      if (v) await ref.read(deviceServicesProvider).requestTracking();
      await ref.read(analyticsProvider).onConsentChanged(v);
    }
    if (k == ConsentKind.productAnalytics) await ref.read(productAnalyticsProvider).onConsentChanged(v);
    // Same OS prompt as onboarding: a notification switch turned on needs the permission to deliver.
    if (v && _notificationKinds.contains(k)) await ref.read(localNotificationsProvider).requestPermission();
    // Worship reminders are local: schedule them now, or cancel the ones already planned.
    if (k == ConsentKind.worshipReminders) ref.read(remindersControllerProvider.notifier).replan().ignore();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final consents = ref.watch(consentRepositoryProvider);
    final rows = [
      (ConsentKind.worshipReminders, t.consentWorship, t.consentWorshipDetail),
      (ConsentKind.challengeRewards, t.consentChallenge, t.consentChallengeDetail),
      (ConsentKind.storeOffers, t.consentOffers, t.consentOffersDetail),
      (ConsentKind.adsMeasurement, t.consentAds, t.consentAdsDetail),
      (ConsentKind.productAnalytics, t.consentAnalytics, t.consentAnalyticsDetail),
    ];
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(compact: true, child: YqStageBar(back: true, title: t.profilePrivacy)),
        children: [
          LiquidGlass(
            padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
            child: Column(
              children: [
                for (final (i, (k, title, detail)) in rows.indexed) ...[
                  if (i > 0) const YqDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                              Text(detail, style: text.bodySmall),
                            ],
                          ),
                        ),
                        YqSwitch(label: title, value: consents.granted(k), onChanged: (v) => _set(k, v)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: YqSpace.m),
          Text(t.consentPrivacyNote, style: text.bodySmall?.copyWith(color: YqColors.success)),
          const SizedBox(height: YqSpace.l),
          const BackupSection(),
        ],
      ),
    );
  }
}
