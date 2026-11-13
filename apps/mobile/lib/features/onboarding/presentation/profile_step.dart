import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/env.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/platform/photo_picker.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../community/domain/community_models.dart';
import '../../profile/domain/avatar.dart';
import '../../profile/domain/avatar_presets.dart';
import '../../profile/domain/level.dart';
import '../../profile/domain/me_profile.dart';
import '../../profile/presentation/me_profile_controller.dart';
import 'onboarding_screens.dart';
import 'session_controller.dart';
import 'sign_in_sheet.dart';
import 'splash_gate.dart';

enum _Filter { all, men, women }

/// Onboarding step 05·ج «ملفّك» at `/onboarding/profile` (APP_SPEC §5.7·ج, design §8): a picture
/// (a photo or one of the 16 presets) and a name, what levels and competitions are, and the weekly
/// league opt-in — off by default, signed-in only, with the age attestation and a connection.
///
/// Name and picture are written on this phone first ([meProfileProvider]; guests stay local until
/// they link an account). Joining the league is a direct call; a failure is shown inline and the
/// person continues with the switch off. Skip keeps the defaults.
class ProfileStep extends ConsumerStatefulWidget {
  const ProfileStep({super.key});

  @override
  ConsumerState<ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<ProfileStep> {
  static const _next = '/onboarding/download';

  late final TextEditingController _name = TextEditingController(text: _initialName())..addListener(_onName);

  /// A preset (or the initial) picked here; null keeps the current picture.
  AvatarRef? _picked;
  _Filter _filter = _Filter.all;
  bool _join = false;
  bool _attest = false;
  bool _busy = false;
  bool _photoBusy = false;
  String? _error;

  /// The person typed in the name field: a late-arriving profile no longer replaces the prefill.
  bool _nameTouched = false;

  /// Preset art decoded (or given up waiting): until then the grid is shaped skeleton circles.
  bool _presetsReady = false;
  bool _precacheStarted = false;
  Timer? _presetsTimeout;

  /// Prefill: what the person already chose on this phone, else the **first name only** of the
  /// Google/Apple account (never the full name).
  String _initialName() {
    final session = ref.read(sessionProvider);
    final profile = ref.read(meProfileProvider).valueOrNull;
    final saved = profile?.displayName?.trim() ?? '';
    if (!session.canEarnPoints) return saved;
    final account = session.displayName?.trim() ?? '';
    if (saved.isNotEmpty && saved != account) return saved;
    return MeProfile.firstNameOf(account.isNotEmpty ? account : saved);
  }

  void _onName() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precacheStarted) return;
    _precacheStarted = true;
    // Never hold the grid back for long (a slow decoder, tests without one).
    _presetsTimeout = Timer(const Duration(milliseconds: 700), _presetsDecoded);
    Future.wait([for (final p in kAvatarPresets) precacheImage(AssetImage(p.asset), context, onError: (_, __) {})])
        .whenComplete(_presetsDecoded)
        .ignore();
  }

  void _presetsDecoded() {
    _presetsTimeout?.cancel();
    if (mounted && !_presetsReady) setState(() => _presetsReady = true);
  }

  @override
  void dispose() {
    _presetsTimeout?.cancel();
    _name
      ..removeListener(_onName)
      ..dispose();
    super.dispose();
  }

  /* ---------------------------------------------------------------- picture */

  Future<void> _pickPhoto() async {
    final t = AppLocalizations.of(context);
    setState(() => _photoBusy = true);
    final result = await ref.read(meProfileProvider.notifier).pickPhoto(PhotoSource.gallery);
    if (!mounted) return;
    setState(() {
      _photoBusy = false;
      // A picked photo is now the profile's picture (shown at once, synced by the repository).
      if (result != null && (result.isOk || result.errorOrNull == CommunityFailure.offline)) _picked = null;
    });
    final failure = result?.errorOrNull;
    final message = switch (failure) {
      null || CommunityFailure.offline => null, // offline: kept on the phone and retried later
      CommunityFailure.photoTooLarge => t.pfPhotoTooLarge,
      CommunityFailure.rateLimited => t.pfPhotoRateLimited,
      CommunityFailure.photoUnreadable || CommunityFailure.photoType => t.pfPhotoUnreadable,
      _ => t.pfUploadFailed,
    };
    if (message != null) YqToast.show(context, message);
  }

  /* ------------------------------------------------------------------ league */

  Future<void> _toggleJoin(bool on) async {
    if (!on) {
      setState(() {
        _join = false;
        _error = null;
      });
      return;
    }
    if (!ref.read(sessionProvider).canEarnPoints) {
      final t = AppLocalizations.of(context);
      final ok = await showSignInSheet(context, title: t.obSignInToJoin);
      if (!mounted) return;
      if (!ok || !ref.read(sessionProvider).canEarnPoints) return;
    }
    setState(() {
      _join = true;
      _error = null;
    });
  }

  String _failureCopy(AppLocalizations t, CommunityFailure f) => switch (f) {
        CommunityFailure.offline => t.obNeedsConnection,
        CommunityFailure.attestationRequired => t.cmErrAttestation,
        CommunityFailure.nameRequired => t.cmErrNameRequired,
        CommunityFailure.invalidName => t.cmErrInvalidName,
        CommunityFailure.nameLocked => t.cmErrNameLocked,
        CommunityFailure.accountRequired => t.obSignInToJoin,
        _ => t.obJoinFailed,
      };

  /* --------------------------------------------------------------------- CTA */

  Future<void> _continue() async {
    final t = AppLocalizations.of(context);
    final profile = ref.read(meProfileProvider).valueOrNull;
    final attested = profile?.community.attestedAdult ?? false;
    final leagues = ref.read(remoteConfigProvider).isOn(Flags.leagues);
    final join = _join && leagues;
    if (join && !attested && !_attest) {
      setState(() => _error = t.cmErrAttestation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final me = ref.read(meProfileProvider.notifier);
    final name = _name.text.trim();
    if (name.isNotEmpty && name != (profile?.displayName?.trim() ?? '')) await me.setName(name);
    final picked = _picked;
    if (picked != null && picked != profile?.avatar) await me.setAvatar(picked);
    if (join) {
      final r = await me.join(
        CommunityUpdate(
          leagues: true,
          displayName: name.isEmpty ? null : name,
          attestAdult: true,
          source: CommunitySource.onboarding,
        ),
      );
      if (!mounted) return;
      final failure = r.errorOrNull;
      if (failure != null) {
        // Shown here; the person carries on with the switch off (they can join later).
        setState(() {
          _busy = false;
          _join = false;
          _attest = false;
          _error = _failureCopy(t, failure);
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    advanceOnboarding(context, ref, _next);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    final profile = ref.watch(meProfileProvider).valueOrNull ?? MeProfile.guest();
    final leagues = ref.watch(remoteConfigProvider.select((c) => c.isOn(Flags.leagues)));
    final picker = ref.watch(photoPickerProvider);
    final current = _picked ?? (profile.photoHidden && profile.avatar is PhotoAvatar ? const InitialAvatar() : profile.avatar);
    final typed = _name.text.trim();
    final level = profile.level;
    final attested = profile.community.attestedAdult;
    // The cached profile can land a moment after the first frame: prefill from it then.
    ref.listen(meProfileProvider, (prev, next) {
      if (_nameTouched || prev?.valueOrNull != null || next.valueOrNull == null) return;
      final initial = _initialName();
      if (initial != _name.text) _name.text = initial;
    });

    final presets = [
      for (final p in kAvatarPresets)
        if (_filter == _Filter.all || (_filter == _Filter.men) == (p.gender == AvatarGender.m)) p,
    ];

    return OnboardingStepFrame(
      step: onboardingRoutes.indexOf('/onboarding/profile'),
      title: t.obProfileTitle,
      sub: t.obProfileSub,
      cta: t.obContinue,
      ctaLoading: _busy,
      onCta: () {
        if (!_busy) unawaited(_continue());
      },
      skipLabel: t.obSkip,
      onSkip: _busy ? null : () => advanceOnboarding(context, ref, _next),
      // The person as others would see them: picture in the level ring, name, level.
      visual: Center(
        child: Column(
          children: [
            YqLevelAvatar(
              avatar: current,
              level: level.level,
              progress: level.progress,
              size: 112,
              stroke: 4,
              achieved: level.isTop,
              name: typed.isEmpty ? null : typed,
              levelName: level.name(locale),
            ),
            const SizedBox(height: YqSpace.s),
            Text(
              typed.isEmpty ? t.obNameHint : typed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: typed.isEmpty ? YqColors.muted : YqColors.ink),
            ),
            Text(level.name(locale), style: text.bodySmall?.copyWith(color: YqColors.muted)),
          ],
        ),
      ),
      children: [
        _Heading(t.obYourPhoto),
        YqSegmented<_Filter>(
          segments: [(_Filter.all, t.obFilterAll), (_Filter.men, t.obFilterMen), (_Filter.women, t.obFilterWomen)],
          selected: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: YqSpace.m),
        _presetsReady
            ? _TileGrid(
                children: [
                  if (picker.available)
                    _PhotoTile(
                      label: t.obFromPhotos,
                      selected: _picked == null && current is PhotoAvatar,
                      busy: _photoBusy,
                      onTap: _photoBusy ? null : _pickPhoto,
                    ),
                  for (final p in presets)
                    _PresetTile(
                      preset: p,
                      label: p.label(locale),
                      selected: current == PresetAvatar(p.id),
                      onTap: () => setState(() => _picked = PresetAvatar(p.id)),
                    ),
                ],
              )
            : YqSkeleton(
                child: _TileGrid(
                  children: [
                    for (var i = 0; i < presets.length + (picker.available ? 1 : 0); i++)
                      const SizedBox.square(dimension: _tile, child: Center(child: YqSkeletonBox.circle(_circle))),
                  ],
                ),
              ),
        const SizedBox(height: YqSpace.xl),
        _Heading(t.obYourName),
        TextField(
          controller: _name,
          onChanged: (_) => _nameTouched = true,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: t.obNameHint, helperText: t.obNameHelper, helperMaxLines: 2),
        ),
        const SizedBox(height: YqSpace.l),
        LiquidGlass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.obLevelsCard, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: YqSpace.s),
              Text(t.obLevelsLine, style: text.bodySmall),
              const SizedBox(height: YqSpace.s),
              // The six levels; the first is where everyone starts.
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (var i = 0; i < cardLevels.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: i == 0 ? YqColors.lapis : YqColors.line),
                      ),
                    ],
                  ],
                ),
              ),
              if (leagues) ...[const SizedBox(height: YqSpace.s), Text(t.obLeagueLine, style: text.bodySmall)],
              const SizedBox(height: YqSpace.s),
              Text(t.obTournamentsLine, style: text.bodySmall),
            ],
          ),
        ),
        if (leagues) ...[
          const SizedBox(height: YqSpace.m),
          LiquidGlass(
            padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
            child: Column(
              children: [
                _SwitchRow(
                  title: t.obJoinLeague,
                  detail: t.obJoinLeagueDetail,
                  value: _join,
                  onChanged: _busy ? null : _toggleJoin,
                ),
                if (_join && !attested) ...[
                  const YqDivider(),
                  _SwitchRow(
                    title: t.obAttest,
                    value: _attest,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _attest = v;
                              if (v) _error = null;
                            }),
                  ),
                ],
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: YqSpace.s, top: YqSpace.s),
              child: Semantics(liveRegion: true, child: Text(_error!, style: text.bodySmall?.copyWith(color: YqColors.ink))),
            ),
          const SizedBox(height: YqSpace.m),
          _PrivacyNote(
            note: t.obPrivacyNote,
            link: t.obTerms,
            onLink: () => ref.read(deviceServicesProvider).openUrl(Env.site('terms', locale).replace(fragment: 'community')),
          ),
        ],
      ],
    );
  }
}

const double _circle = 72;
const double _tile = 80;

/// Even columns of [_tile]-wide cells (4 on a phone), rows filled from the start edge.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          const gap = YqSpace.s;
          final columns = ((box.maxWidth + gap) / (_tile + gap)).floor().clamp(3, 8);
          final cell = (box.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final c in children) SizedBox(width: cell, child: Center(child: c))],
          );
        },
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: YqSpace.s),
        child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      );
}

/// A preset in a 72-pt circle; selected = a 2-pt lapis ring and a check.
class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.label, required this.selected, required this.onTap});
  final AvatarPreset preset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: GlassTap(
          onTap: onTap,
          child: _Ring(selected: selected, child: YqAvatar(avatar: PresetAvatar(preset.id), size: _circle - 6, rim: false)),
        ),
      );
}

/// «من صورك»: opens the photo picker (shown only when one is available).
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.label, required this.selected, required this.busy, required this.onTap});
  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        enabled: onTap != null,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: GlassTap(
          onTap: onTap,
          child: _Ring(
            selected: selected,
            child: busy
                ? const YqSkeleton(child: YqSkeletonBox.circle(_circle - 6))
                : Container(
                    width: _circle - 6,
                    height: _circle - 6,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: YqColors.white.withValues(alpha: 0.6),
                      border: Border.all(color: YqColors.line),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const YqIcon(YqIcons.photo, size: 20),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: YqSpace.xs),
                          child: Text(
                            label,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            // Inside a fixed circle: it keeps its size (the tile is labelled for screen readers).
                            textScaler: TextScaler.noScaling,
                            style: const TextStyle(fontSize: 9.5, height: 1.15, fontWeight: FontWeight.w600, color: YqColors.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
}

class _Ring extends StatelessWidget {
  const _Ring({required this.selected, required this.child});
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: _tile,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: YqMotion.fast,
              width: _circle,
              height: _circle,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? YqColors.lapis : YqColors.lapis.withValues(alpha: 0), width: 2),
              ),
              child: child,
            ),
            if (selected)
              PositionedDirectional(
                end: 2,
                bottom: 2,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: YqColors.lapis,
                    border: Border.all(color: YqColors.white, width: 2),
                  ),
                  child: const Icon(Icons.check_rounded, size: 14, color: YqColors.white),
                ),
              ),
          ],
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, this.detail, required this.value, required this.onChanged});
  final String title;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (detail != null) Text(detail!, style: text.bodySmall?.copyWith(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: YqSpace.s),
          IgnorePointer(
            ignoring: onChanged == null,
            child: YqSwitch(label: title, value: value, onChanged: onChanged ?? (_) {}),
          ),
        ],
      ),
    );
  }
}

/// The green privacy reassurance with the competition terms link (as on the consent step).
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.note, required this.link, required this.onLink});
  final String note;
  final String link;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(YqSpace.m),
      decoration: BoxDecoration(color: YqColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(YqRadii.tile)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: YqColors.success, size: 20),
          const SizedBox(width: YqSpace.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note, style: text.bodySmall?.copyWith(color: YqColors.success)),
                Semantics(
                  link: true,
                  child: GestureDetector(
                    onTap: onLink,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: YqSpace.xs),
                      child: Text(link, style: text.bodySmall?.copyWith(color: YqColors.success, decoration: TextDecoration.underline)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
