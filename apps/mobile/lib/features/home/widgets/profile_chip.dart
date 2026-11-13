import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../profile/domain/avatar.dart';
import '../../profile/presentation/me_profile_controller.dart';

/// True while Home plays the one-shot level-up glint on the chip (APP_SPEC §5.9): the only time,
/// besides the top level «منارة», the ring turns gold. Kept for the app's lifetime: Home may set it
/// before the chip has painted its first ring.
final profileChipGlintProvider = StateProvider<bool>((_) => false);

/// The Home header's profile place (APP_SPEC §5.9, design §7): the caller's avatar in a lapis
/// level ring with the level numeral; tap → `/profile`.
///
/// It reads [meProfileProvider] only (the cached profile, never the network). Guests get the
/// avatar without a ring; a skeleton circle shows only while there is no value at all.
class ProfileChip extends ConsumerWidget {
  const ProfileChip({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final profile = ref.watch(meProfileProvider).valueOrNull;
    if (profile == null) return YqSkeleton(child: YqSkeletonBox.circle(size));
    final session = ref.watch(sessionProvider);
    final glint = ref.watch(profileChipGlintProvider);
    final locale = Localizations.localeOf(context).languageCode;
    final account = session.canEarnPoints;
    final profileName = profile.displayName?.trim() ?? '';
    final sessionName = session.displayName?.trim() ?? '';
    final name = profileName.isNotEmpty ? profileName : (account && sessionName.isNotEmpty ? sessionName : t.guestName);
    // Support hid the photo: draw the initial until the person picks another picture.
    final avatar = profile.photoHidden && profile.avatar is PhotoAvatar ? const InitialAvatar() : profile.avatar;
    final level = profile.level;

    final String label;
    final Widget picture;
    if (account) {
      label = t.hmChipSemantics(
        name,
        YqFormat.number(level.level),
        level.name(locale),
        YqFormat.number((level.progress.clamp(0.0, 1.0) * 100).round()),
      );
      picture = YqLevelAvatar(
        avatar: avatar,
        level: level.level,
        progress: level.progress,
        size: size,
        stroke: 2.5,
        // Gold only for the glint of a level just reached, or at the top level.
        achieved: glint || level.isTop,
        showLevel: true,
        name: name,
        levelName: level.name(locale),
      );
    } else {
      label = t.hmChipGuest(name);
      picture = YqAvatar(avatar: avatar, size: size, name: name);
    }

    void open() {
      HapticFeedback.lightImpact();
      context.go('/profile');
    }

    return Semantics(
      button: true,
      label: label,
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: SizedBox.square(dimension: size, child: picture),
      ),
    );
  }
}
