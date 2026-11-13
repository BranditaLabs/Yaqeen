import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'community_providers.dart';
import 'community_widgets.dart';

/// Long-press on another person's row (design §6.10): «إبلاغ عن الاسم أو الصورة» with three
/// reasons, then «حظر {name}». A block hides the person here at once (both ways on the server).
Future<void> showReportSheet(BuildContext context, PublicCompetitor competitor) async {
  if (competitor.me) return;
  await showYqSheet<void>(context, builder: (_) => ReportSheet(competitor: competitor));
}

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({super.key, required this.competitor});
  final PublicCompetitor competitor;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  bool _busy = false;

  Future<void> _report(ReportReason reason) async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    final r = await ref.read(communityRepositoryProvider).report(widget.competitor.handle, reason);
    if (!mounted) return;
    final message = switch (r.errorOrNull) {
      null => t.cmReportThanks,
      CommunityFailure.rateLimited => t.cmReportLimit,
      _ => t.errorGeneric,
    };
    YqToast.show(context, message);
    Navigator.of(context).pop();
  }

  Future<void> _block() async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = AppLocalizations.of(context);
    final handle = widget.competitor.handle;
    final hidden = ref.read(hiddenHandlesProvider.notifier)..hide(handle);
    final r = await ref.read(communityRepositoryProvider).block(handle);
    if (!mounted) return;
    if (r.isOk) {
      ref.invalidate(blocksProvider);
      YqToast.show(context, t.cmBlockedToast);
    } else {
      hidden.unhide(handle);
      YqToast.show(context, t.errorGeneric);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final name = competitorName(widget.competitor, t);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.cmReportTitle, style: text.titleLarge)),
        const SizedBox(height: YqSpace.m),
        YqListRow(title: t.cmReportName, onTap: _busy ? null : () => _report(ReportReason.name)),
        const YqDivider(),
        YqListRow(title: t.cmReportPhoto, onTap: _busy ? null : () => _report(ReportReason.photo)),
        const YqDivider(),
        YqListRow(title: t.cmReportOther, onTap: _busy ? null : () => _report(ReportReason.other)),
        const SizedBox(height: YqSpace.l),
        YqListRow(
          leading: const YqIcon(YqIcons.block, size: 22, tone: YqIconTone.idle),
          title: t.cmBlockUser(name),
          subtitle: t.cmBlockBody,
          onTap: _busy ? null : _block,
          trailing: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
