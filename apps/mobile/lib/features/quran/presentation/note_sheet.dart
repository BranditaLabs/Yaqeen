import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/annotations.dart';
import '../domain/quran_data.dart';
import 'quran_providers.dart';

/// «ملاحظتي» on an ayah — a private reflection kept on the device (spec §5.11).
Future<void> showNoteSheet(BuildContext context, {required QuranData quran, required AyahRef ref}) =>
    showYqSheet<void>(context, scrollable: true, builder: (_) => _NoteSheet(quran: quran, ayah: ref));

class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({required this.quran, required this.ayah});
  final QuranData quran;
  final AyahRef ayah;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
  final _text = TextEditingController();
  bool _existing = false;

  @override
  void initState() {
    super.initState();
    ref.read(readingRepositoryProvider).annotations().then((a) {
      final n = a.notes[widget.ayah];
      if (mounted && n != null) {
        setState(() {
          _existing = true;
          _text.text = n.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(String text) async {
    await ref.read(readingRepositoryProvider).setNote(widget.ayah, text, ref.read(clockProvider)());
    ref.invalidate(annotationsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final surah = widget.quran.surah(widget.ayah.surah).nameAr;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.noteTitle, style: theme.titleLarge),
        Text('${t.quranSurahName(surah)} · ${t.quranAyahN(widget.ayah.ayah)}', style: theme.bodySmall),
        const SizedBox(height: YqSpace.m),
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          maxLength: AyahNote.maxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: t.noteHint, helperText: t.notePrivate),
        ),
        const SizedBox(height: YqSpace.s),
        YqButton(label: t.noteSave, onPressed: () => _save(_text.text)),
        if (_existing)
          TextButton(
            onPressed: () => _save(''),
            child: Text(t.noteDelete, style: const TextStyle(color: YqColors.error)),
          ),
      ],
    );
  }
}
