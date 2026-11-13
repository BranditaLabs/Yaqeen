import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_states.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../domain/avatar.dart';
import 'me_profile_controller.dart';

/// The caller's own avatar from [meProfileProvider] (cached, never waits on the network). With
/// [ring], it sits in their live level ring (guests: no ring); a skeleton circle only while there
/// is no value at all.
class MeAvatar extends ConsumerWidget {
  const MeAvatar({super.key, this.size = 40, this.ring = false, this.stroke = 2.5, this.showLevel = false, this.semanticLabel});

  final double size;
  final bool ring;
  final double stroke;
  final bool showLevel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(meProfileProvider).valueOrNull;
    if (profile == null) return YqSkeletonBox.circle(size);
    final session = ref.watch(sessionProvider);
    final name = profile.displayName ?? session.displayName;
    final avatar = profile.photoHidden && profile.avatar is PhotoAvatar ? const InitialAvatar() : profile.avatar;
    if (!ring || !session.canEarnPoints) {
      return YqAvatar(avatar: avatar, size: size, name: name, semanticLabel: semanticLabel);
    }
    final locale = Localizations.localeOf(context).languageCode;
    return YqLevelAvatar(
      avatar: avatar,
      level: profile.level.level,
      progress: profile.level.progress,
      size: size,
      stroke: stroke,
      achieved: profile.level.isTop,
      showLevel: showLevel,
      name: name,
      levelName: profile.level.name(locale),
      semanticLabel: semanticLabel,
    );
  }
}
