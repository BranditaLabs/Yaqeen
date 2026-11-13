import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../profile/presentation/me_profile_controller.dart';
import '../data/community_repository.dart';
import '../domain/community_models.dart';
import 'community_providers.dart';
import 'community_widgets.dart';

/// Join sheets (design §6.6–6.9). Joining is always a **direct** online call; offline →
/// «تحتاج اتصالاً للانضمام»; every typed failure shows inline. Each sheet carries the required
/// attestation switch (hidden once `community.attestedAdult`), the privacy line and the terms link.

/// «انضم إلى الدوري الأسبوعي». True when joined.
Future<bool> showJoinLeagueSheet(BuildContext context) async =>
    await showYqSheet<bool>(context, scrollable: true, builder: (_) => const JoinLeagueSheet()) ?? false;

/// The level board (or the country board, [country]). True when joined.
Future<bool> showJoinBoardSheet(BuildContext context, {bool country = false}) async =>
    await showYqSheet<bool>(context, scrollable: true, builder: (_) => JoinBoardSheet(country: country)) ?? false;

/// «انضم إلى البطولة». True when joined.
Future<bool> showJoinTournamentSheet(BuildContext context, String id) async =>
    await showYqSheet<bool>(context, scrollable: true, builder: (_) => JoinTournamentSheet(id: id)) ?? false;

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    this.body,
    required this.children,
    required this.error,
    required this.busy,
    required this.canJoin,
    required this.onJoin,
  }) : joinLabel = null;

  final String title;
  final String? body;
  final List<Widget> children;
  final String? error;
  final bool busy;
  final bool canJoin;
  final VoidCallback onJoin;
  final String? joinLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(title, style: text.titleLarge)),
        if (body != null) ...[
          const SizedBox(height: YqSpace.s),
          Text(body!, style: text.bodyMedium?.copyWith(color: YqColors.muted, height: 1.6)),
        ],
        const SizedBox(height: YqSpace.m),
        ...children,
        const SizedBox(height: YqSpace.s),
        Text(t.cmPrivacy, style: const TextStyle(fontSize: 12.5, height: 1.6, color: YqColors.muted)),
        const CommunityTermsLink(),
        InlineFailure(error),
        const SizedBox(height: YqSpace.m),
        YqButton(label: joinLabel ?? t.cmJoin, loading: busy, onPressed: canJoin && !busy ? onJoin : null),
        const SizedBox(height: YqSpace.xs),
        Center(child: YqButton.text(label: t.cmNotNow, onPressed: busy ? null : () => Navigator.of(context).pop(false))),
      ],
    );
  }
}

class JoinLeagueSheet extends ConsumerStatefulWidget {
  const JoinLeagueSheet({super.key});

  @override
  ConsumerState<JoinLeagueSheet> createState() => _JoinLeagueSheetState();
}

class _JoinLeagueSheetState extends ConsumerState<JoinLeagueSheet> {
  late final TextEditingController _name;
  bool _attest = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The first name only — never the full name (design §1.3).
    _name = TextEditingController(text: ref.read(meProfileProvider).valueOrNull?.firstName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _join(bool attested) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppLocalizations.of(context);
    final r = await ref.read(meProfileProvider.notifier).join(
          CommunityUpdate(leagues: true, displayName: _name.text.trim(), attestAdult: !attested && _attest),
        );
    if (!mounted) return;
    if (r.isOk) {
      ref.invalidate(leagueProvider);
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = communityFailureText(t, r.errorOrNull!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final attested = ref.watch(meProfileProvider.select((p) => p.valueOrNull?.community.attestedAdult ?? false));
    final valid = isValidDisplayName(_name.text) && (attested || _attest);
    return _SheetScaffold(
      title: t.cmJoinLeagueTitle,
      body: t.cmJoinLeagueBody,
      error: _error,
      busy: _busy,
      canJoin: valid,
      onJoin: () => _join(attested),
      children: [
        TextField(
          controller: _name,
          maxLength: 40,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: t.cmDisplayName, counterText: ''),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (!attested) AttestSwitch(value: _attest, onChanged: (v) => setState(() => _attest = v)),
      ],
    );
  }
}

class JoinBoardSheet extends ConsumerStatefulWidget {
  const JoinBoardSheet({super.key, this.country = false});
  final bool country;

  @override
  ConsumerState<JoinBoardSheet> createState() => _JoinBoardSheetState();
}

class _JoinBoardSheetState extends ConsumerState<JoinBoardSheet> {
  bool _attest = false;
  bool _busy = false;
  String? _error;

  Future<void> _join(bool attested) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppLocalizations.of(context);
    final r = await joinBoard(ref, country: widget.country, attestAdult: !attested && _attest);
    if (!mounted) return;
    if (r == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = communityFailureText(t, r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final attested = ref.watch(meProfileProvider.select((p) => p.valueOrNull?.community.attestedAdult ?? false));
    return _SheetScaffold(
      title: widget.country ? t.cmShowMeCountry : t.cmShowMe,
      body: widget.country ? t.cmShowMeCountryBody : t.cmShowMeBody,
      error: _error,
      busy: _busy,
      canJoin: attested || _attest,
      onJoin: () => _join(attested),
      children: [
        if (!attested) AttestSwitch(value: _attest, onChanged: (v) => setState(() => _attest = v)),
      ],
    );
  }
}

/// Turns the level board (or the country board) on with a direct call. Null on success.
///
/// The country board only refines the level board and never stands alone (design §1.3), so turning
/// it on also turns the level board on — the country disclosure says so.
Future<CommunityFailure?> joinBoard(WidgetRef ref, {required bool country, bool attestAdult = false}) async {
  final on = ref.read(meProfileProvider).valueOrNull?.community.leaderboard ?? false;
  final r = await ref.read(meProfileProvider.notifier).join(
        CommunityUpdate(
          leaderboard: country && on ? null : true,
          leaderboardCountry: country ? true : null,
          attestAdult: attestAdult,
        ),
      );
  if (r.isOk) {
    ref
      ..invalidate(leaderboardProvider(LeaderboardScope.global))
      ..invalidate(leaderboardProvider(LeaderboardScope.country));
  }
  return r.errorOrNull;
}

class JoinTournamentSheet extends ConsumerStatefulWidget {
  const JoinTournamentSheet({super.key, required this.id});
  final String id;

  @override
  ConsumerState<JoinTournamentSheet> createState() => _JoinTournamentSheetState();
}

class _JoinTournamentSheetState extends ConsumerState<JoinTournamentSheet> {
  bool _ack = false;
  bool _attest = false;
  bool _busy = false;
  String? _error;

  Future<void> _join(bool attested) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppLocalizations.of(context);
    final r = await ref.read(communityRepositoryProvider).joinTournament(widget.id, attestAdult: !attested && _attest);
    if (!mounted) return;
    if (r.isOk) {
      ref
        ..invalidate(tournamentProvider(widget.id))
        ..invalidate(standingsProvider(widget.id))
        ..invalidate(tournamentsProvider);
      // The attestation (and the community consent) changed on the server.
      if (!attested) unawaited(ref.read(meProfileProvider.notifier).refresh());
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = communityFailureText(t, r.errorOrNull!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final attested = ref.watch(meProfileProvider.select((p) => p.valueOrNull?.community.attestedAdult ?? false));
    return _SheetScaffold(
      title: t.cmJoinTournament,
      error: _error,
      busy: _busy,
      canJoin: _ack && (attested || _attest),
      onJoin: () => _join(attested),
      children: [
        AttestSwitch(value: _ack, label: t.cmTournamentAck, onChanged: (v) => setState(() => _ack = v)),
        if (!attested) AttestSwitch(value: _attest, onChanged: (v) => setState(() => _attest = v)),
      ],
    );
  }
}

/// A plain confirm («مغادرة الدوري» → «غادر»). True when confirmed.
Future<bool> confirmLeave(BuildContext context, {required String title, required String body}) async {
  final t = AppLocalizations.of(context);
  return await showYqSheet<bool>(
        context,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            const SizedBox(height: YqSpace.s),
            Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: YqColors.muted, height: 1.6)),
            const SizedBox(height: YqSpace.xl),
            YqButton(label: t.cmLeave, onPressed: () => Navigator.of(context).pop(true)),
            const SizedBox(height: YqSpace.xs),
            Center(child: YqButton.text(label: t.cancel, onPressed: () => Navigator.of(context).pop(false))),
          ],
        ),
      ) ??
      false;
}
