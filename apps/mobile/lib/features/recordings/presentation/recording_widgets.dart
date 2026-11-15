import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_once.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../quran/domain/quran_data.dart';
import '../data/recording_drafts.dart';
import '../data/recordings_repository.dart';
import '../domain/recording_models.dart';

/// Shared pieces of the «تلاواتي» screens. Palette: porcelain, ink, muted, lapis as the only
/// accent — never red, never gold (gold is for achievement only).

/// «سورة الفاتحة · الآيات 1–4» / "Al-Fatihah · Ayat 1–4" with Western digits (contracts `verseRef`).
String verseRefOf(AppLocalizations t, QuranData q, String locale, int surah, int from, int to) {
  final s = q.surah(surah.clamp(1, QuranData.surahCount));
  final name = locale == 'ar' ? s.nameAr : s.nameEn;
  return from == to ? t.recVerseRefOne(name, YqFormat.number(from)) : t.recVerseRef(name, YqFormat.number(from), YqFormat.number(to));
}

/// The verse reference once the mushaf is parsed (a short shaped line until then).
class VerseRefText extends ConsumerWidget {
  const VerseRefText({super.key, required this.surah, required this.from, required this.to, this.style, this.maxLines = 2});
  final int surah;
  final int from;
  final int to;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(quranDataProvider).valueOrNull;
    if (q == null) return const YqSkeleton(child: YqSkeletonBox(width: 140, height: 14, radius: YqRadii.pill));
    final t = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return Text(verseRefOf(t, q, locale, surah, from, to), maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
  }
}

/// «12 ث».
String secondsText(AppLocalizations t, int ms) => t.recSeconds(YqFormat.number((ms / 1000).round().clamp(1, 99)));

String visibilityLabel(AppLocalizations t, RecordingVisibility v) => switch (v) {
      RecordingVisibility.private => t.recVisPrivate,
      RecordingVisibility.members => t.recVisMembers,
      RecordingVisibility.public => t.recVisPublic,
    };

String visibilityHint(AppLocalizations t, RecordingVisibility v) => switch (v) {
      RecordingVisibility.private => t.recVisPrivateHint,
      RecordingVisibility.members => t.recVisMembersHint,
      RecordingVisibility.public => t.recVisPublicHint,
    };

String reactionLabel(AppLocalizations t, ReactionKind k) => switch (k) {
      ReactionKind.mashallah => t.recReactMashallah,
      ReactionKind.barakallah => t.recReactBarakallah,
      ReactionKind.ahsant => t.recReactAhsant,
    };

/// The owner's status line (APP_SPEC §5.24 copy).
String statusText(AppLocalizations t, Recording r) => switch (r.status) {
      RecordingStatus.privateReady => t.recStatusPrivate,
      RecordingStatus.processing => t.recStatusProcessing,
      RecordingStatus.approved => r.shared ? t.recStatusApproved : t.recStatusPrivate,
      RecordingStatus.needsReview => t.recStatusReview,
      RecordingStatus.removed => t.recRejectRemoved,
      RecordingStatus.rejected => switch (r.rejectReason) {
          RejectReason.notMatching || null => t.recRejectNotMatching,
          RejectReason.unclear => t.recRejectUnclear,
          RejectReason.silence => t.recRejectSilence,
          RejectReason.tooLong => t.recRejectTooLong(YqFormat.number(kRecordingMaxMs ~/ 1000)),
          RejectReason.removedByModerator => t.recRejectRemoved,
        },
    };

String draftText(AppLocalizations t, RecordingDraft d, {required bool signedIn}) => switch (d.state) {
      DraftState.local => signedIn ? t.recDraftLocal : t.recDraftSignIn,
      DraftState.queued => t.recDraftQueued,
      DraftState.failed => d.failure == null ? t.recDraftFailed : '${t.recDraftFailed} · ${failureText(t, d.failure!)}',
    };

/// One line for any refused call (stable codes → copy; never a raw code on screen).
String failureText(AppLocalizations t, RecordingFailure f, {String? problem}) => switch (f) {
      RecordingFailure.tooLong => t.recRejectTooLong(YqFormat.number(kRecordingMaxMs ~/ 1000)),
      RecordingFailure.tooLarge => t.recErrTooLarge,
      RecordingFailure.badFormat => t.recErrBadFormat,
      RecordingFailure.invalidRange => t.recErrInvalidRange,
      RecordingFailure.limit => t.recErrLimit(YqFormat.number(kProfileRecordingsMax)),
      RecordingFailure.dailyLimit => t.recDailyLimit,
      RecordingFailure.notPublic => t.recErrNotPublic,
      RecordingFailure.attestationRequired => t.recErrAttest,
      RecordingFailure.communityRequired => t.recErrCommunity,
      RecordingFailure.communityBanned => t.recGateBanned,
      RecordingFailure.accountRequired => t.recErrAccount,
      RecordingFailure.commentsOff => t.recCommentsOffNote,
      RecordingFailure.commentRejected => '${t.recCommentRejected}${commentProblem(t, problem) == null ? '' : ' · ${commentProblem(t, problem)}'}',
      RecordingFailure.commentRateLimited => t.recCommentRate,
      RecordingFailure.blocked => t.recErrBlocked,
      RecordingFailure.ownRecording => t.recErrOwn,
      RecordingFailure.rateLimited => t.recErrRate,
      RecordingFailure.featureOff => t.recErrFeatureOff,
      RecordingFailure.notFound => t.recErrGone,
      RecordingFailure.offline => t.recErrOffline,
      RecordingFailure.unknown => t.errorGeneric,
    };

/// `comment_rejected`'s reason (server `details.problem`).
String? commentProblem(AppLocalizations t, String? problem) => switch (problem) {
      'link' => t.recCommentWhyLink,
      'phone' => t.recCommentWhyPhone,
      'blocked_word' => t.recCommentWhyWord,
      'mention' => t.recCommentWhyMention,
      'too_short' => t.recCommentWhyShort,
      'too_long' => t.recCommentWhyLong(YqFormat.number(kCommentMax)),
      'invalid_chars' => t.recCommentWhyChars,
      _ => null,
    };

String failureOf(AppLocalizations t, Object e) {
  final r = RecordingException.from(e);
  return failureText(t, r.failure, problem: r.problem);
}

/// A quiet pill: the visibility («خاصة» · «للأعضاء» · «عامة»).
class VisibilityChip extends StatelessWidget {
  const VisibilityChip(this.visibility, {super.key});
  final RecordingVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final shared = visibility != RecordingVisibility.private;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: YqSpace.s, vertical: 2),
      decoration: BoxDecoration(
        color: shared ? YqColors.lapis.withValues(alpha: 0.08) : YqColors.ice,
        borderRadius: BorderRadius.circular(YqRadii.pill),
      ),
      child: Text(
        visibilityLabel(t, visibility),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: shared ? YqColors.lapis : YqColors.muted),
      ),
    );
  }
}

/// The owner's status: a breathing lapis dot while the AI check runs (a few breaths, then lit),
/// muted ink otherwise — never red.
class RecordingStatusLine extends StatelessWidget {
  const RecordingStatusLine(this.recording, {super.key});
  final Recording recording;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final r = recording;
    final text = statusText(t, r);
    final pending = r.pending;
    final good = r.status == RecordingStatus.approved && r.shared;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending) ...[const YqBreathingDot(size: 6), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text,
            key: ValueKey('rec-status-${r.status.code}'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, height: 1.4, color: good || pending ? YqColors.lapis : YqColors.muted, fontWeight: good ? FontWeight.w600 : FontWeight.w400),
          ),
        ),
      ],
    );
  }
}

/// «ما شاء الله 4 · بارك الله فيك 2» — read-only counts (only the kinds someone used).
class ReactionSummary extends StatelessWidget {
  const ReactionSummary({super.key, required this.reactions, required this.comments});
  final ReactionCounts reactions;
  final int comments;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final parts = [
      for (final k in ReactionKind.values)
        if (reactions.of(k) > 0) '${reactionLabel(t, k)} ${YqFormat.number(reactions.of(k))}',
      if (comments > 0) t.recCommentsCount(YqFormat.number(comments)),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: YqColors.muted, height: 1.5));
  }
}

/// A muted inline note (never red): a refusal, a too-short take.
class InlineNote extends StatelessWidget {
  const InlineNote(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: YqSpace.xs),
        child: Semantics(liveRegion: true, child: Text(message, style: const TextStyle(fontSize: 13, color: YqColors.ink, fontWeight: FontWeight.w500, height: 1.5))),
      );
}
