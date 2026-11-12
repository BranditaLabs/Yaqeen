import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/ayah_search.dart';
import '../domain/quran_data.dart';

/// The full-text index, built once (off the UI thread) the first time someone searches.
final ayahSearchIndexProvider = FutureProvider<AyahSearchIndex>((ref) async {
  final q = await ref.watch(quranDataProvider.future);
  return AyahSearchIndex.build(q);
});

/// «في الآيات · N نتيجة»: matching ayat with the match lit in the original text; tap opens the
/// reader on that ayah. Shows [pageSize] at a time.
class AyahResults extends ConsumerStatefulWidget {
  const AyahResults({super.key, required this.quran, required this.query, required this.onOpen});
  final QuranData quran;
  final String query;
  final void Function(AyahRef ref, int page) onOpen;

  static const pageSize = 30;

  @override
  ConsumerState<AyahResults> createState() => _AyahResultsState();
}

class _AyahResultsState extends ConsumerState<AyahResults> {
  int _shown = AyahResults.pageSize;

  @override
  void didUpdateWidget(AyahResults old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _shown = AyahResults.pageSize;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (AyahSearchIndex.terms(widget.query).isEmpty) return const SizedBox.shrink();
    final index = ref.watch(ayahSearchIndexProvider);
    return index.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
        child: Text(t.quranSearching, textAlign: TextAlign.center, style: const TextStyle(color: YqColors.muted)),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (ix) {
        final r = ix.search(widget.query, limit: _shown);
        if (r.total == 0) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: YqSpace.l, bottom: YqSpace.s),
              child: Semantics(header: true, child: Text(t.quranInAyat(r.total), style: Theme.of(context).textTheme.titleSmall)),
            ),
            for (final m in r.matches) ...[
              _AyahResultCard(quran: widget.quran, match: m, onTap: () => widget.onOpen(m.ref, m.page)),
              const SizedBox(height: YqSpace.s),
            ],
            if (r.total > r.matches.length)
              TextButton(onPressed: () => setState(() => _shown += AyahResults.pageSize), child: Text(t.quranShowMore)),
          ],
        );
      },
    );
  }
}

class _AyahResultCard extends StatelessWidget {
  const _AyahResultCard({required this.quran, required this.match, required this.onTap});
  final QuranData quran;
  final AyahMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final surah = quran.surah(match.ref.surah);
    final text = quran.text(match.ref);
    final spans = <TextSpan>[];
    var at = 0;
    for (final (s, e) in match.spans) {
      if (s > at) spans.add(TextSpan(text: text.substring(at, s)));
      spans.add(
        TextSpan(
          text: text.substring(s, e),
          style: const TextStyle(color: YqColors.goldDeep, backgroundColor: Color(0x66E9D49E)),
        ),
      );
      at = e;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    final label = t.quranAyahResultA11y(surah.nameAr, YqFormat.number(match.ref.ayah), YqFormat.number(match.page));
    return GlassTap(
      onTap: onTap,
      semanticLabel: label,
      child: LiquidGlass(
        padding: const EdgeInsets.fromLTRB(YqSpace.l, YqSpace.m, YqSpace.l, YqSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.quranSurahName(surah.nameAr)} · ${t.quranAyahN(match.ref.ayah)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(t.quranPageN(match.page), style: YqText.numberSmall.copyWith(color: YqColors.muted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: YqSpace.xs),
            ExcludeSemantics(
              child: MediaQuery.withNoTextScaling(
                child: Text.rich(
                  TextSpan(children: spans),
                  textDirection: TextDirection.rtl,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: YqText.quran(size: 19, height: 1.9, color: YqColors.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
