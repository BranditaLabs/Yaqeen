import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/format.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/liquid_glass.dart';
import '../../../../core/widgets/yq_icon.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../listen/presentation/listen_controller.dart';
import '../../domain/passage.dart';
import '../../domain/quran_data.dart';

/// The reader follows the recitation (spec §5.11): the page with the recited ayah comes to the
/// screen. With per-ayah timings it follows every ayah; without them only a new surah moves the page
/// (to its first page). Never while a sheet is open, the page is locked, or within
/// [FollowGuard.span] of the reader turning a page by hand. In a spread it turns only when the ayah
/// has left both pages.
abstract final class FollowAudio {
  /// The page to show for [now], or null to stay. [visible]: the pages on screen (both of a spread).
  static int? target({
    required ListenState now,
    required int? previousSurah,
    required List<int> visible,
    required QuranData? quran,
    required bool blocked,
  }) {
    if (blocked || !now.playing || now.sampleOf != null || now.status != ListenStatus.ready) return null;
    final int page;
    if (now.synced && quran != null) {
      page = quran.pageOf(now.ref);
    } else {
      if (previousSurah == null || previousSurah == now.surah) return null;
      page = quran?.surah(now.surah).startPage ?? surahStartPage(now.surah);
    }
    return visible.contains(page) ? null : page;
  }

  /// Tells screen readers the page changed under them.
  static void announce(BuildContext context, int page) {
    final t = AppLocalizations.of(context);
    SemanticsService.sendAnnouncement(View.of(context), t.qsPageAnnounce(YqFormat.number(page)), Directionality.of(context));
  }
}

/// A manual look-ahead pauses following for 8 s; [onEnd] runs when the pause is over.
class FollowGuard {
  FollowGuard({this.onEnd});
  final VoidCallback? onEnd;
  static const span = Duration(seconds: 8);
  Timer? _timer;

  void hold() {
    _timer?.cancel();
    _timer = Timer(span, () => onEnd?.call());
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
  }

  bool get active => _timer?.isActive ?? false;
}

/// «عُد إلى موضع التلاوة»: back to the page being recited after looking ahead.
class BackToRecitationChip extends StatelessWidget {
  const BackToRecitationChip({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return GlassTap(
      onTap: onTap,
      semanticLabel: t.qsBackToRecitation,
      child: LiquidGlass(
        radius: YqRadii.pill,
        highlight: false,
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: YqSpace.touch - YqSpace.s * 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const YqIcon(YqIcons.listen, size: 18),
              const SizedBox(width: YqSpace.s),
              Text(t.qsBackToRecitation, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.lapis)),
            ],
          ),
        ),
      ),
    );
  }
}
