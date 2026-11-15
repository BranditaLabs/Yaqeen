import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/motion.dart';
import '../../../core/di/providers.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_count.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_play_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../community/data/community_repository.dart';
import '../../community/domain/community_models.dart';
import '../../community/presentation/community_providers.dart';
import '../../community/presentation/community_widgets.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../../quran/domain/passage.dart';
import '../data/recordings_repository.dart';
import '../domain/recording_models.dart';
import 'recording_widgets.dart';
import 'recordings_providers.dart';
import 'share_gate.dart';
import 'verse_words_view.dart';

/// What the listener plays: the owner's own recording or a member's shared one.
class ListenTarget {
  const ListenTarget({
    required this.id,
    required this.surah,
    required this.fromAyah,
    required this.toAyah,
    required this.durationMs,
    required this.audioPath,
    required this.words,
    required this.reactions,
    required this.myReaction,
    required this.commentsOn,
    required this.commentCount,
    required this.mine,
    required this.social,
    this.owner,
    this.ownList = false,
  });

  factory ListenTarget.own(Recording r, {List<RecordingWord>? localWords}) => ListenTarget(
        id: r.id,
        surah: r.surah,
        fromAyah: r.fromAyah,
        toAyah: r.toAyah,
        durationMs: r.durationMs,
        audioPath: r.audioPath,
        words: r.words ?? localWords,
        reactions: r.reactions,
        myReaction: null,
        commentsOn: r.commentsOn,
        commentCount: r.commentCount,
        mine: true,
        // Reactions and comments exist only where members can hear it.
        social: r.live,
        ownList: true,
      );

  factory ListenTarget.member(PublicRecording r) => ListenTarget(
        id: r.id,
        surah: r.surah,
        fromAyah: r.fromAyah,
        toAyah: r.toAyah,
        durationMs: r.durationMs,
        audioPath: r.audioPath,
        words: r.words,
        reactions: r.reactions,
        myReaction: r.myReaction,
        commentsOn: r.commentsOn,
        commentCount: r.commentCount,
        mine: r.mine,
        social: true,
        owner: r.owner,
      );

  final String id;
  final int surah;
  final int fromAyah;
  final int toAyah;
  final int durationMs;
  final String audioPath;
  final List<RecordingWord>? words;
  final ReactionCounts reactions;
  final ReactionKind? myReaction;
  final bool commentsOn;
  final int commentCount;
  final bool mine;
  final bool social;
  final PublicCompetitor? owner;

  /// Opened from the owner's own list: its audio is cached on this phone (a member's recording is
  /// fetched for the listen only, `RecordingsRepository.memberAudioFile`).
  final bool ownList;

  String get playKey => 'rec/$id';

  Future<File> audio(RecordingsRepository repo) => ownList ? repo.audioFile(id, audioPath) : repo.memberAudioFile(id, audioPath);
}

/// How the listener's parts report a refused call: true when a gate (sign-in, the community join)
/// was passed and the action is worth trying again — the caller retries once its own busy flag is
/// clear (a retry from inside the failing call would be swallowed by that flag).
typedef RecordingFailureHandler = Future<bool> Function(RecordingException e);

/// Opens the listener (APP_SPEC §5.31.6): the verses in the mushaf font with the word-by-word
/// highlight following the `words` timings, `YqPlayRing`, the three reactions and the comments.
/// The clip stops when the sheet closes. [onChanged] hears new reaction counts (lists refresh).
Future<void> showRecordingListener(BuildContext context, ListenTarget target, {ValueChanged<ReactionState>? onChanged}) async {
  final container = ProviderScope.containerOf(context);
  await showYqSheet<void>(context, builder: (_) => ListenerSheet(target: target, onChanged: onChanged));
  await container.read(recordingPlayerProvider.notifier).stop(target.playKey);
  // A member's clip was fetched for this listen only.
  if (!target.ownList) container.read(recordingsRepositoryProvider).clearListened().ignore();
}

class ListenerSheet extends ConsumerStatefulWidget {
  const ListenerSheet({super.key, required this.target, this.onChanged});
  final ListenTarget target;
  final ValueChanged<ReactionState>? onChanged;

  @override
  ConsumerState<ListenerSheet> createState() => _ListenerSheetState();
}

class _ListenerSheetState extends ConsumerState<ListenerSheet> {
  late ReactionCounts _counts = widget.target.reactions;
  late ReactionKind? _mine = widget.target.myReaction;
  late bool _commentsOn = widget.target.commentsOn;
  bool _reacting = false;
  int _pops = 0;
  ReactionKind? _popped;

  ListenTarget get _t => widget.target;

  Future<void> _toggle() async {
    final t = AppLocalizations.of(context);
    final repo = ref.read(recordingsRepositoryProvider);
    await ref.read(recordingPlayerProvider.notifier).toggle(_t.playKey, () => _t.audio(repo), title: t.recTitle);
    final s = ref.read(recordingPlayerProvider);
    if (s.failed && mounted) YqToast.show(context, t.errorGeneric);
  }

  Future<void> _react(ReactionKind k) async {
    if (_t.mine || _reacting) return;
    final before = (_counts, _mine);
    final removing = _mine == k;
    // Shown at once: one reaction per member — tapping it again takes it back.
    setState(() {
      _reacting = true;
      _counts = _adjust(_counts, _mine, removing ? null : k);
      _mine = removing ? null : k;
      _popped = removing ? null : k;
      _pops++;
    });
    HapticFeedback.selectionClick().ignore();
    final repo = ref.read(recordingsRepositoryProvider);
    RecordingException? failed;
    try {
      final s = removing ? await repo.unreact(_t.id) : await repo.react(_t.id, k);
      if (!mounted) return;
      setState(() {
        _counts = s.reactions;
        _mine = s.myReaction;
      });
      widget.onChanged?.call(s);
    } on RecordingException catch (e) {
      failed = e;
      if (mounted) {
        setState(() {
          _counts = before.$1;
          _mine = before.$2;
        });
      }
    } finally {
      if (mounted) setState(() => _reacting = false);
    }
    // Explained (and retried after a passed gate) once this reaction is no longer in flight.
    if (failed != null && mounted && await _explain(failed) && mounted) await _react(k);
  }

  static ReactionCounts _adjust(ReactionCounts c, ReactionKind? from, ReactionKind? to) {
    int v(ReactionKind k) => c.of(k) - (from == k ? 1 : 0) + (to == k ? 1 : 0);
    return ReactionCounts(
      mashallah: v(ReactionKind.mashallah).clamp(0, 1 << 30),
      barakallah: v(ReactionKind.barakallah).clamp(0, 1 << 30),
      ahsant: v(ReactionKind.ahsant).clamp(0, 1 << 30),
    );
  }

  /// A refused action: the gates open their sheets (true when passed: the caller tries again),
  /// anything else is one quiet line.
  Future<bool> _explain(RecordingException e) async {
    final t = AppLocalizations.of(context);
    if (e.failure == RecordingFailure.accountRequired) {
      return await showSignInSheet(context) && mounted;
    }
    if (isShareGate(e.failure)) {
      return await showShareGate(context) && mounted;
    }
    if (e.failure == RecordingFailure.notFound && mounted) {
      YqToast.show(context, t.recErrGone);
      Navigator.of(context).maybePop();
      return false;
    }
    if (mounted) YqToast.show(context, failureText(t, e.failure, problem: e.problem));
    return false;
  }

  Future<void> _setCommentsOn(bool on) async {
    final t = AppLocalizations.of(context);
    final mine = ref.read(myRecordingsProvider).valueOrNull?.items.where((r) => r.id == _t.id).firstOrNull;
    setState(() => _commentsOn = on);
    ref.read(commentsProvider(_t.id).notifier).setCommentsOn(on);
    try {
      if (mine != null) {
        await ref.read(myRecordingsProvider.notifier).setComments(mine, on);
      } else {
        await ref.read(recordingsRepositoryProvider).patch(_t.id, commentsOn: on);
      }
    } on RecordingException catch (e) {
      if (!mounted) return;
      setState(() => _commentsOn = !on);
      ref.read(commentsProvider(_t.id).notifier).setCommentsOn(!on);
      YqToast.show(context, failureText(t, e.failure));
    }
  }

  Future<void> _ownerMenu() async {
    final t = AppLocalizations.of(context);
    final owner = _t.owner;
    if (_t.mine) {
      await showYqSheet<void>(
        context,
        builder: (sheet) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YqListRow(
              key: const ValueKey('rec-comments-toggle'),
              title: _commentsOn ? t.recCommentsTurnOff : t.recCommentsTurnOn,
              onTap: () {
                Navigator.of(sheet).pop();
                _setCommentsOn(!_commentsOn);
              },
            ),
          ],
        ),
      );
      return;
    }
    if (owner == null) return;
    await showRecordingReportSheet(
      context,
      recordingId: _t.id,
      owner: owner,
      onBlocked: () {
        if (mounted) Navigator.of(context).maybePop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final quran = ref.watch(quranDataProvider).valueOrNull;
    final play = ref.watch(recordingPlayerProvider);
    final mine = play.isOf(_t.playKey);
    final words = _t.words;
    final owner = _t.owner;
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final ayat = quran == null ? const [] : Passage(_t.surah, _t.fromAyah, _t.toAyah.clamp(_t.fromAyah, 286)).expected(quran);
    final current = mine ? Karaoke.currentAt(words, play.position) : null;

    final header = Row(
      children: [
        if (owner != null) ...[
          YqLevelAvatar(avatar: owner.avatar, level: owner.level.level, progress: owner.level.progress, size: 40, stroke: 2, name: competitorName(owner, t)),
          const SizedBox(width: YqSpace.m),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(owner == null ? t.recTitle : t.recListenerTitle(competitorName(owner, t)), style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              VerseRefText(surah: _t.surah, from: _t.fromAyah, to: _t.toAyah, style: const TextStyle(color: YqColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        if (_t.social)
          IconButton(
            key: const ValueKey('rec-listener-menu'),
            tooltip: t.recMenu,
            onPressed: _ownerMenu,
            icon: const Icon(Icons.more_horiz_rounded, color: YqColors.muted),
          ),
      ],
    );

    final slivers = <Widget>[
      SliverToBoxAdapter(child: header),
      const SliverToBoxAdapter(child: SizedBox(height: YqSpace.m)),
      SliverToBoxAdapter(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            child: ayat.isEmpty
                ? const YqSkeleton(child: YqSkeletonText(lines: 3, lineHeight: 24))
                : VerseWordsView(
                    key: const ValueKey('rec-karaoke'),
                    ayat: [for (final a in ayat) a],
                    lookOf: (a, i) => Karaoke.lookAt(words, play.position, a, i, started: mine),
                    current: current,
                    follow: true,
                    fontSize: 26,
                  ),
          ),
        ),
      ),
      if (words == null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: YqSpace.s),
            child: Text(t.recKaraokeLater, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: YqSpace.m)),
      SliverToBoxAdapter(
        child: Center(
          child: Column(
            children: [
              YqPlayRing(
                key: const ValueKey('rec-listener-play'),
                playing: mine && play.playing,
                progress: play.progressOf(_t.playKey, _t.durationMs),
                size: 64,
                orbit: true,
                onPressed: _toggle,
              ),
              const SizedBox(height: YqSpace.xs),
              Text(secondsText(t, _t.durationMs), style: const TextStyle(color: YqColors.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
      if (_t.social) ...[
        const SliverToBoxAdapter(child: SizedBox(height: YqSpace.l)),
        SliverToBoxAdapter(
          child: ReactionsBar(
            counts: _counts,
            mine: _mine,
            own: _t.mine,
            popped: _popped,
            pops: _pops,
            onTap: _react,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: YqSpace.l)),
        SliverToBoxAdapter(child: YqHeading(t.recCommentsTitle)),
        CommentsSliver(recordingId: _t.id, ownerView: _t.mine, onFailure: _explain),
      ],
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: YqSpace.l),
          child: Text(t.recPrivacyLine, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: YqColors.muted, height: 1.5)),
        ),
      ),
    ];

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(child: CustomScrollView(slivers: slivers)),
          if (_t.social) CommentComposer(recordingId: _t.id, enabled: _commentsOn, onFailure: _explain),
        ],
      ),
    );
  }
}

/// «ما شاء الله» · «بارك الله فيك» · «أحسنت»: one per member, tap again to take it back; on one's
/// own recording only the counts. A new reaction pops on a spring and its count rolls.
class ReactionsBar extends StatelessWidget {
  const ReactionsBar({super.key, required this.counts, required this.mine, required this.own, required this.onTap, this.popped, this.pops = 0});
  final ReactionCounts counts;
  final ReactionKind? mine;
  final bool own;
  final ReactionKind? popped;
  final int pops;
  final ValueChanged<ReactionKind> onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: YqSpace.s,
          runSpacing: YqSpace.s,
          children: [
            for (final k in ReactionKind.values)
              _ReactionPill(
                key: ValueKey('rec-react-${k.code}'),
                label: reactionLabel(t, k),
                count: counts.of(k),
                selected: mine == k,
                pop: popped == k ? pops : 0,
                onTap: own ? null : () => onTap(k),
              ),
          ],
        ),
        if (own) ...[
          const SizedBox(height: YqSpace.xs),
          Text(t.recReactOwnHint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: YqColors.muted)),
        ],
      ],
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({super.key, required this.label, required this.count, required this.selected, required this.pop, required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final int pop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final still = reduceMotion(context);
    final pill = AnimatedContainer(
      duration: still ? Duration.zero : Motion.standard,
      curve: Motion.easeOut,
      constraints: const BoxConstraints(minHeight: YqSpace.touch),
      padding: const EdgeInsets.symmetric(horizontal: YqSpace.m, vertical: YqSpace.s),
      decoration: BoxDecoration(
        color: selected ? YqColors.lapis.withValues(alpha: 0.12) : YqColors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(YqRadii.pill),
        border: Border.all(color: selected ? YqColors.lapis : YqColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? YqColors.lapis : YqColors.ink)),
          const SizedBox(width: YqSpace.s),
          YqRollingNumber(value: count, roll: false, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? YqColors.lapis : YqColors.muted)),
        ],
      ),
    );
    // The pop: 1 → 1.12 → 1 on a spring, once per tap (none under reduce motion).
    final popped = pop == 0 || still
        ? pill
        : TweenAnimationBuilder<double>(
            key: ValueKey(pop),
            tween: Tween(begin: 0, end: 1),
            duration: Motion.popCurve.settle,
            curve: Motion.popCurve,
            builder: (context, v, child) => Transform.scale(scale: 1 + 0.12 * (1 - (v - 0.5).abs() * 2).clamp(0.0, 1.0), child: child),
            child: pill,
          );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: t.recReactA11y(label, YqFormat.number(count)),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: popped),
    );
  }
}

/// The comments, newest first, 20 a page (lazy: the next page loads as its end comes into view).
class CommentsSliver extends ConsumerWidget {
  const CommentsSliver({super.key, required this.recordingId, required this.ownerView, required this.onFailure});
  final String recordingId;
  final bool ownerView;
  final RecordingFailureHandler onFailure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final view = ref.watch(commentsProvider(recordingId));
    final hidden = ref.watch(hiddenHandlesProvider);
    return view.when(
      loading: () => const SliverToBoxAdapter(child: YqSkeleton(child: YqSkeletonAvatarRows(rows: 3))),
      error: (e, _) => SliverToBoxAdapter(
        child: YqErrorState(message: failureOf(t, e), onRetry: () => ref.invalidate(commentsProvider(recordingId))),
      ),
      data: (v) {
        final items = [for (final c in v.items) if (!hidden.contains(c.author.handle)) c];
        if (items.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: YqSpace.m),
              child: Text(v.commentsOn ? t.recCommentsEmpty : t.recCommentsOffNote, textAlign: TextAlign.center, style: const TextStyle(color: YqColors.muted)),
            ),
          );
        }
        return SliverList.builder(
          itemCount: items.length + (v.hasMore || v.moreFailed ? 1 : 0) + (v.commentsOn ? 0 : 1),
          itemBuilder: (context, i) {
            if (!v.commentsOn && i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: YqSpace.s),
                child: Text(t.recCommentsOffNote, key: const ValueKey('rec-comments-off'), textAlign: TextAlign.center, style: const TextStyle(color: YqColors.muted, fontSize: 12.5)),
              );
            }
            final k = v.commentsOn ? i : i - 1;
            if (k >= items.length) {
              if (v.moreFailed) {
                return Center(child: TextButton(onPressed: () => ref.read(commentsProvider(recordingId).notifier).loadMore(), child: Text(t.retry)));
              }
              WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(commentsProvider(recordingId).notifier).loadMore());
              return const YqSkeleton(child: YqSkeletonAvatarRows(rows: 1));
            }
            return CommentRow(key: ValueKey('rec-comment-${items[k].id}'), recordingId: recordingId, comment: items[k], onFailure: onFailure);
          },
        );
      },
    );
  }
}

/// One comment: avatar, name, level, text; «حذف» for its author or the recording's owner,
/// «إبلاغ» / «حظر» for others.
class CommentRow extends ConsumerWidget {
  const CommentRow({super.key, required this.recordingId, required this.comment, required this.onFailure});
  final String recordingId;
  final RecordingComment comment;
  final RecordingFailureHandler onFailure;

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final c = comment;
    await showYqSheet<void>(
      context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.canDelete)
            YqListRow(
              key: const ValueKey('rec-comment-delete'),
              title: t.recCommentDelete,
              onTap: () async {
                Navigator.of(sheet).pop();
                try {
                  await ref.read(commentsProvider(recordingId).notifier).delete(c);
                  if (context.mounted) YqToast.show(context, t.recCommentDeleted);
                } on RecordingException catch (e) {
                  await onFailure(e);
                }
              },
            ),
          if (!c.mine) ...[
            if (c.canDelete) const YqDivider(),
            YqListRow(
              key: const ValueKey('rec-comment-report'),
              title: t.recCommentReport,
              onTap: () async {
                Navigator.of(sheet).pop();
                final reason = await pickReportReason(context);
                if (reason == null) return;
                try {
                  await ref.read(recordingsRepositoryProvider).reportComment(recordingId, c.id, reason);
                  ref.read(commentsProvider(recordingId).notifier).hide((x) => x.id == c.id);
                  if (context.mounted) YqToast.show(context, t.recReported);
                } on RecordingException catch (e) {
                  await onFailure(e);
                }
              },
            ),
            const YqDivider(),
            YqListRow(
              key: const ValueKey('rec-comment-block'),
              leading: const YqIcon(YqIcons.block, size: 22, tone: YqIconTone.idle),
              title: t.recBlock(competitorName(c.author, t)),
              trailing: const SizedBox.shrink(),
              onTap: () async {
                Navigator.of(sheet).pop();
                await blockMember(context, ref, c.author);
                ref.read(commentsProvider(recordingId).notifier).hide((x) => x.author.handle == c.author.handle);
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = comment;
    final a = c.author;
    final name = competitorName(a, t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YqSpace.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YqLevelAvatar(avatar: a.avatar, level: a.level.level, progress: a.level.progress, size: 34, stroke: 2, name: name),
          const SizedBox(width: YqSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: a.name == null ? YqColors.muted : YqColors.ink)),
                    ),
                    const SizedBox(width: YqSpace.s),
                    Text(levelNameOf(a.level.level, Localizations.localeOf(context).languageCode), style: const TextStyle(fontSize: 11, color: YqColors.muted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(c.text, style: const TextStyle(height: 1.5, color: YqColors.ink)),
              ],
            ),
          ),
          if (c.canDelete || !c.mine)
            IconButton(
              tooltip: t.recMenu,
              onPressed: () => _menu(context, ref),
              icon: const Icon(Icons.more_vert_rounded, size: 18, color: YqColors.muted),
            ),
        ],
      ),
    );
  }
}

/// «اكتب تعليقاً لطيفاً…» (280 max, a counter), inline reasons for `comment_rejected` and the rate
/// limit; comments off → a note instead.
class CommentComposer extends ConsumerStatefulWidget {
  const CommentComposer({super.key, required this.recordingId, required this.enabled, required this.onFailure});
  final String recordingId;
  final bool enabled;
  final RecordingFailureHandler onFailure;

  @override
  ConsumerState<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends ConsumerState<CommentComposer> {
  final _text = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final text = _text.text.trim();
    if (text.length < kCommentMin || _sending) {
      setState(() => _error = text.isEmpty ? null : t.recCommentWhyShort);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    RecordingException? gate;
    try {
      await ref.read(commentsProvider(widget.recordingId).notifier).post(text);
      _text.clear();
    } on RecordingException catch (e) {
      if (!mounted) return;
      if (e.failure == RecordingFailure.commentRejected || e.failure == RecordingFailure.commentRateLimited || e.failure == RecordingFailure.commentsOff) {
        setState(() => _error = failureText(t, e.failure, problem: e.problem));
      } else {
        gate = e;
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    // Explained (and sent again after a passed gate) once this send is no longer in flight.
    if (gate != null && mounted && await widget.onFailure(gate) && mounted) await _send();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final commentsOn = ref.watch(commentsProvider(widget.recordingId)).valueOrNull?.commentsOn ?? widget.enabled;
    if (!commentsOn || !widget.enabled) {
      return Padding(
        padding: const EdgeInsets.only(top: YqSpace.s),
        child: Text(t.recCommentsOffNote, key: const ValueKey('rec-composer-off'), textAlign: TextAlign.center, style: const TextStyle(color: YqColors.muted, fontSize: 12.5)),
      );
    }
    // UTF-16 units, as the server's strictest check counts (zod `.max(280)`): a mark of tashkeel or
    // an emoji's parts count, so what the counter allows is never refused as `too_long`.
    final len = _text.text.length;
    return Padding(
      padding: const EdgeInsets.only(top: YqSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('rec-composer'),
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  inputFormatters: const [Utf16LengthLimiter(kCommentMax)],
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    hintText: t.recCommentHint,
                    counterText: '${YqFormat.number(len)}/${YqFormat.number(kCommentMax)}',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: YqSpace.s),
              IconButton.filled(
                key: const ValueKey('rec-composer-send'),
                tooltip: t.recCommentSend,
                style: IconButton.styleFrom(backgroundColor: YqColors.lapis, minimumSize: const Size(YqSpace.touch, YqSpace.touch)),
                onPressed: _sending || len < kCommentMin ? null : _send,
                icon: const Icon(Icons.arrow_upward_rounded, color: YqColors.white),
              ),
            ],
          ),
          if (_error != null) InlineFailure(_error),
        ],
      ),
    );
  }
}

/// «إبلاغ عن التلاوة»: four reasons, then «حظر {name}» (both ways on the server, hidden here at once).
Future<void> showRecordingReportSheet(BuildContext context, {required String recordingId, required PublicCompetitor owner, VoidCallback? onBlocked}) =>
    showYqSheet<void>(
      context,
      builder: (sheet) => Consumer(
        builder: (context, ref, _) {
          final t = AppLocalizations.of(context);
          Future<void> report(RecordingReportReason r) async {
            Navigator.of(sheet).pop();
            try {
              await ref.read(recordingsRepositoryProvider).reportRecording(recordingId, r);
              if (context.mounted) YqToast.show(context, t.recReported);
            } on RecordingException catch (e) {
              if (context.mounted) YqToast.show(context, failureText(t, e.failure));
            }
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(t.recReport, style: Theme.of(context).textTheme.titleLarge)),
              const SizedBox(height: YqSpace.m),
              for (final r in RecordingReportReason.values) ...[
                YqListRow(key: ValueKey('rec-report-${r.code}'), title: reportReasonLabel(t, r), onTap: () => report(r)),
                if (r != RecordingReportReason.values.last) const YqDivider(),
              ],
              const SizedBox(height: YqSpace.l),
              YqListRow(
                key: const ValueKey('rec-report-block'),
                leading: const YqIcon(YqIcons.block, size: 22, tone: YqIconTone.idle),
                title: t.recBlock(competitorName(owner, t)),
                trailing: const SizedBox.shrink(),
                onTap: () async {
                  Navigator.of(sheet).pop();
                  await blockMember(context, ref, owner);
                  onBlocked?.call();
                },
              ),
            ],
          );
        },
      ),
    );

/// The four report reasons (a recording or a comment); null when dismissed.
Future<RecordingReportReason?> pickReportReason(BuildContext context) => showYqSheet<RecordingReportReason>(
      context,
      builder: (sheet) {
        final t = AppLocalizations.of(sheet);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(t.recCommentReport, style: Theme.of(sheet).textTheme.titleLarge)),
            const SizedBox(height: YqSpace.m),
            for (final r in RecordingReportReason.values) ...[
              YqListRow(key: ValueKey('rec-reason-${r.code}'), title: reportReasonLabel(t, r), onTap: () => Navigator.of(sheet).pop(r)),
              if (r != RecordingReportReason.values.last) const YqDivider(),
            ],
          ],
        );
      },
    );

String reportReasonLabel(AppLocalizations t, RecordingReportReason r) => switch (r) {
      RecordingReportReason.notRecitation => t.recReportNotRecitation,
      RecordingReportReason.inappropriate => t.recReportInappropriate,
      RecordingReportReason.spam => t.recReportSpam,
      RecordingReportReason.other => t.recReportOther,
    };

/// Blocks [who] through the community block (hidden here at once, both ways on the server).
Future<void> blockMember(BuildContext context, WidgetRef ref, PublicCompetitor who) async {
  final t = AppLocalizations.of(context);
  final hidden = ref.read(hiddenHandlesProvider.notifier)..hide(who.handle);
  final r = await ref.read(communityRepositoryProvider).block(who.handle);
  if (!context.mounted) return;
  if (r.isOk) {
    ref.invalidate(blocksProvider);
    YqToast.show(context, t.recBlocked(competitorName(who, t)));
  } else {
    hidden.unhide(who.handle);
    YqToast.show(context, t.errorGeneric);
  }
}

/// Limits a field to [max] UTF-16 code units (Flutter's `maxLength` counts grapheme clusters, which
/// the server does not): a paste is cut at the limit, never inside a surrogate pair.
class Utf16LengthLimiter extends TextInputFormatter {
  const Utf16LengthLimiter(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length <= max) return newValue;
    if (oldValue.text.length >= max && newValue.text.length > oldValue.text.length) return oldValue;
    var end = max;
    final units = newValue.text.codeUnits;
    // Never split a surrogate pair.
    if (units[end - 1] >= 0xD800 && units[end - 1] <= 0xDBFF) end--;
    final text = newValue.text.substring(0, end);
    final offset = newValue.selection.baseOffset.clamp(0, text.length);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}
