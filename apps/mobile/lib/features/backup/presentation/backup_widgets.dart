import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'backup_sync.dart';

/// Privacy › «نسخ احتياطي سحابي»: the switch, what it stores, the last backup and "back up now".
/// Guests see it greyed out with "sign in to enable"; turning it off asks first (it deletes the
/// server copy).
class BackupSection extends ConsumerWidget {
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = ref.watch(backupSyncProvider);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final sync = ref.read(backupSyncProvider.notifier);

    Future<void> toggle(bool on) async {
      if (on) return sync.enable();
      final ok = await showYqSheet<bool>(
            context,
            builder: (c) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.backupOffTitle, style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: YqSpace.s),
                Text(t.backupOffBody, style: Theme.of(c).textTheme.bodyMedium),
                const SizedBox(height: YqSpace.l),
                YqButton(label: t.backupOffCta, onPressed: () => Navigator.of(c).pop(true)),
                const SizedBox(height: YqSpace.s),
                YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
              ],
            ),
          ) ??
          false;
      if (ok) await sync.disable();
    }

    final last = status.lastBackupAt?.toLocal();
    final line = status.syncing
        ? t.backupSyncing
        : status.offline
            ? t.backupOffline
            : last == null
                ? t.backupNever
                : t.backupLast('${YqFormat.dayMonth(last, locale)} · ${YqFormat.time(last, locale)}');

    return YqGroup(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.backupTitle, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: YqSpace.xs),
                    Text(t.backupDetail, style: text.bodySmall),
                    if (!status.available) ...[
                      const SizedBox(height: YqSpace.xs),
                      Text(t.backupGuest, style: text.bodySmall?.copyWith(color: YqColors.lapis, fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: YqSpace.m),
              Opacity(
                opacity: status.available ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !status.available,
                  child: YqSwitch(label: t.backupTitle, value: status.enabled, onChanged: toggle),
                ),
              ),
            ],
          ),
        ),
        if (status.enabled)
          YqListRow(
            dense: true,
            title: line,
            trailing: YqButton.text(label: t.backupNow, loading: status.syncing, onPressed: status.syncing ? null : sync.backUpNow),
          ),
      ],
    );
  }
}

/// First sign-in on a new phone, the account has a backup: restore / not now.
Future<void> showRestoreBackupSheet(BuildContext context, WidgetRef ref) async {
  final restore = await showYqSheet<bool>(
    context,
    builder: (c) {
      final t = AppLocalizations.of(c);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.backupRestoreTitle, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: YqSpace.s),
          Text(t.backupRestoreBody, style: Theme.of(c).textTheme.bodyMedium),
          const SizedBox(height: YqSpace.l),
          YqButton(label: t.backupRestoreCta, onPressed: () => Navigator.of(c).pop(true)),
          const SizedBox(height: YqSpace.s),
          YqButton.secondary(label: t.backupNotNow, onPressed: () => Navigator.of(c).pop(false)),
        ],
      );
    },
  );
  final sync = ref.read(backupSyncProvider.notifier);
  if (restore == true) {
    await sync.restore();
    if (context.mounted) YqToast.show(context, AppLocalizations.of(context).backupRestored);
  } else {
    await sync.dismissOffer();
  }
}
