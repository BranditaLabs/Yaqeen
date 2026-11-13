import 'package:flutter/material.dart' hide Badge;
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../community/domain/community_models.dart';
import '../../community/presentation/badge_label.dart';

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
  const BadgeMedal({super.key, required this.badge, this.size = 56, this.showDate = false, this.width = 88});
  final Badge badge;
  final double size;
  final bool showDate;
  final double width;

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
            Container(
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
class BadgesStrip extends StatelessWidget {
  const BadgesStrip({super.key, required this.badges, required this.count});
  final List<Badge> badges;
  final int count;

  static const height = 124.0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: badges.length,
              separatorBuilder: (_, __) => const SizedBox(width: YqSpace.s),
              itemBuilder: (context, i) => BadgeMedal(badge: badges[i]),
            ),
          ),
      ],
    );
  }
}
