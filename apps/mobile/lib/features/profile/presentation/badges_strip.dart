import 'dart:convert';

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_once.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../community/domain/community_models.dart';
import '../../community/presentation/badge_label.dart';
import '../data/profile_repository.dart';

/// The badges whose light has already passed over them on this phone (KV
/// [ProfileRepository.badgesSweptKey]; wiped with the account).
final sweptBadgesProvider = FutureProvider<Set<String>>((ref) async {
  final raw = await ref.watch(kvStoreProvider).read(ProfileRepository.badgesSweptKey);
  if (raw == null) return <String>{};
  try {
    return {for (final k in jsonDecode(raw) as List) '$k'};
  } on Object {
    return <String>{};
  }
});

String _sweepKey(Badge b) => '${b.kind.name}:${b.refKey}';

/// Earned medals catch one light sweep the first time this phone shows them (gold: earned), then
/// never again. A list screen asks once, when the badges and the swept set are both known, and
/// keeps the answer for its life; the KV set is updated at once.
mixin BadgeSweepLatch<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Set<String>? _sweep;

  /// Whether [b] sweeps on this screen (false until the swept set is read).
  bool sweeps(Badge b) => _sweep?.contains(_sweepKey(b)) ?? false;

  /// Call from build with the badges on screen.
  void latchSweep(List<Badge> badges) {
    if (_sweep != null) return;
    final swept = ref.watch(sweptBadgesProvider).valueOrNull;
    if (swept == null) return;
    _sweep = {for (final b in badges) if (!swept.contains(_sweepKey(b))) _sweepKey(b)};
    if (_sweep!.isEmpty) return;
    final all = [...swept, ..._sweep!];
    // The newest few hundred are plenty: older badges have long had their moment.
    final kept = all.length > 300 ? all.sublist(all.length - 300) : all;
    ref.read(kvStoreProvider).write(ProfileRepository.badgesSweptKey, jsonEncode(kept)).ignore();
  }
}

/// The icon a badge's medal carries: league marks, tournament trophies, the streak flame, the level.
YqIcons badgeIcon(BadgeKind k) => switch (k) {
      BadgeKind.streak => YqIcons.streak,
      BadgeKind.level => YqIcons.badge,
      BadgeKind.tournamentPodium || BadgeKind.tournamentTop10 || BadgeKind.tournamentFinisher => YqIcons.trophy,
      _ => YqIcons.league,
    };

/// An earned badge as a medal: a cream disc with a gold rim and a gold mark, its label (and date)
/// underneath. Gold is earned here — the medal is achievement styling and nothing else on Profile is.
class BadgeMedal extends StatelessWidget {
  const BadgeMedal({
    super.key,
    required this.badge,
    this.size = 56,
    this.showDate = false,
    this.width = 88,
    this.sweep = false,
    this.sweepDelay = Duration.zero,
  });
  final Badge badge;
  final double size;
  final bool showDate;
  final double width;

  /// One gold light passes over the medal (its first time on this phone), after [sweepDelay].
  final bool sweep;
  final Duration sweepDelay;

  /// How far apart neighbouring medals catch the light.
  static const sweepStep = Duration(milliseconds: 90);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final label = badgeLabel(badge, t, locale);
    final date = YqFormat.fullDate(badge.awardedAt.toLocal(), locale);
    return Semantics(
      container: true,
      label: t.badgeSemantics(label, date),
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YqSheen(
              play: sweep,
              circle: true,
              color: YqColors.white,
              opacity: 0.85,
              delay: sweepDelay,
              child: Container(
                key: const ValueKey('badge-medal'),
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient:
                      const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [YqColors.cream, YqColors.sand]),
                  border: Border.all(color: YqColors.gold, width: 2),
                  boxShadow: [
                    BoxShadow(color: YqColors.gold.withValues(alpha: 0.25), blurRadius: 14, spreadRadius: -6, offset: const Offset(0, 6)),
                  ],
                ),
                child: YqIcon(badgeIcon(badge.kind), size: size * 0.46, tone: YqIconTone.gold),
              ),
            ),
            const SizedBox(height: YqSpace.s),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, height: 1.35, fontWeight: FontWeight.w700, color: YqColors.goldText),
            ),
            if (showDate)
              Text(date, maxLines: 1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: YqColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// «الشارات» on the Profile tab: the newest earned medals in one lazy horizontal row, «الكل» →
/// `/profile/badges`. The only gold block on the tab.
class BadgesStrip extends ConsumerStatefulWidget {
  const BadgesStrip({super.key, required this.badges, required this.count});
  final List<Badge> badges;
  final int count;

  static const height = 124.0;

  @override
  ConsumerState<BadgesStrip> createState() => _BadgesStripState();
}

class _BadgesStripState extends ConsumerState<BadgesStrip> with BadgeSweepLatch {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final badges = widget.badges;
    final count = widget.count;
    latchSweep(badges);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YqHeading(
          t.pfBadges,
          action: count > 0 || badges.isNotEmpty
              ? TextButton(onPressed: () => context.push('/profile/badges'), child: Text(t.pfBadgesAll))
              : null,
        ),
        if (badges.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: YqSpace.s),
            child: Text(t.pfBadgesEmpty, style: const TextStyle(fontSize: 13, height: 1.5, color: YqColors.muted)),
          )
        else
          SizedBox(
            height: BadgesStrip.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: badges.length,
              separatorBuilder: (_, __) => const SizedBox(width: YqSpace.s),
              itemBuilder: (context, i) => BadgeMedal(
                badge: badges[i],
                sweep: sweeps(badges[i]),
                sweepDelay: BadgeMedal.sweepStep * i.clamp(0, 6),
              ),
            ),
          ),
      ],
    );
  }
}
