import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_button.dart';
import '../../../core/widgets/yq_icon.dart';
import '../../../core/widgets/yq_layout.dart';
import '../../../core/widgets/yq_play_ring.dart';
import '../../../core/widgets/yq_stage.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../onboarding/presentation/session_controller.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../data/recording_drafts.dart';
import '../data/recordings_repository.dart';
import '../domain/recording_models.dart';
import 'listener_sheet.dart';
import 'recording_widgets.dart';
import 'recordings_providers.dart';
import 'share_gate.dart';

/// «تلاواتي» on the Profile tab (APP_SPEC §5.24, after the badges): up to three track cards of the
/// person's own voice — verse reference, duration, `YqPlayRing`, the visibility, the status line
/// for the owner, reactions and comments. Long-press and drag to reorder (also «إلى الأعلى /
/// الأسفل» in the menu); the menu sets who hears it, comments, and deletes (two steps). Empty: one
/// quiet row «سجّل تلاوتك لآيات تحبها (30 ثانية)». Takes still on this phone (a guest's, or saved
/// offline) follow the cards. Refreshes when the app comes back; shaped skeletons while loading.
class RecordingsSection extends ConsumerStatefulWidget {
  const RecordingsSection({super.key});

  @override
  ConsumerState<RecordingsSection> createState() => _RecordingsSectionState();
}

class _RecordingsSectionState extends ConsumerState<RecordingsSection> {
  /// Back from the background: fresh statuses (an AI check may have finished) and queued uploads.
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: () => ref.read(myRecordingsProvider.notifier).refresh(flush: true).ignore());
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  void _record() => context.push('/profile/recordings/new');

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final view = ref.watch(myRecordingsProvider);
    final v = view.valueOrNull;
    final full = v?.full ?? false;
    final daily = v != null && v.leftToday <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YqHeading(
          t.recTitle,
          action: v == null || v.count == 0 || full
              ? null
              : TextButton.icon(
                  key: const ValueKey('rec-new'),
                  onPressed: daily ? null : _record,
                  icon: const Icon(Icons.mic_none_rounded, size: 18),
                  label: Text(t.recRecordNew),
                ),
        ),
        YqFadeSwap(
          child: switch (view) {
            AsyncData(:final value) => _Body(key: const ValueKey('rec-body'), view: value, onRecord: daily ? null : _record),
            AsyncError(:final error) when v == null => LiquidGlass(
                key: const ValueKey('rec-error'),
                child: YqErrorState(message: failureOf(t, error), onRetry: () => ref.invalidate(myRecordingsProvider)),
              ),
            _ => const RecordingsSkeleton(key: ValueKey('rec-skeleton')),
          },
        ),
        if (v != null && (full || daily)) ...[
          const SizedBox(height: YqSpace.s),
          Text(
            full ? t.recLimitReached(YqFormat.number(kProfileRecordingsMax)) : t.recDailyLimit,
            key: const ValueKey('rec-limit'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: YqColors.muted),
          ),
        ],
      ],
    );
  }
}

/// Two track-card shapes under one shimmer (never a spinner).
class RecordingsSkeleton extends StatelessWidget {
  const RecordingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const YqSkeleton(
        child: Column(
          children: [
            _CardShape(),
            SizedBox(height: YqSpace.s),
            _CardShape(),
          ],
        ),
      );
}

class _CardShape extends StatelessWidget {
  const _CardShape();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(YqSpace.l),
        child: Row(
          children: [
            YqSkeletonBox.circle(52),
            SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  YqSkeletonBox(width: 170, height: 14, radius: YqRadii.pill),
                  SizedBox(height: YqSpace.s),
                  YqSkeletonBox(width: 110, height: 10, radius: YqRadii.pill),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Body extends ConsumerWidget {
  const _Body({super.key, required this.view, required this.onRecord});
  final MyRecordingsView view;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    if (view.count == 0) {
      return YqGroup(
        key: const ValueKey('rec-empty'),
        children: [
          YqListRow(
            leading: const YqIconTile(YqIcons.recite, size: 36),
            title: t.recEmpty(YqFormat.number(kRecordingMaxMs ~/ 1000)),
            onTap: onRecord,
          ),
        ],
      );
    }
    final items = view.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.offline) ...[const YqOfflineBanner(offline: true), const SizedBox(height: YqSpace.s)],
        if (items.isNotEmpty)
          ReorderableListView.builder(
            key: const ValueKey('rec-cards'),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: items.length > 1,
            itemCount: items.length,
            proxyDecorator: (child, _, __) => Material(type: MaterialType.transparency, child: child),
            // newIndex is already adjusted for the lifted item: the 1-based position is newIndex + 1.
            onReorderItem: (from, to) {
              if (from == to) return;
              ref.read(myRecordingsProvider.notifier).move(items[from], (to + 1).clamp(1, items.length)).catchError((Object e) {
                if (context.mounted) YqToast.show(context, failureOf(t, e));
              });
            },
            itemBuilder: (context, i) => Padding(
              key: ValueKey('rec-card-${items[i].id}'),
              padding: const EdgeInsets.only(bottom: YqSpace.s),
              child: RecordingCard(recording: items[i], index: i, total: items.length),
            ),
          ),
        for (final d in view.drafts)
          Padding(
            key: ValueKey('rec-draft-${d.id}'),
            padding: const EdgeInsets.only(bottom: YqSpace.s),
            child: DraftCard(draft: d),
          ),
        if (items.length > 1)
          Text(t.recReorderHint, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: YqColors.muted)),
      ],
    );
  }
}

/// One recording on the profile.
class RecordingCard extends ConsumerWidget {
  const RecordingCard({super.key, required this.recording, required this.index, required this.total});
  final Recording recording;
  final int index;
  final int total;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final local = recording.words == null ? await ref.read(recordingsRepositoryProvider).localWords(recording.id) : null;
    if (!context.mounted) return;
    await showRecordingListener(context, ListenTarget.own(recording, localWords: local));
    ref.read(myRecordingsProvider.notifier).refresh().ignore();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final r = recording;
    final play = ref.watch(recordingPlayerProvider);
    final key = 'rec/${r.id}';
    final rejected = r.status == RecordingStatus.rejected || r.status == RecordingStatus.removed;
    return GlassTap(
      onTap: () => _open(context, ref),
      child: LiquidGlass(
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                YqPlayRing(
                  key: ValueKey('rec-play-${r.id}'),
                  size: 52,
                  playing: play.isOf(key) && play.playing,
                  progress: play.progressOf(key, r.durationMs),
                  semanticLabel: play.isOf(key) && play.playing ? t.recPauseA11y(t.recTitle) : t.recPlayA11y(t.recTitle),
                  onPressed: () => ref
                      .read(recordingPlayerProvider.notifier)
                      .toggle(key, () => ref.read(recordingsRepositoryProvider).audioFile(r.id, r.audioPath), title: t.recTitle),
                ),
                const SizedBox(width: YqSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VerseRefText(surah: r.surah, from: r.fromAyah, to: r.toAyah, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(secondsText(t, r.durationMs), style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                          const SizedBox(width: YqSpace.s),
                          VisibilityChip(r.visibility),
                        ],
                      ),
                      const SizedBox(height: 4),
                      RecordingStatusLine(r),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('rec-menu-${r.id}'),
                  tooltip: t.recMenu,
                  onPressed: () => showRecordingMenu(context, r, index: index, total: total),
                  icon: const Icon(Icons.more_vert_rounded, color: YqColors.muted),
                ),
              ],
            ),
            if (r.reactions.total > 0 || r.commentCount > 0) ...[
              const SizedBox(height: YqSpace.s),
              ReactionSummary(reactions: r.reactions, comments: r.commentCount),
            ],
            if (rejected && r.status != RecordingStatus.removed)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: ValueKey('rec-rerecord-${r.id}'),
                  onPressed: () => context.push('/profile/recordings/new?surah=${r.surah}&from=${r.fromAyah}&to=${r.toAyah}'),
                  child: Text(t.recRerecord),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A take still on this phone: play it, upload it (after signing in), or delete it.
class DraftCard extends ConsumerWidget {
  const DraftCard({super.key, required this.draft});
  final RecordingDraft draft;

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    if (!ref.read(sessionProvider).canEarnPoints) {
      final ok = await showSignInSheet(context, title: t.recDraftSignIn);
      if (!ok || !context.mounted) return;
    }
    try {
      await ref.read(myRecordingsProvider.notifier).uploadDraft(draft);
      if (context.mounted) YqToast.show(context, t.recSaved);
    } on RecordingException catch (e) {
      if (!context.mounted) return;
      if (isShareGate(e.failure)) {
        if (await showShareGate(context) && context.mounted) await _upload(context, ref);
        return;
      }
      YqToast.show(context, failureText(t, e.failure));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final d = draft;
    final signedIn = ref.watch(sessionProvider.select((s) => s.canEarnPoints));
    final play = ref.watch(recordingPlayerProvider);
    final key = 'draft/${d.id}';
    return LiquidGlass(
      padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
      child: Row(
        children: [
          YqPlayRing(
            key: ValueKey('rec-draft-play-${d.id}'),
            size: 52,
            playing: play.isOf(key) && play.playing,
            progress: play.progressOf(key, d.durationMs),
            onPressed: () => ref.read(recordingPlayerProvider.notifier).toggle(key, () async => File(d.path), title: t.recTitle),
          ),
          const SizedBox(width: YqSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VerseRefText(surah: d.surah, from: d.fromAyah, to: d.toAyah, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${secondsText(t, d.durationMs)} · ${draftText(t, d, signedIn: signedIn)}',
                  key: ValueKey('rec-draft-state-${d.state.name}'),
                  style: const TextStyle(fontSize: 12, color: YqColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          if (d.state != DraftState.queued)
            TextButton(key: ValueKey('rec-draft-upload-${d.id}'), onPressed: () => _upload(context, ref), child: Text(t.recDraftUpload)),
          IconButton(
            key: ValueKey('rec-draft-delete-${d.id}'),
            tooltip: t.delete,
            onPressed: () async {
              if (await confirmRecordingDelete(context) && context.mounted) {
                await ref.read(recordingPlayerProvider.notifier).stop(key);
                await ref.read(myRecordingsProvider.notifier).deleteDraft(d);
              }
            },
            icon: const Icon(Icons.close_rounded, color: YqColors.muted),
          ),
        ],
      ),
    );
  }
}

/// «حذف هذه التلاوة؟» — the second step of a delete. True when confirmed.
Future<bool> confirmRecordingDelete(BuildContext context) async {
  final t = AppLocalizations.of(context);
  final ok = await showYqSheet<bool>(
    context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.recDeleteTitle, style: Theme.of(sheet).textTheme.titleLarge)),
        const SizedBox(height: YqSpace.s),
        Text(t.recDeleteBody, style: const TextStyle(color: YqColors.muted, height: 1.6)),
        const SizedBox(height: YqSpace.l),
        // The destructive confirm is the one place the error colour appears (spec §5.24·ب).
        FilledButton(
          key: const ValueKey('rec-delete-confirm'),
          style: FilledButton.styleFrom(backgroundColor: YqColors.error, minimumSize: const Size.fromHeight(YqSpace.touch + 6)),
          onPressed: () => Navigator.of(sheet).pop(true),
          child: Text(t.recDeleteConfirm),
        ),
        const SizedBox(height: YqSpace.s),
        YqButton.text(label: t.cancel, expand: true, onPressed: () => Navigator.of(sheet).pop(false)),
      ],
    ),
  );
  return ok == true;
}

/// The card's menu: who hears it, comments, move up / down, delete.
Future<void> showRecordingMenu(BuildContext context, Recording r, {required int index, required int total}) =>
    showYqSheet<void>(context, scrollable: true, builder: (_) => RecordingMenu(recording: r, index: index, total: total));

class RecordingMenu extends ConsumerStatefulWidget {
  const RecordingMenu({super.key, required this.recording, required this.index, required this.total});
  final Recording recording;
  final int index;
  final int total;

  @override
  ConsumerState<RecordingMenu> createState() => _RecordingMenuState();
}

class _RecordingMenuState extends ConsumerState<RecordingMenu> {
  late Recording _r = widget.recording;
  bool _busy = false;
  String? _error;

  Future<void> _visibility(RecordingVisibility v) async {
    if (v == _r.visibility || _busy) return;
    final t = AppLocalizations.of(context);
    if (v != RecordingVisibility.private && !await ensureAccountForSharing(context, ref)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await ref.read(myRecordingsProvider.notifier).setVisibility(_r, v);
      if (mounted) setState(() => _r = next);
    } on RecordingException catch (e) {
      if (!mounted) return;
      if (isShareGate(e.failure)) {
        setState(() => _busy = false);
        if (await showShareGate(context) && mounted) await _visibility(v);
        return;
      }
      setState(() => _error = failureText(t, e.failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _comments(bool on) async {
    final t = AppLocalizations.of(context);
    setState(() => _r = _r.copyWith(commentsOn: on));
    try {
      await ref.read(myRecordingsProvider.notifier).setComments(widget.recording, on);
    } on RecordingException catch (e) {
      if (!mounted) return;
      setState(() {
        _r = _r.copyWith(commentsOn: !on);
        _error = failureText(t, e.failure);
      });
    }
  }

  Future<void> _move(int position) async {
    final t = AppLocalizations.of(context);
    Navigator.of(context).pop();
    try {
      await ref.read(myRecordingsProvider.notifier).move(_r, position);
    } on RecordingException catch (e) {
      if (mounted) YqToast.show(context, failureText(t, e.failure));
    }
  }

  Future<void> _delete() async {
    final t = AppLocalizations.of(context);
    final nav = Navigator.of(context);
    if (!await confirmRecordingDelete(context) || !mounted) return;
    nav.pop();
    final messenger = context;
    try {
      await ref.read(recordingPlayerProvider.notifier).stop('rec/${_r.id}');
      await ref.read(myRecordingsProvider.notifier).delete(_r);
      if (messenger.mounted) YqToast.show(messenger, t.recDeleted);
    } on RecordingException catch (e) {
      if (messenger.mounted) YqToast.show(messenger, failureText(t, e.failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final r = _r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text(t.recMenu, style: text.titleLarge)),
        const SizedBox(height: YqSpace.xs),
        VerseRefText(surah: r.surah, from: r.fromAyah, to: r.toAyah, style: const TextStyle(color: YqColors.muted)),
        const SizedBox(height: YqSpace.l),
        Text(t.recMenuVisibility, style: text.titleSmall),
        const SizedBox(height: YqSpace.xs),
        YqGroup(
          children: [
            for (final v in RecordingVisibility.values)
              YqListRow(
                key: ValueKey('rec-vis-${v.code}'),
                dense: true,
                title: visibilityLabel(t, v),
                subtitle: visibilityHint(t, v),
                trailing: r.visibility == v ? const Icon(Icons.check_rounded, color: YqColors.lapis) : const SizedBox(width: 24),
                // A rejected or removed recording stays private (`recording_not_public`).
                onTap: _busy || (v != RecordingVisibility.private && !r.shareable) ? null : () => _visibility(v),
              ),
          ],
        ),
        if (_error != null) InlineNote(_error!),
        if (r.shared) ...[
          const SizedBox(height: YqSpace.m),
          YqGroup(
            children: [
              YqListRow(
                dense: true,
                title: t.recMenuComments,
                trailing: YqSwitch(key: const ValueKey('rec-menu-comments'), label: t.recMenuComments, value: r.commentsOn, onChanged: _comments),
              ),
            ],
          ),
        ],
        const SizedBox(height: YqSpace.m),
        YqGroup(
          children: [
            if (widget.index > 0) YqListRow(key: const ValueKey('rec-move-up'), dense: true, title: t.recMenuMoveUp, onTap: () => _move(widget.index)),
            if (widget.index < widget.total - 1)
              YqListRow(key: const ValueKey('rec-move-down'), dense: true, title: t.recMenuMoveDown, onTap: () => _move(widget.index + 2)),
            YqListRow(key: const ValueKey('rec-delete'), dense: true, title: t.delete, onTap: _delete),
          ],
        ),
      ],
    );
  }
}

