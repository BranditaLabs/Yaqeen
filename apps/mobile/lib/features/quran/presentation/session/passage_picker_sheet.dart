import 'package:flutter/material.dart';

import '../../../../core/format.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_states.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/passage.dart';
import '../../domain/quran_data.dart';

/// `PassagePickerSheet` «اختر المقطع»: the ayat of one surah to memorise or recite, from–to.
Future<Passage?> showPassagePicker(BuildContext context, {required QuranData quran, required Passage initial}) =>
    showYqSheet<Passage>(context, builder: (_) => PassagePickerSheet(quran: quran, initial: initial));

class PassagePickerSheet extends StatefulWidget {
  const PassagePickerSheet({super.key, required this.quran, required this.initial});
  final QuranData quran;
  final Passage initial;

  @override
  State<PassagePickerSheet> createState() => _PassagePickerSheetState();
}

class _PassagePickerSheetState extends State<PassagePickerSheet> {
  late RangeValues _range = RangeValues(widget.initial.from.toDouble(), widget.initial.to.toDouble());

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final surah = widget.quran.surah(widget.initial.surah);
    final n = surah.ayahCount;
    final from = _range.start.round(), to = _range.end.round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.qsPassagePicker, style: text.titleLarge),
        const SizedBox(height: YqSpace.xs),
        Text(t.quranSurahName(surah.nameAr), style: text.bodySmall),
        const SizedBox(height: YqSpace.l),
        Text(t.listenRepeatRangeLabel(from, to), style: text.bodyMedium),
        if (n > 1)
          RangeSlider(
            min: 1,
            max: n.toDouble(),
            divisions: n - 1,
            values: _range,
            labels: RangeLabels(YqFormat.number(from), YqFormat.number(to)),
            activeColor: YqColors.lapis,
            inactiveColor: YqColors.line,
            onChanged: (v) => setState(() => _range = v),
          ),
        const SizedBox(height: YqSpace.m),
        YqButton(label: t.qsConfirm, onPressed: () => Navigator.of(context).pop(Passage(surah.number, from, to))),
      ],
    );
  }
}
