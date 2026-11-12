import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format.dart';
import '../../../core/text/arabic.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/quran_data.dart';

/// Where the jump sheet sends the reader: a page, and the ayah to light when one was picked.
typedef JumpTarget = ({int page, AyahRef? ayah});

enum _JumpTab { surah, juz, page, ayah }

/// «انتقل إلى» (spec §5.11): surah (filterable), juz, page number, or surah + ayah — one sheet,
/// one tap. Opens from the reader's title.
Future<JumpTarget?> showJumpSheet(BuildContext context, {required QuranData quran, required int currentPage, required String locale}) =>
    showYqSheet<JumpTarget>(context, scrollable: true, builder: (_) => _JumpSheet(quran: quran, currentPage: currentPage, locale: locale));

class _JumpSheet extends StatefulWidget {
  const _JumpSheet({required this.quran, required this.currentPage, required this.locale});
  final QuranData quran;
  final int currentPage;
  final String locale;

  @override
  State<_JumpSheet> createState() => _JumpSheetState();
}

class _JumpSheetState extends State<_JumpSheet> {
  _JumpTab _tab = _JumpTab.surah;
  final _filter = TextEditingController();
  late final _page = TextEditingController(text: '${widget.currentPage}');
  late int _surah = widget.quran.firstOfPage(widget.currentPage).surah;
  final _ayah = TextEditingController(text: '1');

  @override
  void dispose() {
    _filter.dispose();
    _page.dispose();
    _ayah.dispose();
    super.dispose();
  }

  void _done(int page, [AyahRef? ayah]) => Navigator.of(context).pop((page: page.clamp(1, QuranData.pageCount), ayah: ayah));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final q = widget.quran;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.jumpTitle, style: text.titleLarge),
        const SizedBox(height: YqSpace.m),
        YqSegmented<_JumpTab>(
          segments: [(_JumpTab.surah, t.jumpSurah), (_JumpTab.juz, t.jumpJuz), (_JumpTab.page, t.jumpPage), (_JumpTab.ayah, t.jumpAyah)],
          selected: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: YqSpace.m),
        switch (_tab) {
          _JumpTab.surah => _surahList(t, q),
          _JumpTab.juz => Wrap(
              spacing: YqSpace.s,
              runSpacing: YqSpace.s,
              alignment: WrapAlignment.center,
              children: [
                for (var j = 1; j <= 30; j++)
                  YqChip(
                    label: YqFormat.number(j),
                    selected: q.juzOf(q.firstOfPage(widget.currentPage)) == j,
                    semanticLabel: t.quranJuz(j),
                    onTap: () => _done(q.juzStartPage(j)),
                  ),
              ],
            ),
          _JumpTab.page => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _page,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  textAlign: TextAlign.center,
                  style: YqText.numberSmall.copyWith(fontSize: 28, color: YqColors.ink),
                  decoration: InputDecoration(labelText: t.jumpPageField),
                  onSubmitted: (v) => _done(int.tryParse(v) ?? widget.currentPage),
                ),
                const SizedBox(height: YqSpace.m),
                YqButton(label: t.jumpGo, onPressed: () => _done(int.tryParse(_page.text) ?? widget.currentPage)),
              ],
            ),
          _JumpTab.ayah => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _surah,
                  isExpanded: true,
                  items: [
                    for (final s in q.surahs)
                      DropdownMenuItem(value: s.number, child: Text('${YqFormat.number(s.number)} · ${s.name(widget.locale)}')),
                  ],
                  onChanged: (v) => setState(() => _surah = v ?? _surah),
                ),
                const SizedBox(height: YqSpace.m),
                TextField(
                  controller: _ayah,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  textAlign: TextAlign.center,
                  style: YqText.numberSmall.copyWith(fontSize: 24, color: YqColors.ink),
                  decoration: InputDecoration(
                    labelText: t.jumpAyahField,
                    helperText: t.jumpAyahOf(YqFormat.number(q.surah(_surah).ayahCount)),
                  ),
                ),
                const SizedBox(height: YqSpace.m),
                YqButton(
                  label: t.jumpGo,
                  onPressed: () {
                    final a = (int.tryParse(_ayah.text) ?? 1).clamp(1, q.surah(_surah).ayahCount);
                    final ref = AyahRef(_surah, a);
                    _done(q.pageOf(ref), ref);
                  },
                ),
              ],
            ),
        },
      ],
    );
  }

  Widget _surahList(AppLocalizations t, QuranData q) {
    final f = ArabicText.normalize(_filter.text).toLowerCase();
    final list = [
      for (final s in q.surahs)
        if (f.isEmpty || ArabicText.normalize(s.nameAr).contains(f) || s.nameEn.toLowerCase().contains(f) || '${s.number}' == f) s,
    ];
    final current = q.firstOfPage(widget.currentPage).surah;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _filter,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: t.jumpFilter, prefixIcon: const Icon(Icons.search_rounded)),
        ),
        const SizedBox(height: YqSpace.s),
        SizedBox(
          height: 320,
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              return YqListRow(
                dense: true,
                leading: SizedBox(
                  width: 32,
                  child: Text(YqFormat.number(s.number), textAlign: TextAlign.center, style: YqText.numberSmall),
                ),
                title: s.name(widget.locale),
                titleColor: s.number == current ? YqColors.lapis : null,
                subtitle: t.quranPageN(s.startPage),
                onTap: () => _done(s.startPage),
              );
            },
          ),
        ),
      ],
    );
  }
}
