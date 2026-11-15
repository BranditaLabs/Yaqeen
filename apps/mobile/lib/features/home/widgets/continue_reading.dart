import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/quran_data.dart';
import '../../quran/presentation/quran_index_screen.dart';
import '../../quran/presentation/session/quran_entry.dart';

/// Home's «now» card on the day timeline: continue reading (or al-Kahf on Friday) with a listen
/// button. A session left open today comes first: «أكمل جلستك · ص {page}» picks it up in the reader.
class ContinueReading extends ConsumerWidget {
  const ContinueReading({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final last = ref.watch(lastReadProvider).valueOrNull;
    final s = ref.watch(settingsProvider);
    final listenOn = ref.watch(remoteConfigProvider).isOn(Flags.listen);
    final resume = ref.watch(quranResumeProvider).valueOrNull;
    if (quran == null) return const YqSkeleton(child: YqSkeletonBox(height: 92, radius: YqRadii.card));

    final today = ref.watch(prayerRepositoryProvider).today(s, ref.watch(clockProvider)());
    // Friday: suggest al-Kahf unless it is already the current reading (a suggestion, not a badge).
    final kahf = resume == null && today.weekday == DateTime.friday && last?.surah != 18;
    final page = resume != null ? sessionPage(resume) : (kahf ? quran.surah(18).startPage : (last?.page ?? 1));
    final first = quran.firstOfPage(page);
    final surah = quran.surah(kahf ? 18 : first.surah);
    final surahPages =
        (surah.number < QuranData.surahCount ? quran.surah(surah.number + 1).startPage : QuranData.pageCount + 1) - surah.startPage;
    final progress = surahPages <= 0 ? 0.0 : ((page - surah.startPage + 1) / surahPages).clamp(0.0, 1.0);
    final surahName = surah.name(s.locale);
    final eyebrow = resume != null
        ? t.qsResume(YqFormat.number(page))
        : kahf
            ? t.homeKahfSuggestion
            : (last == null ? t.homeStartReading : t.continueReading);

    return GlassTap(
      onTap: () => context.push(resume != null ? resumeLocation(resume, mode: resume.mode) : '/quran/read/$page'),
      semanticLabel: '$eyebrow، ${t.homeReadingMeta(surahName, page, quran.juzOf(first))}',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: YqColors.navy,
          borderRadius: BorderRadius.circular(YqRadii.card),
          boxShadow: [BoxShadow(color: YqColors.ink.withValues(alpha: 0x40 / 255), blurRadius: 24, spreadRadius: -10, offset: const Offset(0, 12))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow,
                    style: text.labelSmall?.copyWith(color: YqColors.goldLight, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    surahName,
                    // The brand display face is Arabic-only; Latin names use Amiri rather than the system font.
                    style: TextStyle(
                      fontFamily: s.locale == 'ar' ? YqFonts.display : YqFonts.naskh,
                      fontFamilyFallback: YqFonts.displayFallback,
                      fontSize: 30,
                      color: YqColors.goldLight,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    t.homeReadingMeta(surahName, page, quran.juzOf(first)),
                    style: text.bodySmall?.copyWith(color: YqColors.gold200),
                  ),
                  const SizedBox(height: 8),
                  YqProgressLine(value: progress, color: YqColors.gold, track: YqColors.goldLight.withValues(alpha: 0x33 / 255)),
                ],
              ),
            ),
            if (listenOn) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: t.homeListenTo(surahName),
                child: Semantics(
                  button: true,
                  label: t.homeListenTo(surahName),
                  excludeSemantics: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => openQuranListen(context, ref, fallbackSurah: surah.number),
                    child: Container(
                      width: YqSpace.touch,
                      height: YqSpace.touch,
                      decoration: const BoxDecoration(color: YqColors.goldLight, shape: BoxShape.circle),
                      child: const Center(child: Icon(Icons.play_arrow_rounded, color: YqColors.navy)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
