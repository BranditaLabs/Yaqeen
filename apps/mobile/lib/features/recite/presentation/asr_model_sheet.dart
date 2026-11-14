import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/network/resumable_download.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../content/presentation/pack_row.dart' show megabytes;
import 'asr_model_controller.dart';

/// Makes sure the recitation model is on the phone before a «تسميع» / voice «تحفيظ» entry goes on:
/// true at once when it is; otherwise the calm sheet (what it does, «يعمل دون إنترنت ولا يغادر صوتك
/// جهازك», the size, «تنزيل») and true once the download has finished while it was open. Never
/// downloads on mobile data unless the user taps that choice.
Future<bool> ensureReciteModel(BuildContext context, WidgetRef ref) async {
  if (ref.read(asrModelControllerProvider).supported == null) await ref.read(asrModelControllerProvider.notifier).refresh();
  if (!context.mounted) return false;
  final s = ref.read(asrModelControllerProvider);
  if (s.ready) return true;
  if (s.supported != true) return false;
  final ok = await showYqSheet<bool>(context, builder: (_) => const AsrModelSheet());
  return ok == true && ref.read(asrModelControllerProvider).ready;
}

/// Offered by itself once (the hifz test the first time); afterwards only an explicit tap opens it.
const asrSheetOfferedKey = 'asr.sheetOffered';

class AsrModelSheet extends ConsumerStatefulWidget {
  const AsrModelSheet({super.key});

  @override
  ConsumerState<AsrModelSheet> createState() => _AsrModelSheetState();
}

class _AsrModelSheetState extends ConsumerState<AsrModelSheet> {
  bool _metered = false;

  Future<void> _download({bool allowMetered = false}) async {
    try {
      await ref.read(asrModelControllerProvider.notifier).download(allowMetered: allowMetered);
      if (mounted && ref.read(asrModelControllerProvider).ready) Navigator.of(context).pop(true);
    } on WifiRequired {
      if (mounted) setState(() => _metered = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final s = ref.watch(asrModelControllerProvider);
    final size = megabytes(t, s.bytes);
    final progress = s.progress;
    Widget line(IconData icon, String label) => Padding(
          padding: const EdgeInsets.only(bottom: YqSpace.s),
          child: Row(
            children: [
              Icon(icon, size: 20, color: YqColors.lapis),
              const SizedBox(width: YqSpace.m),
              Expanded(child: Text(label, style: text.bodyMedium)),
            ],
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: progress == null
              ? const Icon(Icons.graphic_eq_rounded, size: 40, color: YqColors.lapis)
              : Semantics(
                  label: t.asrPreparing(YqFormat.number((progress * 100).round())),
                  child: YqRing(value: progress, size: 48, stroke: 3.4),
                ),
        ),
        const SizedBox(height: YqSpace.m),
        Text(t.asrSheetTitle, textAlign: TextAlign.center, style: text.titleLarge),
        const SizedBox(height: YqSpace.s),
        Text(t.asrSheetBody, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: YqColors.muted)),
        const SizedBox(height: YqSpace.l),
        line(Icons.lock_outline_rounded, t.asrSheetPrivacy),
        line(Icons.spellcheck_rounded, t.asrSheetWords),
        line(Icons.download_rounded, t.asrSheetSize(size)),
        if (s.failed) Text(t.asrSettingsFailed, style: text.bodySmall?.copyWith(color: YqColors.goldText)),
        const SizedBox(height: YqSpace.l),
        if (progress != null)
          Text(
            t.asrPreparing('${YqFormat.number((progress * 100).round())}%'),
            textAlign: TextAlign.center,
            style: text.labelLarge?.copyWith(color: YqColors.lapis),
          )
        else if (_metered) ...[
          Text(t.reciterWifiOnly, textAlign: TextAlign.center, style: text.bodySmall),
          const SizedBox(height: YqSpace.s),
          YqButton(label: t.asrDownloadMetered, onPressed: () => _download(allowMetered: true)),
        ] else
          YqButton(label: t.asrDownload, onPressed: _download),
        const SizedBox(height: YqSpace.s),
        YqButton.secondary(label: t.asrNotNow, onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
