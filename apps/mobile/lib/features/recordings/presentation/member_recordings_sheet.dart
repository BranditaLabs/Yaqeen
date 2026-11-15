import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/liquid_glass.dart';
import '../../../core/widgets/yq_avatar.dart';
import '../../../core/widgets/yq_play_ring.dart';
import '../../../core/widgets/yq_states.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../community/domain/community_models.dart';
import '../../community/presentation/community_providers.dart';
import '../../community/presentation/community_widgets.dart';
import '../../onboarding/presentation/sign_in_sheet.dart';
import '../data/recordings_repository.dart';
import '../domain/recording_models.dart';
import 'listener_sheet.dart';
import 'recording_widgets.dart';
import 'recordings_providers.dart';

/// A member's profile sheet from the league, tournament and level-board rows (APP_SPEC §5.31.6):
/// their picture in the level ring, name and «تلاواته» — the approved recordings they share with
/// members — each opening the listener. Report and block from the listener's menu. Listening needs
/// only an account (a guest is asked to sign in); a blocked or departed member is simply gone.
/// Closing it stops a clip played from the list and drops the member clips fetched for listening.
Future<void> showMemberRecordingsSheet(BuildContext context, PublicCompetitor member) async {
  final container = ProviderScope.containerOf(context);
  await showYqSheet<void>(context, scrollable: true, builder: (_) => MemberRecordingsSheet(member: member));
  final player = container.read(recordingPlayerProvider.notifier);
  if (container.read(recordingPlayerProvider).key?.startsWith('rec/') ?? false) await player.stop();
  container.read(recordingsRepositoryProvider).clearListened().ignore();
}

class MemberRecordingsSheet extends ConsumerWidget {
  const MemberRecordingsSheet({super.key, required this.member});
  final PublicCompetitor member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final name = competitorName(member, t);
    final hidden = ref.watch(hiddenHandlesProvider).contains(member.handle);
    final view = ref.watch(memberRecordingsProvider(member.handle));
    final locale = Localizations.localeOf(context).languageCode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            YqLevelAvatar(avatar: member.avatar, level: member.level.level, progress: member.level.progress, size: 52, stroke: 2.5, name: name),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('@${member.handle} · ${levelNameOf(member.level.level, locale)}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: YqSpace.l),
        Text(t.recMemberTitle(name), style: text.titleSmall),
        const SizedBox(height: YqSpace.s),
        if (hidden)
          Text(t.recErrGone, style: const TextStyle(color: YqColors.muted))
        else
          YqFadeSwap(
            child: view.when(
              loading: () => const YqSkeleton(key: ValueKey('rec-member-loading'), child: YqSkeletonRows(rows: 2, leading: 48)),
              error: (e, _) {
                final f = RecordingException.from(e).failure;
                if (f == RecordingFailure.accountRequired) {
                  return Column(
                    key: const ValueKey('rec-member-account'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t.recErrAccount, style: const TextStyle(color: YqColors.muted)),
                      TextButton(
                        onPressed: () async {
                          if (await showSignInSheet(context)) ref.invalidate(memberRecordingsProvider(member.handle));
                        },
                        child: Text(t.recSignInToShare),
                      ),
                    ],
                  );
                }
                if (f == RecordingFailure.notFound) {
                  return Text(t.recMemberEmpty, key: const ValueKey('rec-member-empty'), style: const TextStyle(color: YqColors.muted));
                }
                return YqErrorState(message: failureText(t, f), onRetry: () => ref.invalidate(memberRecordingsProvider(member.handle)));
              },
              data: (m) => m.items.isEmpty
                  ? Text(t.recMemberEmpty, key: const ValueKey('rec-member-empty'), style: const TextStyle(color: YqColors.muted))
                  : Column(
                      key: const ValueKey('rec-member-list'),
                      children: [
                        for (final r in m.items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: YqSpace.s),
                            child: MemberRecordingTile(recording: r, onChanged: () => ref.invalidate(memberRecordingsProvider(member.handle))),
                          ),
                      ],
                    ),
            ),
          ),
        const SizedBox(height: YqSpace.m),
        Text(t.recPrivacyLine, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: YqColors.muted, height: 1.5)),
      ],
    );
  }
}

class MemberRecordingTile extends ConsumerWidget {
  const MemberRecordingTile({super.key, required this.recording, required this.onChanged});
  final PublicRecording recording;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final r = recording;
    final play = ref.watch(recordingPlayerProvider);
    final key = 'rec/${r.id}';
    return GlassTap(
      onTap: () async {
        await showRecordingListener(context, ListenTarget.member(r), onChanged: (_) => onChanged());
      },
      child: LiquidGlass(
        key: ValueKey('rec-member-${r.id}'),
        padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.m),
        child: Row(
          children: [
            YqPlayRing(
              size: 48,
              playing: play.isOf(key) && play.playing,
              progress: play.progressOf(key, r.durationMs),
              onPressed: () => ref
                  .read(recordingPlayerProvider.notifier)
                  .toggle(key, () => ref.read(recordingsRepositoryProvider).memberAudioFile(r.id, r.audioPath), title: t.recTitle),
            ),
            const SizedBox(width: YqSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  VerseRefText(surah: r.surah, from: r.fromAyah, to: r.toAyah, style: Theme.of(context).textTheme.titleSmall),
                  Text(secondsText(t, r.durationMs), style: const TextStyle(fontSize: 12, color: YqColors.muted)),
                  if (r.reactions.total > 0 || r.commentCount > 0) ReactionSummary(reactions: r.reactions, comments: r.commentCount),
                ],
              ),
            ),
            if (r.reactions.total > 0) Text(YqFormat.number(r.reactions.total), style: const TextStyle(color: YqColors.lapis, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
