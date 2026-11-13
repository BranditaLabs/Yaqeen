import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'me_profile_controller.dart';

/// contracts `DISPLAY_NAME_MAX`.
const displayNameMax = 40;

/// Mirrors contracts `DisplayName`: URLs, control characters, bidi controls and zero-width
/// characters are refused (the server adds reserved/brand/profanity checks on top).
final _forbidden = RegExp(r'https?:|www\.|[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]', caseSensitive: false);

/// Whether [name] is a display name the server will take (1–40 characters after trimming).
bool isValidDisplayName(String name) {
  final s = name.trim();
  return s.isNotEmpty && s.length <= displayNameMax && !_forbidden.hasMatch(s);
}

/// «اسمك» — the name others see. Saved on this phone first and synced (Outbox); support can lock it.
Future<void> showEditNameSheet(BuildContext context) => showYqSheet<void>(context, scrollable: true, builder: (_) => const EditNameSheet());

class EditNameSheet extends ConsumerStatefulWidget {
  const EditNameSheet({super.key});

  @override
  ConsumerState<EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends ConsumerState<EditNameSheet> {
  late final TextEditingController _c = TextEditingController(text: ref.read(meProfileProvider).valueOrNull?.displayName ?? '');
  bool _touched = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!isValidDisplayName(_c.text)) return;
    await ref.read(meProfileProvider.notifier).setName(_c.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locked = ref.watch(meProfileProvider.select((p) => p.valueOrNull?.nameHidden ?? false));
    final valid = isValidDisplayName(_c.text);
    final showError = _touched && !valid && !locked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.pfNameTitle, style: text.titleLarge)),
        const SizedBox(height: YqSpace.l),
        if (locked) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: YqIcon(YqIcons.lock, size: 18, tone: YqIconTone.idle)),
              const SizedBox(width: YqSpace.s),
              Expanded(child: Text(t.pfNameLocked, style: text.bodyMedium?.copyWith(color: YqColors.ink, height: 1.6))),
            ],
          ),
          const SizedBox(height: YqSpace.l),
        ],
        TextField(
          controller: _c,
          enabled: !locked,
          autofocus: !locked,
          maxLength: displayNameMax,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _touched = true),
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            hintText: t.pfNameHint,
            helperText: showError ? null : t.pfNameHelper,
            errorText: showError ? t.pfNameInvalid : null,
            errorMaxLines: 3,
            filled: true,
            fillColor: YqColors.white.withValues(alpha: 0.8),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(YqRadii.chip), borderSide: const BorderSide(color: YqColors.line)),
            enabledBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(YqRadii.chip), borderSide: const BorderSide(color: YqColors.line)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YqRadii.chip),
              borderSide: const BorderSide(color: YqColors.lapis, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: YqSpace.l),
        YqButton(label: t.pfSave, onPressed: !locked && valid ? _save : null),
      ],
    );
  }
}
