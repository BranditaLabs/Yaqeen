import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../core/time/zoned.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../profile/domain/level.dart';
import '../domain/community_models.dart';

/// Shared pieces of the community screens (APP_SPEC §5.31, design §6.6–6.10). Palette: porcelain,
/// ink, muted, lapis as the only accent; gold only on earned badges and closed-period podiums.

const cairo = 'Africa/Cairo';

/// Today's Cairo calendar day (leagues and tournaments run on whole Cairo days).
DateTime cairoToday(DateTime now) => Zoned.today(cairo, now);

/// The Cairo calendar day of an instant (a period boundary is a Cairo midnight).
DateTime cairoDay(DateTime instant) {
  final l = Zoned.local(instant.toUtc(), cairo);
  return DateTime(l.year, l.month, l.day);
}

/// Whole days left before a period that ends at the Cairo midnight [endsAt]: 0 on its last day
/// («ينتهي الليلة»), 1 the day before («غداً»).
int daysLeft(DateTime endsAt, DateTime now) => Zoned.daysBetween(cairoToday(now), cairoDay(endsAt)) - 1;

/// The website terms, at the competitions section («شروط المنافسات»).
Uri communityTermsUri(String locale) => Env.site('terms', locale).replace(fragment: 'community');

/// contracts `DisplayName`: 1–40 characters, no links, control, bidi or zero-width characters.
/// The server also checks reserved and brand names (`invalid_name`).
bool isValidDisplayName(String name) {
  final t = name.trim();
  if (t.isEmpty || t.characters.length > 40) return false;
  return !RegExp('https?:|www\\.|[\\u0000-\\u001f\\u007f\\u200b-\\u200f\\u202a-\\u202e\\u2066-\\u2069\\ufeff]', caseSensitive: false)
      .hasMatch(t);
}

/// The inline message for a failed join / report / block.
String communityFailureText(AppLocalizations t, CommunityFailure f) => switch (f) {
      CommunityFailure.offline => t.cmNeedsConnection,
      CommunityFailure.attestationRequired => t.cmErrAttestation,
      CommunityFailure.nameRequired => t.cmErrNameRequired,
      CommunityFailure.invalidName => t.cmErrInvalidName,
      CommunityFailure.nameLocked => t.cmErrNameLocked,
      CommunityFailure.communityBanned => t.cmBanned,
      CommunityFailure.featureOff => t.cmFeatureOff,
      CommunityFailure.tournamentNotOpen => t.cmErrTournamentNotOpen,
      CommunityFailure.ackRequired => t.cmErrAck,
      CommunityFailure.accountRequired => t.cmGuest,
      CommunityFailure.countryUnknown => t.cmCountryUnknown,
      CommunityFailure.countryTooSmall => t.cmCountryTooSmall,
      CommunityFailure.rateLimited => t.cmReportLimit,
      _ => t.cmErrGeneric,
    };

/// A competitor's public name: the name, else «@handle»; support-hidden → «عضو يقين».
String competitorName(PublicCompetitor c, AppLocalizations t) {
  final n = c.name?.trim();
  if (n != null && n.isNotEmpty) return n;
  return t.avHiddenName;
}

String levelNameOf(int level, String locale) {
  final l = cardLevels[(level - 1).clamp(0, cardLevels.length - 1)];
  return locale == 'ar' ? l.$2 : l.$3;
}

/// «—» for a rank or points that are null (before the first snapshot) or 0.
String rankText(int? rank, AppLocalizations t) => rank == null ? t.cmNoValue : YqFormat.number(rank);
String pointsText(int? points, AppLocalizations t) => points == null || points <= 0 ? t.cmNoValue : YqFormat.number(points);

/// One person in a public list: rank · avatar in their (snapshot) level ring · name · points (or
/// the level name on the level board). The caller's own row is tinted lapis and says «أنت».
/// Long-press another person's row → report/block.
class CompetitorRow extends StatelessWidget {
  const CompetitorRow({
    super.key,
    required this.competitor,
    this.showPoints = true,
    this.podium = false,
    this.onLongPress,
  });

  final PublicCompetitor competitor;

  /// False on the level board: the level name instead of points.
  final bool showPoints;

  /// A closed period: ranks 1–3 get a gold mark (achievement).
  final bool podium;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context).languageCode;
    final c = competitor;
    final name = competitorName(c, t);
    final rank = rankText(c.rank, t);
    final gold = podium && c.rank != null && c.rank! <= 3;
    final level = levelNameOf(c.level.level, locale);
    final trailing = showPoints ? pointsText(c.points, t) : null;
    final semantics = [
      rank,
      name,
      '@${c.handle}',
      if (c.me) t.cmYou,
      if (trailing != null) trailing else level,
    ].join('، ');
    final row = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: YqSpace.m, vertical: YqSpace.s),
      decoration: BoxDecoration(
        color: c.me ? YqColors.lapis.withValues(alpha: 0.06) : null,
        borderRadius: BorderRadius.circular(YqRadii.chip),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: gold
                ? Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: YqColors.gold, width: 1.5)),
                    child: Text(rank, style: YqText.numeral.copyWith(fontSize: 13, color: YqColors.goldText, fontWeight: FontWeight.w600)),
                  )
                : Text(
                    rank,
                    textAlign: TextAlign.center,
                    style: YqText.numeral.copyWith(fontSize: 15, color: YqColors.muted, fontWeight: FontWeight.w400),
                  ),
          ),
          const SizedBox(width: YqSpace.s),
          YqLevelAvatar(avatar: c.avatar, level: c.level.level, progress: c.level.progress, size: 36, stroke: 2, name: name),
          const SizedBox(width: YqSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: c.name == null ? YqColors.muted : YqColors.ink),
                      ),
                    ),
                    if (c.me) ...[
                      const SizedBox(width: YqSpace.s),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: YqSpace.s, vertical: 1),
                        decoration: BoxDecoration(
                          color: YqColors.lapis.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(YqRadii.pill),
                        ),
                        child: Text(t.cmYou, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: YqColors.lapis)),
                      ),
                    ],
                  ],
                ),
                Text(
                  showPoints ? '@${c.handle}' : level,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: showPoints ? TextDirection.ltr : null,
                  textAlign: TextAlign.start,
                  style: text.bodySmall?.copyWith(fontSize: 11.5, color: YqColors.muted),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: YqSpace.s),
            // Implicit only: a new snapshot slides the number, never a live ticker.
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : YqMotion.base,
              child: Text(
                trailing,
                key: ValueKey(trailing),
                style: YqText.numeral.copyWith(fontSize: 16, color: YqColors.ink, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      label: semantics,
      excludeSemantics: true,
      onLongPress: onLongPress,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onLongPress: onLongPress, child: row),
    );
  }
}

/// A quiet separator inside a league list: «يصعدون إلى {next}» / «يبدأون الأسبوع القادم في {prev}».
/// Muted, never red.
class ZoneLabel extends StatelessWidget {
  const ZoneLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: YqSpace.s),
        child: Row(
          children: [
            const Expanded(child: Divider(color: YqColors.line, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.m),
              child: Text(label, style: const TextStyle(fontSize: 12, color: YqColors.muted, fontWeight: FontWeight.w500)),
            ),
            const Expanded(child: Divider(color: YqColors.line, height: 1)),
          ],
        ),
      );
}

/// «يُحدَّث الترتيب كل ليلة.» under every standings list.
class SnapshotLine extends StatelessWidget {
  const SnapshotLine({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
        child: Text(
          AppLocalizations.of(context).cmSnapshotLine,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: YqColors.muted),
        ),
      );
}

/// «شروط المنافسات» — opens the website terms at #community.
class CommunityTermsLink extends ConsumerWidget {
  const CommunityTermsLink({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: YqButton.text(
        label: t.cmTerms,
        onPressed: () => ref.read(deviceServicesProvider).openUrl(communityTermsUri(locale)),
      ),
    );
  }
}

/// The sincerity + privacy lines and the terms link closing every competition screen.
class CommunityFooter extends StatelessWidget {
  const CommunityFooter({super.key, this.sincerity = true});
  final bool sincerity;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    const style = TextStyle(fontSize: 12.5, height: 1.6, color: YqColors.muted);
    return Padding(
      padding: const EdgeInsets.only(top: YqSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sincerity) ...[Text(t.cmSincerity, style: style), const SizedBox(height: YqSpace.s)],
          Text(t.cmPrivacy, style: style),
          const CommunityTermsLink(),
        ],
      ),
    );
  }
}

/// A glass note with an icon, a line and an optional action (guest, banned, closing, explainers).
class CommunityNote extends StatelessWidget {
  const CommunityNote({super.key, required this.icon, required this.title, this.body, this.actionLabel, this.onAction, this.busy = false});

  final YqIcons icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LiquidGlass(
      padding: const EdgeInsets.all(YqSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              YqIcon(icon, size: 26, tone: YqIconTone.active),
              const SizedBox(width: YqSpace.m),
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: YqSpace.s),
            Text(body!, style: text.bodyMedium?.copyWith(color: YqColors.muted, height: 1.6)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: YqSpace.l),
            YqButton(label: actionLabel!, loading: busy, onPressed: busy ? null : onAction),
          ],
        ],
      ),
    );
  }
}

/// The required switch «عمري 18 عاماً أو أكثر، أو لديّ موافقة وليّ أمري».
class AttestSwitch extends StatelessWidget {
  const AttestSwitch({super.key, required this.value, required this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Defaults to the attestation; the tournament acknowledgement reuses the row.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final l = label ?? AppLocalizations.of(context).cmAttest;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(YqRadii.chip),
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: YqSpace.touch),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: YqSpace.s),
            child: Row(
              children: [
                Expanded(child: Text(l, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5))),
                const SizedBox(width: YqSpace.m),
                YqSwitch(value: value, onChanged: onChanged, label: l),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An inline failure line (muted ink, never red: these are gentle screens).
class InlineFailure extends StatelessWidget {
  const InlineFailure(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: YqMotion.fast,
        child: message == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: YqSpace.s),
                child: Semantics(
                  liveRegion: true,
                  child: Text(message!, style: const TextStyle(fontSize: 13, color: YqColors.ink, fontWeight: FontWeight.w500)),
                ),
              ),
      );
}

/// Loading rows inside one shimmer (never a spinner).
class CompetitorSkeleton extends StatelessWidget {
  const CompetitorSkeleton({super.key, this.rows = 8});
  final int rows;

  @override
  Widget build(BuildContext context) => YqSkeleton(child: YqSkeletonAvatarRows(rows: rows));
}

/// A stage moment with a muted (not gold) eyebrow: division names stay monochrome.
class CommunityMoment extends StatelessWidget {
  const CommunityMoment({super.key, this.eyebrow, required this.value, this.caption});
  final String? eyebrow;
  final Widget value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        if (eyebrow != null)
          Text(
            eyebrow!,
            textAlign: TextAlign.center,
            style: text.labelSmall?.copyWith(color: YqColors.ink, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6),
          ),
        const SizedBox(height: 2),
        value,
        if (caption != null) ...[
          const SizedBox(height: YqSpace.xs),
          Text(caption!, textAlign: TextAlign.center, style: text.bodySmall?.copyWith(fontSize: 13)),
        ],
      ],
    );
  }
}
