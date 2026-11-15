import 'dart:convert';

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/motion.dart';
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
/// [ProfileRepository.badgesSweptKey]; wiped with the account, when the session also drops this
/// cache). [SweptBadges.markSwept] updates the cached set and the KV together, so a second list
/// in the same run (the strip, then «الكل») never sweeps the same medals again.
final sweptBadgesProvider = AsyncNotifierProvider<SweptBadges, Set<String>>(SweptBadges.new);

class SweptBadges extends AsyncNotifier<Set<String>> {
  /// The newest few hundred are plenty: older badges have long had their moment.
  static const keep = 300;

  @override
  Future<Set<String>> build() async {
    final raw = await ref.watch(kvStoreProvider).read(ProfileRepository.badgesSweptKey);
    if (raw == null) return <String>{};
    try {
      return {for (final k in jsonDecode(raw) as List) '$k'};
    } on Object {
      return <String>{};
    }
  }

  /// Records [keys] as swept: the cached set at once, the KV in the background.
  void markSwept(Iterable<String> keys) {
    final current = state.valueOrNull;
    if (current == null) return;
    final added = [
      for (final k in keys)
        if (!current.contains(k)) k,
    ];
    if (added.isEmpty) return;
    final all = [...current, ...added];
    final kept = all.length > keep ? all.sublist(all.length - keep) : all;
    state = AsyncData(kept.toSet());
    ref.read(kvStoreProvider).write(ProfileRepository.badgesSweptKey, jsonEncode(kept)).ignore();
  }
}

/// The key a badge's sweep is remembered by (on this phone and per screen).
String badgeSweepKey(Badge b) => '${b.kind.name}:${b.refKey}';

/// Earned medals catch one light sweep the first time this phone shows them (gold: earned), then
/// never again. A list screen asks once, when the badges and the swept set are both known, and
/// keeps the answer for its life; the swept set is updated right after the frame. Wrap the medals
/// in a `YqMotionMemo(memo: sweepMemo)`: a medal rebuilt after scrolling away (a lazy list) has
/// already had its light and stays still.
mixin BadgeSweepLatch<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Set<String>? _sweep;

  /// Which medals already played their sweep on this screen.
  final MotionMemo sweepMemo = MotionMemo();

  /// Whether [b] sweeps on this screen (false until the swept set is read).
  bool sweeps(Badge b) => _sweep?.contains(badgeSweepKey(b)) ?? false;

  /// Call from build with the badges on screen.
  void latchSweep(List<Badge> badges) {
    if (_sweep != null) return;
    final swept = ref.watch(sweptBadgesProvider).valueOrNull;
    if (swept == null) return;
    final fresh = {
      for (final b in badges)
        if (!swept.contains(badgeSweepKey(b))) badgeSweepKey(b),
    };
    _sweep = fresh;
    if (fresh.isEmpty) return;
    // Providers cannot change while widgets build: record it right after this frame.
    Future.microtask(() {
      if (mounted) ref.read(sweptBadgesProvider.notifier).markSwept(fresh);
    });
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
            _MedalSweep(
              sweep: sweep,
              sweepKey: badgeSweepKey(badge),
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

/// The medal's one light, decided once for this element: it plays when [sweep] is (or turns)
/// true and the screen's memo has not played this medal yet, and keeps that answer for its life.
class _MedalSweep extends StatefulWidget {
  const _MedalSweep({required this.sweep, required this.sweepKey, required this.delay, required this.child});
  final bool sweep;
  final String sweepKey;
  final Duration delay;
  final Widget child;

  @override
  State<_MedalSweep> createState() => _MedalSweepState();
}

class _MedalSweepState extends State<_MedalSweep> {
  bool _play = false;
  bool _decided = false;

  void _decide() {
    if (_decided || !widget.sweep) return;
    _decided = true;
    _play = YqMotionMemo.firstTime(context, 'badge-sweep:${widget.sweepKey}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _decide();
  }

  @override
  void didUpdateWidget(_MedalSweep old) {
    super.didUpdateWidget(old);
    _decide();
  }

  @override
  Widget build(BuildContext context) =>
      YqSheen(play: _play, circle: true, color: YqColors.white, opacity: 0.85, delay: widget.delay, child: widget.child);
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
            // Medals scrolled back into view have had their light (the memo outlives the items).
            child: YqMotionMemo(
              memo: sweepMemo,
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
          ),
      ],
    );
  }
}
