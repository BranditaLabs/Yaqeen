import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/config_controller.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/platform/photo_picker.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../card/presentation/card_screen.dart' show myCardProvider;
import '../../community/domain/community_models.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../domain/avatar.dart';
import '../domain/avatar_presets.dart';
import '../domain/me_profile.dart';
import 'me_profile_controller.dart';
import 'profile_providers.dart';

/// What the sheet hands back when the person chose to take or pick a photo (the picker opens
/// after the sheet has closed, so the upload's ring and toasts show on the screen underneath).
enum _Pick { camera, album }

/// «صورتك»: the 16 presets (filtered «الكل · رجال · نساء»), a photo, or the initial. Presets and
/// the initial are saved on this phone at once and synced; a photo uploads directly.
Future<void> showAvatarSheet(BuildContext context, WidgetRef ref) async {
  final pick = await showYqSheet<_Pick>(context, scrollable: true, builder: (_) => const AvatarSheet());
  if (pick == null || !context.mounted) return;
  await pickAndUploadPhoto(context, ref, pick == _Pick.camera ? PhotoSource.camera : PhotoSource.gallery);
}

/// Opens the picker, shows the photo at once, uploads it (the stage ring shimmers meanwhile) and
/// says what went wrong, if anything.
Future<void> pickAndUploadPhoto(BuildContext context, WidgetRef ref, PhotoSource source) async {
  final t = AppLocalizations.of(context);
  final uploading = ref.read(photoUploadingProvider.notifier);
  final profile = ref.read(meProfileProvider.notifier);
  uploading.state = true;
  Result<AvatarRef, CommunityFailure>? result;
  try {
    result = await profile.pickPhoto(source);
  } on Object {
    result = const Err(CommunityFailure.unknown);
  } finally {
    uploading.state = false;
  }
  final failure = result?.errorOrNull;
  if (failure == null || !context.mounted) return;
  YqToast.show(context, photoFailureMessage(t, failure));
}

/// The toast for a failed photo upload.
String photoFailureMessage(AppLocalizations t, CommunityFailure f) => switch (f) {
      CommunityFailure.photoTooLarge => t.pfPhotoTooLarge,
      CommunityFailure.rateLimited => t.pfPhotoRateLimited,
      CommunityFailure.photoUnreadable || CommunityFailure.photoType => t.pfPhotoUnreadable,
      CommunityFailure.photoLocked => t.pfAvatarHidden,
      // Kept on this phone and retried when the connection is back.
      CommunityFailure.offline => t.pfPendingSync,
      _ => t.pfUploadFailed,
    };

class AvatarSheet extends ConsumerStatefulWidget {
  const AvatarSheet({super.key});

  @override
  ConsumerState<AvatarSheet> createState() => _AvatarSheetState();
}

class _AvatarSheetState extends ConsumerState<AvatarSheet> {
  AvatarGender? _filter;
  bool _attesting = false;

  Future<void> _choose(AvatarRef avatar) async {
    await ref.read(meProfileProvider.notifier).setAvatar(avatar);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _attest() async {
    final t = AppLocalizations.of(context);
    setState(() => _attesting = true);
    final r = await ref.read(meProfileProvider.notifier).attest();
    if (!mounted) return;
    setState(() => _attesting = false);
    final failure = r.errorOrNull;
    if (failure != null) YqToast.show(context, failure == CommunityFailure.offline ? t.pfAttestOffline : t.errorGeneric);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final session = ref.watch(sessionProvider);
    final profile = ref.watch(meProfileProvider).valueOrNull ?? MeProfile.guest(displayName: session.displayName);
    final picker = ref.watch(photoPickerProvider);
    final current = profile.avatar;
    final hasPhoto = current is PhotoAvatar && !profile.photoHidden;
    final name = profile.displayName ?? session.displayName;
    final presets = [
      for (final p in kAvatarPresets)
        if (_filter == null || p.gender == _filter) p,
    ];

    // Others would see the photo (card published or in a competition) but the age isn't confirmed.
    var needsAttest = false;
    if (hasPhoto && session.canEarnPoints && !profile.community.attestedAdult) {
      final cardLive =
          ref.watch(remoteConfigProvider).isOn(Flags.publicCards) && (ref.watch(myCardProvider).valueOrNull?.published ?? false);
      needsAttest = profile.community.anyOn || cardLive;
    }

    Widget action(String label, YqIcons icon, VoidCallback? onTap) => YqListRow(
          dense: true,
          title: label,
          titleColor: onTap == null ? YqColors.muted : null,
          leading: YqIconTile(icon, size: 36, tone: onTap == null ? YqIconTone.idle : YqIconTone.active),
          onTap: onTap,
          trailing: const SizedBox.shrink(),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.pfAvatarTitle, style: text.titleLarge)),
        const SizedBox(height: YqSpace.m),
        if (profile.photoHidden) ...[
          _Note(key: const ValueKey('avatar-hidden'), icon: YqIcons.lock, text: t.pfAvatarHidden, strong: true),
          const SizedBox(height: YqSpace.m),
        ],
        YqSegmented<AvatarGender?>(
          segments: [(null, t.pfFilterAll), (AvatarGender.m, t.pfFilterMen), (AvatarGender.f, t.pfFilterWomen)],
          selected: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: YqSpace.m),
        AnimatedSize(
          duration: YqMotion.base,
          curve: YqMotion.ease,
          alignment: Alignment.topCenter,
          child: Column(
            children: [
              for (var i = 0; i < presets.length; i += 4)
                Padding(
                  padding: const EdgeInsets.only(bottom: YqSpace.s),
                  child: Row(
                    children: [
                      for (var c = 0; c < 4; c++)
                        Expanded(
                          child: i + c < presets.length
                              ? Center(
                                  child: _PresetTile(
                                    preset: presets[i + c],
                                    label: presets[i + c].label(locale),
                                    selected: current is PresetAvatar && current.id == presets[i + c].id,
                                    onTap: () => _choose(PresetAvatar(presets[i + c].id)),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: YqSpace.s),
        YqGroup(
          children: [
            if (picker.available) ...[
              action(t.pfTakePhoto, YqIcons.camera, profile.photoHidden ? null : () => Navigator.of(context).pop(_Pick.camera)),
              action(t.pfFromAlbum, YqIcons.photo, profile.photoHidden ? null : () => Navigator.of(context).pop(_Pick.album)),
            ],
            if (hasPhoto)
              action(t.pfRemovePhoto, YqIcons.photo, () async {
                await ref.read(meProfileProvider.notifier).removePhoto();
              }),
            YqListRow(
              dense: true,
              title: t.pfUseInitial,
              leading: YqAvatar(avatar: const InitialAvatar(), size: 36, name: name, rim: false, semanticLabel: ''),
              trailing: current is InitialAvatar ? _Check(label: t.pfSelected) : const SizedBox.shrink(),
              onTap: () => _choose(const InitialAvatar()),
            ),
          ],
        ),
        const SizedBox(height: YqSpace.m),
        if (needsAttest) ...[
          LiquidGlass(
            key: const ValueKey('avatar-attest'),
            padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.pfAvatarAttestNote, style: text.bodySmall?.copyWith(height: 1.6)),
                const SizedBox(height: YqSpace.s),
                Row(
                  children: [
                    Expanded(child: Text(t.pfAttest, style: text.titleSmall?.copyWith(height: 1.5))),
                    const SizedBox(width: YqSpace.m),
                    YqSwitch(label: t.pfAttest, value: _attesting, onChanged: (v) => v && !_attesting ? _attest() : null),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: YqSpace.m),
        ],
        _Note(icon: YqIcons.lock, text: session.canEarnPoints ? t.pfAvatarNote : t.pfAvatarGuestNote),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.label, required this.selected, required this.onTap});
  final AvatarPreset preset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Semantics(
      selected: selected,
      child: GlassTap(
        onTap: onTap,
        semanticLabel: selected ? t.pfSemanticsJoin(label, t.pfSelected) : label,
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: YqMotion.fast,
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? YqColors.lapis : YqColors.lapis.withValues(alpha: 0), width: 2),
                  ),
                ),
                YqAvatar(avatar: PresetAvatar(preset.id), size: 64, semanticLabel: label),
                if (selected) PositionedDirectional(end: 0, bottom: 0, child: _Check(label: t.pfSelected)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The lapis check on the chosen picture.
class _Check extends StatelessWidget {
  const _Check({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Container(
          key: const ValueKey('avatar-selected'),
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, color: YqColors.lapis, border: Border.all(color: YqColors.white, width: 2)),
          child: const Icon(Icons.check_rounded, size: 14, color: YqColors.white),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text, this.strong = false});
  final YqIcons icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: YqIcon(icon, size: 16, tone: strong ? YqIconTone.active : YqIconTone.idle),
          ),
          const SizedBox(width: YqSpace.s),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: strong ? 13.5 : 12, height: 1.6, color: strong ? YqColors.ink : YqColors.muted),
            ),
          ),
        ],
      );
}
