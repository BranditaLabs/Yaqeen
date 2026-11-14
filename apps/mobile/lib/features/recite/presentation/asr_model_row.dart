import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../content/presentation/pack_row.dart' show megabytes;
import 'asr_model_controller.dart';
import 'asr_model_sheet.dart';
import 'recite_available.dart';

/// Settings › «التعرّف على التلاوة على الجهاز»: the size, «تنزيل» (through the calm sheet, so the
/// privacy line and the Wi-Fi rule are always seen), a progress ring while it downloads (tap to
/// cancel), «حذف» once it is on the phone. Hidden where «تسميع» is not offered.
class AsrModelRow extends ConsumerWidget {
  const AsrModelRow({super.key, this.leading = true});

  /// The icon tile (Settings); the Downloads list has none.
  final bool leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(reciteEntryProvider)) return const SizedBox.shrink();
    final t = AppLocalizations.of(context);
    final s = ref.watch(asrModelControllerProvider);
    final c = ref.read(asrModelControllerProvider.notifier);
    final onDisk = ref.watch(asrModelBytesProvider).valueOrNull ?? 0;
    final progress = s.progress;
    final subtitle = progress != null
        ? t.asrSettingsDownloading('${YqFormat.number((progress * 100).round())}%')
        : s.ready
            ? t.asrSettingsReady(megabytes(t, onDisk > 0 ? onDisk : s.bytes))
            : s.failed
                ? t.asrSettingsFailed
                : t.asrSettingsDownload(megabytes(t, s.bytes));
    return YqListRow(
      title: t.asrSettingsTitle,
      subtitle: subtitle,
      leading: leading ? const YqIconTile(YqIcons.recite, size: 36) : null,
      trailing: progress != null
          ? Semantics(
              button: true,
              label: t.cancel,
              value: '${YqFormat.number((progress * 100).round())}%',
              child: InkResponse(onTap: c.cancel, child: YqRing(value: progress, size: 22, stroke: 2.4)),
            )
          : s.ready
              ? TextButton(onPressed: () => _delete(context, ref), child: Text(t.delete))
              : IconButton(
                  tooltip: t.asrDownload,
                  onPressed: () => ensureReciteModel(context, ref),
                  icon: const Icon(Icons.download_rounded, color: YqColors.lapis),
                ),
      onTap: progress != null || s.ready ? null : () => ensureReciteModel(context, ref),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final ok = await showYqSheet<bool>(
      context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.asrDeleteConfirm, style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: YqSpace.s),
          Text(t.asrDeleteBody, style: Theme.of(c).textTheme.bodyMedium),
          const SizedBox(height: YqSpace.l),
          YqButton(label: t.delete, onPressed: () => Navigator.of(c).pop(true)),
          const SizedBox(height: YqSpace.s),
          YqButton.secondary(label: t.cancel, onPressed: () => Navigator.of(c).pop(false)),
        ],
      ),
    );
    if (ok == true) await ref.read(asrModelControllerProvider.notifier).delete();
  }
}
