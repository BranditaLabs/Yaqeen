import 'package:flutter/material.dart';

import '../../../../core/format.dart';
import '../../../../core/theme/tokens.dart';
import '../../../../core/widgets/controls.dart';
import '../../../../core/widgets/yq_button.dart';
import '../../../../core/widgets/yq_states.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// A rough reading pace for the plan line (a printed page read aloud at a calm pace).
const minutesPerPage = 2;

/// «ابدأ وردك»: «{pages} صفحات من ص {page} · نحو {minutes} د», «مع التلاوة» (when listening is
/// offered), then the button. Returns the choice, or null when dismissed.
Future<({bool audio})?> showSessionStartSheet(BuildContext context, {required int pages, required int page, required bool listenOn}) =>
    showYqSheet<({bool audio})>(context, builder: (_) => SessionStartSheet(pages: pages, page: page, listenOn: listenOn));

class SessionStartSheet extends StatefulWidget {
  const SessionStartSheet({super.key, required this.pages, required this.page, required this.listenOn});
  final int pages;
  final int page;
  final bool listenOn;

  @override
  State<SessionStartSheet> createState() => _SessionStartSheetState();
}

class _SessionStartSheetState extends State<SessionStartSheet> {
  bool _audio = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.qsStartWird, style: text.titleLarge),
        const SizedBox(height: YqSpace.xs),
        Text(
          t.qsWirdPlan(
            YqFormat.number(widget.pages),
            YqFormat.number(widget.page),
            YqFormat.number(widget.pages * minutesPerPage),
          ),
          style: text.bodyMedium?.copyWith(color: YqColors.muted),
        ),
        if (widget.listenOn) ...[
          const SizedBox(height: YqSpace.m),
          Row(
            children: [
              Expanded(child: Text(t.qsWithAudio, style: text.titleSmall)),
              YqSwitch(label: t.qsWithAudio, value: _audio, onChanged: (v) => setState(() => _audio = v)),
            ],
          ),
        ],
        const SizedBox(height: YqSpace.l),
        YqButton(label: t.qsStartWird, onPressed: () => Navigator.of(context).pop((audio: _audio))),
      ],
    );
  }
}
