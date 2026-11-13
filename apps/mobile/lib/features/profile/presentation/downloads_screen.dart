import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../content/presentation/pack_row.dart';
import '../../listen/domain/audio_models.dart';
import 'profile_providers.dart';

/// «التنزيلات دون اتصال» (`/profile/downloads`) — storage per reciter; deleting reclaims it
/// (spec §5.14 acceptance).
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  Map<String, int>? _sizes;
  int _packBytes = 0;

  /// The reciters with audio on this phone, read once per [_load] with the sizes (a rebuild never
  /// re-reads them, so the list never flashes back to its skeleton).
  List<Reciter> _reciters = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = ref.read(audioDownloadsProvider);
    final reciters = await ref.read(reciterRepositoryProvider).cached();
    final sizes = <String, int>{};
    for (final r in reciters) {
      final b = await d.bytesOnDisk(r.id);
      if (b > 0) sizes[r.id] = b;
    }
    final packBytes = await ref.read(packRepositoryProvider).bytesOnDisk();
    if (mounted) {
      setState(() {
        _sizes = sizes;
        _reciters = [
          for (final r in reciters)
            if (sizes.containsKey(r.id)) r,
        ];
        _packBytes = packBytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final total = _sizes?.values.fold<int>(0, (a, b) => a + b) ?? 0;
    return Scaffold(
      backgroundColor: YqColors.porcelain,
      body: YqCanvas(
        stage: YqStage(
          compact: true,
          child: YqStageBar(back: true, title: t.profileDownloads, subtitle: t.downloadsUsed(megabytes(t, total + _packBytes))),
        ),
        children: [
          ...switch (ref.watch(packsCatalogueProvider).valueOrNull) {
            final packs? when packs.isNotEmpty => [
                Text(t.packsTitle, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: YqSpace.s),
                LiquidGlass(
                  padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
                  child: Column(
                    children: [
                      for (final p in packs)
                        PackRow(
                          pack: p,
                          onRemove: () async {
                            await ref.read(packRepositoryProvider).remove(p.id);
                            ref.invalidate(installedPacksProvider);
                            ref.invalidate(tafsirRepositoryProvider);
                            ref.invalidate(downloadsBytesProvider);
                            await _load();
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: YqSpace.l),
                Text(t.downloadsAudio, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: YqSpace.s),
              ],
            _ => const <Widget>[],
          },
          if (_sizes == null)
            const YqSkeleton(child: YqSkeletonRows(rows: 2, leading: 40))
          else if (_sizes!.isEmpty)
            LiquidGlass(child: YqEmptyState(icon: YqIcons.download, title: t.downloadsNone))
          else
            LiquidGlass(
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.xs),
              child: Column(
                children: [
                  for (final r in _reciters)
                    YqListRow(
                      title: r.name(locale),
                      subtitle: megabytes(t, _sizes![r.id]!),
                      trailing: TextButton(
                        onPressed: () async {
                          await ref.read(audioDownloadsProvider).delete(r.id);
                          ref.invalidate(downloadsBytesProvider);
                          await _load();
                        },
                        child: Text(t.delete),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
