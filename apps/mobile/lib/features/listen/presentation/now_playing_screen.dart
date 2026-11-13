import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../quran/domain/passage.dart';
import 'listen_controller.dart';

export 'player_sheet.dart' show mmss;

/// A general «استماع» entry (Home, Quran index, challenge): the reader, in listen mode with the
/// player open, on the page of what is already playing, else of the saved resume point, else of
/// [fallbackSurah] (the last-read one). «Now playing» is no longer a screen of its own: the printed
/// page is the only Quran surface (spec §5.13).
Future<void> pushListen(BuildContext context, WidgetRef ref, int fallbackSurah) async {
  final at = await ref.read(listenControllerProvider.notifier).entryRef(fallbackSurah);
  if (!context.mounted) return;
  final q = ref.read(quranDataProvider).valueOrNull;
  final page = q?.pageOf(at) ?? surahStartPage(at.surah);
  await context.push('/quran/read/$page?mode=${QuranMode.listen.name}&ayah=${at.surah}:${at.ayah}&player=open');
}
