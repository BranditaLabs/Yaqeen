import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'profile_providers.dart';

/// Says «لم يُقبل الاسم، فأعدناه كما كان.» whenever a queued name is refused on replay (design §6.4).
/// It sits in the app shell, so the revert is announced on every tab — also for a name set in the
/// onboarding profile step or on another device screen — and keeps [nameRevertsProvider] listening
/// for as long as the shell is up, not only while the Profile tab is built.
class NameRevertToaster extends ConsumerWidget {
  const NameRevertToaster({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(nameRevertsProvider, (before, now) {
      if (now > (before ?? 0)) YqToast.show(context, AppLocalizations.of(context).pfNameReverted);
    });
    return child;
  }
}
