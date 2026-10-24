import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/network/resumable_download.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/pack_repository.dart';
import '../domain/content_pack.dart';

final packsCatalogueProvider = FutureProvider.autoDispose((ref) => ref.watch(packRepositoryProvider).catalogue());
final installedPacksProvider = FutureProvider.autoDispose((ref) => ref.watch(packRepositoryProvider).installed());

String megabytes(AppLocalizations t, int bytes) => t.megabytes((bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0));

/// One downloadable pack: install with progress (Wi-Fi only unless allowed), ✓ when verified.
class PackRow extends ConsumerStatefulWidget {
  const PackRow({super.key, required this.pack, this.onRemove});
  final ContentPack pack;

  /// Shown when installed (Profile › Downloads); onboarding has no delete.
  final VoidCallback? onRemove;

  @override
  ConsumerState<PackRow> createState() => _PackRowState();
}

class _PackRowState extends ConsumerState<PackRow> {
  double? _progress;
  CancelToken? _cancel;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _install() async {
    final t = AppLocalizations.of(context);
    final token = _cancel = CancelToken();
    setState(() => _progress = 0);
    try {
      await ref.read(packRepositoryProvider).install(
        widget.pack,
        cancel: token,
        allowMetered: await ref.read(listenStoreProvider).allowMetered(),
        onProgress: (got, total) {
          final size = total ?? widget.pack.sizeBytes;
          if (mounted && size > 0) setState(() => _progress = got / size);
        },
      );
      ref.invalidate(tafsirRepositoryProvider);
      ref.invalidate(installedPacksProvider);
    } on WifiRequired {
      if (mounted) YqToast.show(context, t.reciterWifiOnly);
    } on PackChecksumMismatch {
      if (mounted) YqToast.show(context, t.packChecksumFailed);
    } on DownloadCancelled {
      // partial file kept; the next tap resumes
    } on Exception {
      if (mounted) YqToast.show(context, t.errorGeneric);
    } finally {
      _cancel = null;
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final installed = (ref.watch(installedPacksProvider).valueOrNull ?? const {})[widget.pack.id] != null;
    final busy = _progress != null;
    return YqListRow(
      dense: true,
      title: widget.pack.title(locale),
      subtitle: busy ? t.packInstalling : (installed ? t.packInstalled : t.packInstall(megabytes(t, widget.pack.sizeBytes))),
      trailing: busy
          ? SizedBox.square(dimension: 22, child: CircularProgressIndicator(value: _progress, strokeWidth: 2.4, color: YqColors.lapis))
          : installed
              ? (widget.onRemove == null
                  ? const Icon(Icons.check_circle_rounded, color: YqColors.success)
                  : TextButton(onPressed: widget.onRemove, child: Text(t.delete)))
              : IconButton(
                  tooltip: t.packInstall(megabytes(t, widget.pack.sizeBytes)),
                  onPressed: _install,
                  icon: const Icon(Icons.download_rounded, color: YqColors.lapis),
                ),
      onTap: busy || installed ? null : _install,
    );
  }
}
