import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/config_controller.dart';
import '../../../../core/config/remote_config.dart';
import '../../../../core/format.dart';
import '../../../../core/settings/settings_controller.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/yq_layout.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/passage.dart';
import '../../domain/quran_data.dart';
import '../mushaf_page.dart' show MemoriseMode;
import 'quran_session_controller.dart';

/// Repetitions that make a passage «تكرار ×10».
const memoriseRepeatGoal = 10;

/// «تحفيظ» over the page: hide whole ayat or every other word, show / hide all, the passage being
/// memorised (tap to choose another), the «كرّرت» counter and «استماع ×3».
class MemoriseStrip extends ConsumerWidget {
  const MemoriseStrip({
    super.key,
    required this.quran,
    required this.passage,
    required this.onShowAll,
    required this.onPickPassage,
    required this.onListen3,
  });

  final QuranData quran;

  /// What is being memorised (the chosen passage, or the page's).
  final Passage passage;
  final VoidCallback onShowAll;
  final VoidCallback onPickPassage;
  final VoidCallback onListen3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final layers = ref.watch(quranSessionControllerProvider);
    final c = ref.read(quranSessionControllerProvider.notifier);
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final listenOn = ref.watch(remoteConfigProvider).isOn(Flags.listen);
    final repeats = layers.repeats;
    final met = repeats >= memoriseRepeatGoal;
    final name = quran.surah(passage.surah).name(locale);
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsetsDirectional.only(end: YqSpace.s),
          child: YqChip(label: label, selected: on, onTap: onTap),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              chip(t.qsAyat, layers.memorise == MemoriseMode.ayat, () => c.setMemorise(MemoriseMode.ayat)),
              chip(t.qsWordByWord, layers.memorise == MemoriseMode.words, () => c.setMemorise(MemoriseMode.words)),
              TextButton(onPressed: onShowAll, child: Text(t.qsShowAll)),
              TextButton(onPressed: c.hideAll, child: Text(t.qsHideAll)),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: '${t.qsPassagePicker}: ${t.hifzRange(name, passage.from, passage.to)}',
                excludeSemantics: true,
                onTap: onPickPassage,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPickPassage,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: YqSpace.touch),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        t.hifzRange(name, passage.from, passage.to),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: YqColors.lapis),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // «كرّرت ×n / 10»: a tap per repetition, a firmer tick when the ten are done.
            Semantics(
              button: true,
              label: '${t.qsRepeated} ${t.qsRoundOf(YqFormat.number(repeats), YqFormat.number(memoriseRepeatGoal))}',
              excludeSemantics: true,
              child: TextButton(
                onPressed: () {
                  c.countRepeat();
                  repeats + 1 == memoriseRepeatGoal ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
                },
                child: Text(
                  '${t.qsRepeated} ${t.qsRoundOf(YqFormat.number(repeats), YqFormat.number(memoriseRepeatGoal))}',
                  // Gold only once the goal is met.
                  style: TextStyle(color: met ? YqColors.goldText : YqColors.lapis, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (listenOn) TextButton(onPressed: onListen3, child: Text(t.qsListenTimes(YqFormat.number(3)))),
          ],
        ),
      ],
    );
  }
}
