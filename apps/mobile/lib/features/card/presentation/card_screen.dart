import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import '../../../core/platform/nfc_writer.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/widgets/ambient_background.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_orb.dart';
import '../../../core/widgets/yq_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../rewards/domain/reward.dart';
import '../domain/public_card.dart';

final myCardProvider = FutureProvider.autoDispose((ref) => ref.watch(cardRepositoryProvider).mine());

String socialLabel(AppLocalizations t, SocialKind k) => switch (k) {
      SocialKind.instagram => t.socialInstagram,
      SocialKind.x => t.socialX,
      SocialKind.tiktok => t.socialTiktok,
      SocialKind.facebook => t.socialFacebook,
      SocialKind.youtube => t.socialYoutube,
      SocialKind.snapchat => t.socialSnapchat,
      SocialKind.linkedin => t.socialLinkedin,
      SocialKind.whatsapp => t.socialWhatsapp,
      SocialKind.website => t.socialWebsite,
    };

/// A monogram tile per platform (no third-party logos in the app).
String socialMono(SocialKind k) => switch (k) {
      SocialKind.instagram => 'IG',
      SocialKind.x => 'X',
      SocialKind.tiktok => 'TT',
      SocialKind.facebook => 'f',
      SocialKind.youtube => '▶',
      SocialKind.snapchat => 'SC',
      SocialKind.linkedin => 'in',
      SocialKind.whatsapp => 'WA',
      SocialKind.website => '↗',
    };

/// «بطاقة يقين» — the user's public card for NFC tags and QR codes (opt-in, no worship detail).
///
/// The stage is a live preview of the card in its chosen look; the orbs write it to a tag, show
/// its QR and count its opens; below, the card is edited: identity, links, what visitors may see
/// and the look. Nothing is public until it is published and saved.
class CardScreen extends ConsumerStatefulWidget {
  const CardScreen({super.key});

  @override
  ConsumerState<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends ConsumerState<CardScreen> {
  PublicCard? _saved;
  PublicCard? _draft;
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  HandleProblem? _handleProblem;
  bool? _handleFree;
  Timer? _check;
  bool _saving = false;

  @override
  void dispose() {
    _check?.cancel();
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _adopt(PublicCard c) {
    _saved = c;
    _draft = c;
    _name.text = c.displayName;
    _handle.text = c.handle;
    _bio.text = c.bio;
    _handleProblem = null;
    _handleFree = true;
  }

  void _edit(PublicCard Function(PublicCard d) f) => setState(() => _draft = f(_draft!));

  void _onHandle(String v) {
    _edit((d) => d.copyWith(handle: v.trim().toLowerCase()));
    final problem = handleProblemOf(v);
    setState(() {
      _handleProblem = problem;
      _handleFree = null;
    });
    _check?.cancel();
    if (problem != null) return;
    if (v.trim().toLowerCase() == _saved?.handle) {
      setState(() => _handleFree = true);
      return;
    }
    _check = Timer(const Duration(milliseconds: 450), () async {
      try {
        final free = await ref.read(cardRepositoryProvider).available(v);
        if (mounted && _draft?.handle == v.trim().toLowerCase()) setState(() => _handleFree = free);
      } on Exception {
        // offline: the save will tell
      }
    });
  }

  bool get _valid =>
      _draft != null &&
      _handleProblem == null &&
      _handleFree != false &&
      _draft!.displayName.trim().isNotEmpty &&
      _draft!.bio.length <= PublicCard.maxBio;

  bool get _dirty => _draft != null && _saved != null && !_draft!.sameAs(_saved!);

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final saved = await ref.read(cardRepositoryProvider).save(_draft!);
      if (!mounted) return;
      setState(() => _adopt(saved));
      ref.invalidate(cardViewProvider(saved.handle));
      HapticFeedback.lightImpact();
      YqToast.show(context, t.cardSaved);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'handle_taken') setState(() => _handleFree = false);
      YqToast.show(
        context,
        switch (e.code) {
          'handle_taken' => t.cardHandleTaken,
          'handle_reserved' => t.cardHandleReserved,
          _ => t.errorGeneric,
        },
      );
    } on OfflineException {
      if (mounted) YqToast.show(context, t.redeemErrOffline);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    if (!session.canEarnPoints) return _GuestView(onSignIn: () => showSignInSheet(context));

    final mine = ref.watch(myCardProvider);
    if (_saved == null && mine.valueOrNull != null) _adopt(mine.valueOrNull!);
    final d = _draft;

    return Scaffold(
      body: YqCanvas(
        bottom: YqSpace.l,
        lights: d?.theme == CardLook.gold ? const [AmbientLight(Alignment(0, -0.8), Color(0x6BE9D49E))] : null,
        stage: YqStage(
          compact: true,
          gold: d?.theme == CardLook.gold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(
                back: true,
                title: t.cardTitle,
                actions: [
                  if (_saved != null && _saved!.published)
                    GlassIconButton(
                      tooltip: t.cardShare,
                      onPressed: () => ref.read(deviceServicesProvider).shareText(_saved!.url),
                      icon: const YqIcon(YqIcons.share, size: 20),
                    ),
                ],
              ),
              const SizedBox(height: YqSpace.l),
              if (d == null)
                const YqSkeleton(child: YqSkeletonBox(height: 300, radius: YqRadii.hero))
              else
                _CardPreview(card: d, saved: _saved!),
            ],
          ),
        ),
        footer: d == null
            ? null
            : YqButton(
                label: t.cardSave,
                loading: _saving,
                onPressed: _dirty && _valid && !_saving ? _save : null,
              ),
        children: switch (mine) {
          AsyncError() when d == null => [YqErrorState(onRetry: () => ref.invalidate(myCardProvider))],
          _ when d == null => [const YqSkeleton(child: YqSkeletonOrbs())],
          _ => _editor(context, t, d),
        },
      ),
    );
  }

  List<Widget> _editor(BuildContext context, AppLocalizations t, PublicCard d) {
    final text = Theme.of(context).textTheme;
    final saved = _saved!;
    final live = saved.published && !_dirty;
    return [
      YqOrbRow(
        orbs: [
          YqOrb(
            title: t.cardNfc,
            status: t.cardNfcStatus,
            onTap: () => _nfcSheet(context, saved, live),
            semanticLabel: t.cardNfcTitle,
            disc: const Center(child: _NfcGlyph(size: 46)),
          ),
          YqOrb(
            title: t.cardQr,
            status: t.cardQrStatus,
            onTap: () => _qrSheet(context, saved),
            semanticLabel: t.cardQr,
            disc: Center(
              child: QrImageView(
                data: saved.url,
                size: 64,
                padding: EdgeInsets.zero,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: YqColors.lapis),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: YqColors.navy),
              ),
            ),
          ),
          YqOrb(
            title: t.cardOpens,
            status: t.cardOpensStatus,
            glow: saved.views > 0,
            semanticLabel: '${t.cardOpens}: ${YqFormat.number(saved.views)}',
            disc: YqOrb.number(YqFormat.number(saved.views), size: 26, color: saved.views > 0 ? YqColors.goldDeep : YqColors.ink),
          ),
        ],
      ),
      const SizedBox(height: YqSpace.xl),
      LiquidGlass(
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
        child: YqListRow(
          title: t.cardPublish,
          subtitle: t.cardPublishHint,
          trailing: YqSwitch(label: t.cardPublish, value: d.published, onChanged: (v) => _edit((x) => x.copyWith(published: v))),
        ),
      ),
      const SizedBox(height: YqSpace.xl),
      YqHeading(t.cardIdentity),
      LiquidGlass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              controller: _name,
              label: t.cardName,
              maxLength: PublicCard.maxName,
              onChanged: (v) => _edit((x) => x.copyWith(displayName: v)),
            ),
            const SizedBox(height: YqSpace.m),
            _Field(
              controller: _handle,
              label: t.cardHandle,
              ltr: true,
              prefix: '@',
              maxLength: 24,
              onChanged: _onHandle,
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]'))],
              helper: switch ((_handleProblem, _handleFree)) {
                (HandleProblem.reserved, _) => (t.cardHandleReserved, true),
                (HandleProblem.format, _) => (t.cardHandleFormat, true),
                (_, false) => (t.cardHandleTaken, true),
                (_, true) => ('${t.cardHandleOk} · ${_publicHost(saved.url)}/u/${d.handle}', false),
                _ => (t.cardHandleFormat, false),
              },
            ),
            const SizedBox(height: YqSpace.m),
            _Field(
              controller: _bio,
              label: t.cardBio,
              hint: t.cardBioHint,
              maxLength: PublicCard.maxBio,
              maxLines: 3,
              onChanged: (v) => _edit((x) => x.copyWith(bio: v)),
            ),
          ],
        ),
      ),
      const SizedBox(height: YqSpace.xl),
      YqHeading(
        t.cardLinks,
        action: d.links.length < PublicCard.maxLinks
            ? TextButton.icon(
                onPressed: () => _addLink(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(t.cardAddLink),
              )
            : Text(t.cardLinksMax, style: text.bodySmall),
      ),
      if (d.links.isEmpty)
        GlassTap(
          onTap: () => _addLink(context),
          semanticLabel: t.cardAddLink,
          child: LiquidGlass(
            child: Row(
              children: [
                for (final k in const [SocialKind.instagram, SocialKind.x, SocialKind.whatsapp]) ...[
                  _Mono(kind: k, size: 32),
                  const SizedBox(width: 6),
                ],
                const SizedBox(width: YqSpace.s),
                Expanded(child: Text(t.cardAddLink, style: text.titleSmall?.copyWith(color: YqColors.lapis))),
              ],
            ),
          ),
        )
      else
        YqGroup(
          children: [
            for (final (i, l) in d.links.indexed)
              YqListRow(
                leading: _Mono(kind: l.kind),
                title: socialLabel(t, l.kind),
                subtitle: l.value,
                trailing: IconButton(
                  tooltip: t.delete,
                  icon: const Icon(Icons.close_rounded, color: YqColors.muted),
                  onPressed: () => _edit((x) => x.copyWith(links: [...x.links]..removeAt(i))),
                ),
              ),
          ],
        ),
      const SizedBox(height: YqSpace.xl),
      YqHeading(t.cardShows),
      YqGroup(
        children: [
          _toggle(t.cardShowLevel, d.show.level, (v) => d.show.copyWith(level: v)),
          _toggle(t.cardShowStreak, d.show.streak, (v) => d.show.copyWith(streak: v)),
          _toggle(t.cardShowChallenge, d.show.challengeDay, (v) => d.show.copyWith(challengeDay: v)),
          _toggle(t.cardShowBadges, d.show.badges, (v) => d.show.copyWith(badges: v)),
          _toggle(t.cardShowSince, d.show.memberSince, (v) => d.show.copyWith(memberSince: v)),
        ],
      ),
      const SizedBox(height: YqSpace.s),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline_rounded, size: 16, color: YqColors.goldText)),
            const SizedBox(width: YqSpace.s),
            Expanded(child: Text(t.cardPrivacy, style: text.bodySmall?.copyWith(color: YqColors.goldText))),
          ],
        ),
      ),
      const SizedBox(height: YqSpace.xl),
      YqHeading(t.cardThemeTitle),
      Row(
        children: [
          for (final th in CardLook.values) ...[
            if (th != CardLook.values.first) const SizedBox(width: YqSpace.m),
            Expanded(child: _ThemeSwatch(theme: th, selected: d.theme == th, onTap: () => _edit((x) => x.copyWith(theme: th)))),
          ],
        ],
      ),
    ];
  }

  Widget _toggle(String title, bool value, CardVisibility Function(bool v) next) => YqListRow(
        dense: true,
        title: title,
        trailing: YqSwitch(label: title, value: value, onChanged: (v) => _edit((x) => x.copyWith(show: next(v)))),
      );

  Future<void> _addLink(BuildContext context) async {
    final link = await showYqSheet<SocialLink>(context, scrollable: true, builder: (_) => const _LinkSheet());
    if (link != null) _edit((x) => x.copyWith(links: [...x.links, link]));
  }

  Future<void> _nfcSheet(BuildContext context, PublicCard saved, bool live) =>
      showYqSheet<void>(context, builder: (_) => _NfcSheet(url: saved.url, ready: live));

  Future<void> _qrSheet(BuildContext context, PublicCard saved) => showYqSheet<void>(context, builder: (_) => _QrSheet(card: saved));
}

String _publicHost(String url) => Uri.tryParse(url)?.host ?? '';

/* ------------------------------------------------------------- preview */

/// The public view (level, streak…) as the server computes it, for the preview.
final cardViewProvider = FutureProvider.autoDispose.family<CardView?, String>((ref, handle) => ref.watch(cardRepositoryProvider).publicView(handle));

/// The card as visitors will see it, in its chosen look — updates live while editing.
class _CardPreview extends ConsumerWidget {
  const _CardPreview({required this.card, required this.saved});
  final PublicCard card;
  final PublicCard saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Published: the server's numbers. Not yet: the level from the points history on the device.
    final view = saved.published ? ref.watch(cardViewProvider(saved.handle)).valueOrNull : null;
    final ledger = ref.watch(ledgerProvider).valueOrNull ?? const <LedgerEntry>[];
    final level = view?.level ?? levelFor(ledger.where((e) => e.delta > 0).fold(0, (s, e) => s + e.delta));
    final night = card.theme == CardLook.night;
    final ink = night ? YqColors.white : YqColors.ink;
    final muted = night ? const Color(0xFFC3C8D3) : YqColors.muted;
    final initial = card.displayName.trim().isEmpty ? '·' : String.fromCharCode(card.displayName.trim().runes.first);

    final chips = <Widget>[
      if (card.show.streak && view?.streak != null) _Stat(value: YqFormat.number(view!.streak!), label: t.cardShowStreak, night: night),
      if (card.show.challengeDay && view?.challengeDay != null)
        _Stat(value: YqFormat.number(view!.challengeDay!), label: t.cardShowChallenge, night: night),
      if (card.show.badges && view?.badges != null) _Stat(value: YqFormat.number(view!.badges!.length), label: t.cardShowBadges, night: night),
    ];

    return AnimatedContainer(
      duration: YqMotion.slow,
      curve: YqMotion.ease,
      padding: const EdgeInsets.fromLTRB(YqSpace.xl, YqSpace.xl, YqSpace.xl, YqSpace.l),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YqRadii.hero),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: switch (card.theme) {
            CardLook.sky => const [Color(0xF2FFFFFF), Color(0xCCE3EBF7)],
            CardLook.gold => const [YqColors.cream, YqColors.sand],
            CardLook.night => const [YqColors.midnight, YqColors.navy, YqColors.lapis],
          },
        ),
        border: Border.all(color: night ? const Color(0x29FFFFFF) : const Color(0xF2FFFFFF)),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              if (card.show.level) YqRing(value: level.progress, gold: true, size: 112, stroke: 4),
              Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: card.theme == CardLook.gold ? const [YqColors.gold300, YqColors.goldText] : const [YqColors.lapis500, YqColors.lapis],
                  ),
                  border: Border.all(color: const Color(0xF2FFFFFF), width: 3),
                ),
                child: Text(initial, style: const TextStyle(fontFamily: YqFonts.naskh, fontSize: 38, fontWeight: FontWeight.w700, color: YqColors.white)),
              ),
            ],
          ),
          const SizedBox(height: YqSpace.m),
          Text(
            card.displayName.trim().isEmpty ? '—' : card.displayName.trim(),
            textAlign: TextAlign.center,
            style: YqMoment.display(context, size: 28).copyWith(color: ink),
          ),
          Text('@${card.handle}', textDirection: TextDirection.ltr, style: YqText.numberSmall.copyWith(color: muted, fontSize: 13)),
          if (card.show.level) ...[
            const SizedBox(height: YqSpace.s),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: night ? const Color(0x1AE9D49E) : const Color(0x59E9D49E),
                borderRadius: BorderRadius.circular(YqRadii.pill),
                border: Border.all(color: const Color(0x73C6A867)),
              ),
              child: Text(
                '${level.name(locale)} · ${t.cardLevel(level.level)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: night ? YqColors.goldLight : YqColors.goldText),
              ),
            ),
          ],
          if (card.bio.trim().isNotEmpty) ...[
            const SizedBox(height: YqSpace.s),
            Text(card.bio.trim(), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.6, color: muted)),
          ],
          if (chips.isNotEmpty) ...[const SizedBox(height: YqSpace.m), Row(children: [for (final c in chips) Expanded(child: c)])],
          if (card.links.isNotEmpty) ...[
            const SizedBox(height: YqSpace.m),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [for (final l in card.links) _Mono(kind: l.kind, size: 30)]),
          ],
          const SizedBox(height: YqSpace.m),
          _StatusPill(live: saved.published, night: night),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.night});
  final String value;
  final String label;
  final bool night;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value, style: YqMoment.numeral(size: 26, color: night ? YqColors.white : YqColors.ink)),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 10.5, color: night ? const Color(0xFFC3C8D3) : YqColors.muted)),
        ],
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.live, required this.night});
  final bool live;
  final bool night;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: live ? YqColors.success : YqColors.slate400),
        ),
        const SizedBox(width: 6),
        Text(live ? t.cardLive : t.cardHidden, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: night ? const Color(0xFFC3C8D3) : YqColors.muted)),
      ],
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono({required this.kind, this.size = 40});
  final SocialKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.35),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: switch (kind) {
              SocialKind.whatsapp => const [Color(0xFF4FA27B), YqColors.success],
              SocialKind.website => const [YqColors.gold300, YqColors.goldText],
              _ => const [YqColors.lapis500, YqColors.navy],
            },
          ),
        ),
        child: Text(
          socialMono(kind),
          textDirection: TextDirection.ltr,
          style: YqText.numberSmall.copyWith(fontSize: size * 0.34, fontWeight: FontWeight.w500, color: YqColors.white),
        ),
      );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme, required this.selected, required this.onTap});
  final CardLook theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final label = switch (theme) {
      CardLook.sky => t.cardThemeSky,
      CardLook.gold => t.cardThemeGold,
      CardLook.night => t.cardThemeNight,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GlassTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: YqMotion.base,
          height: 76,
          alignment: AlignmentDirectional.bottomStart,
          padding: const EdgeInsets.all(YqSpace.m),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YqRadii.tile),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: switch (theme) {
                CardLook.sky => const [YqColors.white, YqColors.sky200],
                CardLook.gold => const [YqColors.cream, YqColors.gold200],
                CardLook.night => const [YqColors.midnight, YqColors.lapis],
              },
            ),
            border: Border.all(color: selected ? YqColors.lapis : const Color(0xE6FFFFFF), width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: theme == CardLook.night ? YqColors.white : YqColors.ink),
                ),
              ),
              if (selected) Icon(Icons.check_circle_rounded, size: 18, color: theme == CardLook.night ? YqColors.goldLight : YqColors.lapis),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hint,
    this.helper,
    this.maxLength,
    this.maxLines = 1,
    this.ltr = false,
    this.prefix,
    this.formatters,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final String? hint;

  /// (text, isProblem)
  final (String, bool)? helper;
  final int? maxLength;
  final int maxLines;
  final bool ltr;
  final String? prefix;
  final List<TextInputFormatter>? formatters;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(YqRadii.chip), borderSide: const BorderSide(color: YqColors.line));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: YqColors.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          maxLength: maxLength,
          maxLines: maxLines,
          minLines: 1,
          inputFormatters: formatters,
          textDirection: ltr ? TextDirection.ltr : null,
          autocorrect: !ltr,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            counterText: maxLines > 1 ? null : '',
            filled: true,
            fillColor: const Color(0xCCFFFFFF),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(borderSide: const BorderSide(color: YqColors.lapis, width: 1.4)),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              helper!.$1,
              textDirection: helper!.$2 ? null : TextDirection.ltr,
              style: TextStyle(fontSize: 11.5, color: helper!.$2 ? YqColors.goldText : YqColors.success),
            ),
          ),
      ],
    );
  }
}

/* ---------------------------------------------------------------- sheets */

class _LinkSheet extends StatefulWidget {
  const _LinkSheet();

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  SocialKind _kind = SocialKind.instagram;
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final link = SocialLink(_kind, _value.text);
    final ok = _value.text.trim().isNotEmpty && link.url != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.cardAddLink, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: YqSpace.l),
        Wrap(
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            for (final k in SocialKind.values)
              YqChip(label: socialLabel(t, k), selected: _kind == k, onTap: () => setState(() => _kind = k)),
          ],
        ),
        const SizedBox(height: YqSpace.l),
        _Field(
          controller: _value,
          label: t.cardLinkValue,
          ltr: true,
          maxLength: 120,
          onChanged: (_) => setState(() {}),
          helper: _value.text.trim().isEmpty ? null : (ok ? (link.url!, false) : (t.cardLinkInvalid, true)),
        ),
        const SizedBox(height: YqSpace.l),
        YqButton(label: t.cardAddLink, onPressed: ok ? () => Navigator.of(context).pop(SocialLink(_kind, _value.text.trim())) : null),
      ],
    );
  }
}

/// Writes the card link to a tag. Gently pulsing rings while waiting; clear outcomes; and a way
/// to get a Yaqeen NFC tag from the store.
class _NfcSheet extends ConsumerStatefulWidget {
  const _NfcSheet({required this.url, required this.ready});
  final String url;

  /// Published and saved: a scanner would see the card.
  final bool ready;

  @override
  ConsumerState<_NfcSheet> createState() => _NfcSheetState();
}

class _NfcSheetState extends ConsumerState<_NfcSheet> {
  bool _waiting = false;
  NfcWriteResult? _result;

  @override
  void dispose() {
    if (_waiting) ref.read(nfcWriterProvider).cancel();
    super.dispose();
  }

  Future<void> _write() async {
    final t = AppLocalizations.of(context);
    setState(() {
      _waiting = true;
      _result = null;
    });
    final r = await ref.read(nfcWriterProvider).writeUrl(widget.url, prompt: t.cardNfcHint, done: t.cardNfcWritten);
    if (!mounted) return;
    if (r == NfcWriteResult.written) HapticFeedback.mediumImpact();
    setState(() {
      _waiting = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final message = switch (_result) {
      null => widget.ready ? t.cardNfcHint : t.cardNfcPublishFirst,
      NfcWriteResult.written => t.cardNfcWritten,
      NfcWriteResult.notSupported => t.cardNfcUnsupported,
      NfcWriteResult.disabled => t.cardNfcDisabled,
      NfcWriteResult.notWritable => t.cardNfcNotWritable,
      NfcWriteResult.tooSmall => t.cardNfcTooSmall,
      NfcWriteResult.cancelled || NfcWriteResult.failed => t.cardNfcFailed,
    };
    final done = _result == NfcWriteResult.written;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.cardNfcTitle, textAlign: TextAlign.center, style: text.titleLarge),
        const SizedBox(height: YqSpace.xl),
        Center(child: _Pulse(active: _waiting, done: done)),
        const SizedBox(height: YqSpace.l),
        Text(
          message,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: done ? YqColors.success : (_result == null ? YqColors.muted : YqColors.goldText)),
        ),
        const SizedBox(height: YqSpace.s),
        Text(widget.url, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: YqText.numberSmall.copyWith(fontSize: 12, color: YqColors.muted)),
        const SizedBox(height: YqSpace.xl),
        if (done)
          YqButton(label: t.close, onPressed: () => Navigator.of(context).pop())
        else
          YqButton(label: t.cardNfcStart, loading: _waiting, onPressed: widget.ready && !_waiting ? _write : null),
        const SizedBox(height: YqSpace.s),
        YqButton.text(
          label: t.cardNfcBuy,
          onPressed: () => ref.read(deviceServicesProvider).openUrl(Uri.parse(Env.storeUrl)),
        ),
      ],
    );
  }
}

/// Concentric rings breathing out from the NFC glyph while the phone waits for a tag.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.done});
  final bool active;
  final bool done;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.active && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 150,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => CustomPaint(painter: _PulsePainter(_c.value, widget.active), child: child),
          child: Center(
            child: AnimatedContainer(
              duration: YqMotion.base,
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.done ? YqColors.success : YqColors.navy),
              child: Center(
                child: widget.done
                    ? const Icon(Icons.check_rounded, color: YqColors.white, size: 40)
                    : const _NfcGlyph(size: 40, color: YqColors.goldLight),
              ),
            ),
          ),
        ),
      );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t, this.active);
  final double t;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    if (!active) {
      canvas.drawCircle(
        c,
        58,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0x331F3F94),
      );
      return;
    }
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        42 + 34 * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = YqColors.lapis.withValues(alpha: 0.45 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t || old.active != active;
}

/// Three widening arcs — the contactless mark, drawn (no icon font needed).
class _NfcGlyph extends StatelessWidget {
  const _NfcGlyph({this.size = 40, this.color = YqColors.lapis});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: size, child: CustomPaint(painter: _NfcGlyphPainter(color)));
}

class _NfcGlyphPainter extends CustomPainter {
  _NfcGlyphPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.08
      ..color = color;
    final c = Offset(size.width * 0.28, size.height / 2);
    for (var i = 1; i <= 3; i++) {
      final r = size.width * 0.17 * i;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -0.75, 1.5, false, paint);
    }
    canvas.drawCircle(c, size.width * 0.06, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NfcGlyphPainter old) => old.color != color;
}

/// A QR on a printable card: the logo above, the code with round modules, the name and link.
class _QrSheet extends ConsumerWidget {
  const _QrSheet({required this.card});
  final PublicCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.cardQrTitle, textAlign: TextAlign.center, style: text.titleLarge),
        const SizedBox(height: YqSpace.l),
        Center(
          child: Container(
            padding: const EdgeInsets.all(YqSpace.xl),
            decoration: BoxDecoration(
              color: YqColors.white,
              borderRadius: BorderRadius.circular(YqRadii.hero),
              border: Border.all(color: YqColors.line),
            ),
            child: Column(
              children: [
                QrImageView(
                  data: card.url,
                  size: 220,
                  padding: EdgeInsets.zero,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: YqColors.lapis),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: YqColors.navy),
                  embeddedImage: const AssetImage('assets/brand/mark-navy.png'),
                  embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(44, 44)),
                ),
                const SizedBox(height: YqSpace.m),
                Text(card.displayName, style: YqMoment.display(context, size: 22)),
                Text('@${card.handle}', textDirection: TextDirection.ltr, style: YqText.numberSmall.copyWith(color: YqColors.muted)),
              ],
            ),
          ),
        ),
        const SizedBox(height: YqSpace.l),
        YqButton(label: t.cardShare, onPressed: () => ref.read(deviceServicesProvider).shareText(card.url)),
        const SizedBox(height: YqSpace.s),
        YqButton.secondary(
          label: t.copy,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: card.url));
            if (context.mounted) YqToast.show(context, t.copied);
          },
        ),
      ],
    );
  }
}

class _GuestView extends StatelessWidget {
  const _GuestView({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: YqCanvas(
        bottom: YqSpace.l,
        stage: YqStage(
          compact: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YqStageBar(back: true, title: t.cardTitle),
              const SizedBox(height: YqSpace.xl),
              const Center(child: _NfcGlyph(size: 72)),
              const SizedBox(height: YqSpace.l),
              YqMoment(value: Text(t.cardTeaserTitle, style: YqMoment.display(context, size: 28)), caption: Text(t.cardGuest)),
            ],
          ),
        ),
        footer: YqButton(label: t.signIn, onPressed: onSignIn),
        children: const [],
      ),
    );
  }
}
