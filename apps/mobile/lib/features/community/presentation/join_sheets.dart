import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../profile/domain/me_profile.dart';
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

/// The server refuses a join without a shown name (`name_required`, design §3.3) — e.g. after an
/// Apple sign-in that shared none. Then every join sheet asks for «الاسم الظاهر», and the direct
/// join paths go through the sheet. A name hidden by support is never asked for.
bool needsDisplayName(MeProfile? p) => p != null && !p.nameHidden && (p.displayName?.trim().isEmpty ?? true);

/// The first name to prefill: the profile's, else the signed-in account's — never the full name.
String firstNameFor(WidgetRef ref) {
  final p = ref.read(meProfileProvider).valueOrNull;
  final own = p?.firstName ?? '';
  if (own.isNotEmpty) return own;
  return MeProfile.firstNameOf(ref.read(sessionProvider).displayName);
}

/// «الاسم الظاهر», 1–40.
class DisplayNameField extends StatelessWidget {
  const DisplayNameField({super.key, required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLength: 40,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: AppLocalizations.of(context).cmDisplayName, counterText: ''),
        onChanged: onChanged,
      );
}

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
    _name = TextEditingController(text: firstNameFor(ref));
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
    final r = await joinCommunity(
      ref,
      CommunityUpdate(leagues: true, displayName: _nameToSend(), attestAdult: !attested && _attest),
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

  /// The name to send: none while support hides it (the server answers `name_locked` to any
  /// name, and the person may still join as «عضو يقين»), none when it is already the shown name.
  String? _nameToSend() {
    final p = ref.read(meProfileProvider).valueOrNull;
    if (p?.nameHidden ?? false) return null;
    final name = _name.text.trim();
    return name == p?.displayName?.trim() ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final attested = ref.watch(meProfileProvider.select((p) => p.valueOrNull?.community.attestedAdult ?? false));
    final nameHidden = ref.watch(meProfileProvider.select((p) => p.valueOrNull?.nameHidden ?? false));
    final valid = (nameHidden || isValidDisplayName(_name.text)) && (attested || _attest);
    return _SheetScaffold(
      title: t.cmJoinLeagueTitle,
      body: t.cmJoinLeagueBody,
      error: _error,
      busy: _busy,
      canJoin: valid,
      onJoin: () => _join(attested),
      children: [
        if (nameHidden)
          // Read-only: support hid the name, so it cannot be changed here (design §1.3).
          InputDecorator(
            decoration: InputDecoration(labelText: t.cmDisplayName, enabled: false),
            child: Text(t.avHiddenName, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: YqColors.muted)),
          )
        else
          DisplayNameField(controller: _name, onChanged: (_) => setState(() => _error = null)),
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
  late final TextEditingController _name;
  bool _attest = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: firstNameFor(ref));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _join(bool attested, bool askName) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppLocalizations.of(context);
    final r = await joinBoard(
      ref,
      country: widget.country,
      attestAdult: !attested && _attest,
      displayName: askName ? _name.text.trim() : null,
    );
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
    final askName = ref.watch(meProfileProvider.select((p) => needsDisplayName(p.valueOrNull)));
    return _SheetScaffold(
      title: widget.country ? t.cmShowMeCountry : t.cmShowMe,
      body: widget.country ? t.cmShowMeCountryBody : t.cmShowMeBody,
      error: _error,
      busy: _busy,
      canJoin: (attested || _attest) && (!askName || isValidDisplayName(_name.text)),
      onJoin: () => _join(attested, askName),
      children: [
        if (askName) DisplayNameField(controller: _name, onChanged: (_) => setState(() => _error = null)),
        if (!attested) AttestSwitch(value: _attest, onChanged: (v) => setState(() => _attest = v)),
      ],
    );
  }
}

/// Turns the level board (or the country board) on with a direct call. Null on success.
///
/// The country board only refines the level board (design §1.3). Turning it on never publishes the
/// person on the worldwide board as a side effect: it is offered only while the level board is
/// already on (the screens disable it otherwise), and this refuses without a call when it is not —
/// the server would otherwise turn the level board on with it.
Future<CommunityFailure?> joinBoard(WidgetRef ref, {required bool country, bool attestAdult = false, String? displayName}) async {
  final on = ref.read(meProfileProvider).valueOrNull?.community.leaderboard ?? false;
  if (country && !on) return CommunityFailure.unknown;
  final r = await joinCommunity(
    ref,
    CommunityUpdate(
      leaderboard: country ? null : true,
      leaderboardCountry: country ? true : null,
      displayName: displayName,
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
  late final TextEditingController _name;
  bool _ack = false;
  bool _attest = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: firstNameFor(ref));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _join(bool attested, bool askName) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final t = AppLocalizations.of(context);
    // No shown name yet: set it first (a direct name-only PUT /v1/me/community, which turns
    // nothing on), or the tournament join answers `name_required`.
    if (askName) {
      final named = await ref.read(meProfileProvider.notifier).join(CommunityUpdate(displayName: _name.text.trim()));
      if (!mounted) return;
      if (!named.isOk) {
        setState(() {
          _busy = false;
          _error = communityFailureText(t, named.errorOrNull!);
        });
        return;
      }
    }
    final r = await ref.read(communityRepositoryProvider).joinTournament(widget.id, attestAdult: !attested && _attest);
    if (!mounted) return;
    if (r.isOk) {
      ref.read(leftTournamentsProvider.notifier).remove(widget.id);
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
    final askName = ref.watch(meProfileProvider.select((p) => needsDisplayName(p.valueOrNull)));
    return _SheetScaffold(
      title: t.cmJoinTournament,
      error: _error,
      busy: _busy,
      canJoin: _ack && (attested || _attest) && (!askName || isValidDisplayName(_name.text)),
      onJoin: () => _join(attested, askName),
      children: [
        if (askName) DisplayNameField(controller: _name, onChanged: (_) => setState(() => _error = null)),
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
