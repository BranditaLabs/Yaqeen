import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/mushaf_fonts.dart';
import 'quran_providers.dart';

/// «صفحات المصحف كما في الطبعة» in the reader settings: how many printed pages are on the device,
/// «download the whole mushaf» with progress and cancel, and the font / layout credit (spec §10).
class MushafDownloadSection extends ConsumerStatefulWidget {
  const MushafDownloadSection({super.key});

  @override
  ConsumerState<MushafDownloadSection> createState() => _MushafDownloadSectionState();
}

class _MushafDownloadSectionState extends ConsumerState<MushafDownloadSection> {
  int? _onDevice;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final n = await ref.read(mushafFontsProvider).downloadedCount();
    if (mounted) setState(() => _onDevice = n);
  }

  Future<void> _start() async {
    final t = AppLocalizations.of(context);
    final fonts = ref.read(mushafFontsProvider);
    final metered = !await ref.read(connectivityProvider).isUnmetered();
    if (metered && !await ref.read(listenStoreProvider).allowMetered()) {
      if (mounted) YqToast.show(context, t.reciterWifiOnly);
      return;
    }
    await fonts.downloadAll();
    final bulk = fonts.bulk.value;
    if (mounted && (bulk?.failed ?? false)) YqToast.show(context, t.mushafDownloadFailed);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final fonts = ref.watch(mushafFontsProvider);
    return ValueListenableBuilder<MushafBulk?>(
      valueListenable: fonts.bulk,
      builder: (context, bulk, _) {
        final done = bulk?.done ?? _onDevice ?? 0;
        final all = done >= MushafFonts.pageCount;
        final running = bulk?.running ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.mushafPagesTitle, style: text.titleSmall),
            const SizedBox(height: YqSpace.xs),
            Text(t.mushafPagesHint, style: text.bodySmall),
            const SizedBox(height: YqSpace.s),
            Text(
              all ? t.mushafPagesAll : t.mushafPagesStatus(YqFormat.number(done)),
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
            if (running) ...[
              const SizedBox(height: YqSpace.s),
              YqProgressLine(value: done / MushafFonts.pageCount),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: YqButton.text(label: t.cancel, onPressed: fonts.cancelDownloadAll),
              ),
            ] else if (!all) ...[
              const SizedBox(height: YqSpace.s),
              YqButton.secondary(
                label: t.mushafDownloadAll(YqFormat.number(MushafFonts.approxTotalMb)),
                icon: const Icon(Icons.download_rounded, size: 18, color: YqColors.lapis),
                onPressed: _start,
              ),
            ],
            const SizedBox(height: YqSpace.s),
            Text(t.mushafCredit, style: text.bodySmall?.copyWith(fontSize: 11, color: YqColors.muted)),
          ],
        );
      },
    );
  }
}
