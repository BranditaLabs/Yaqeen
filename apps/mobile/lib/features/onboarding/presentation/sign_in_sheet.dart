import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/auth_repository.dart';
import 'session_controller.dart';

/// «سجّل الدخول لتحفظ نقاطك» (spec §5.7, §5.24): a guest links to Google/Apple keeping their
/// points; someone without a session signs in. Returns true when an account is ready.
Future<bool> showSignInSheet(BuildContext context, {String? title}) async =>
    await showYqSheet<bool>(context, builder: (_) => _SignInSheet(title: title)) ?? false;

class _SignInSheet extends ConsumerStatefulWidget {
  const _SignInSheet({this.title});
  final String? title;

  @override
  ConsumerState<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<_SignInSheet> {
  SignInProvider? _busy;

  Future<void> _go(SignInProvider p) async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = p);
    final session = ref.read(sessionProvider.notifier);
    final outcome = ref.read(sessionProvider).isGuest ? await session.link(p) : await session.signInWith(p);
    if (!mounted) return;
    setState(() => _busy = null);
    switch (outcome) {
      case SignInOutcome.signedIn:
        Navigator.of(context).pop(true);
      case SignInOutcome.cancelled:
        break;
      case SignInOutcome.offline:
        YqToast.show(context, t.welcomeOffline);
      case SignInOutcome.failed:
        YqToast.show(context, t.welcomeError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final busy = _busy != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title ?? t.signInToKeep, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: YqSpace.l),
        YqButton.secondary(
          label: t.welcomeGoogle,
          loading: _busy == SignInProvider.google,
          onPressed: busy ? null : () => _go(SignInProvider.google),
        ),
        const SizedBox(height: YqSpace.s),
        // Apple on iOS always (App Store 4.8) and on Android too (spec §5.3).
        YqButton(label: t.welcomeApple, loading: _busy == SignInProvider.apple, onPressed: busy ? null : () => _go(SignInProvider.apple)),
        const SizedBox(height: YqSpace.s),
        YqButton.text(label: t.later, onPressed: busy ? null : () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
