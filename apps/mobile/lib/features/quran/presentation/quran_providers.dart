import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/di/providers.dart';
import '../data/mushaf_fonts.dart';
import '../domain/annotations.dart';
import '../domain/khatma.dart';
import '../domain/mushaf_layout.dart';
import '../domain/reading_stats.dart';

/// Highlights and notes the reader paints — device first; optional encrypted cloud backup (consent
/// `cloud_backup`).
final annotationsProvider = FutureProvider.autoDispose<Annotations>((ref) => ref.watch(readingRepositoryProvider).annotations());

/// The active khatma plan, if any.
final khatmaProvider = FutureProvider.autoDispose<Khatma?>((ref) => ref.watch(readingRepositoryProvider).khatma());

final khatmaHistoryProvider = FutureProvider.autoDispose<List<KhatmaRecord>>((ref) => ref.watch(readingRepositoryProvider).khatmaHistory());

final readingStatsProvider = FutureProvider.autoDispose<ReadingStats>((ref) => ref.watch(readingRepositoryProvider).stats());

/// The printed page layout (null → the reader sets text pages). Parsed with the mushaf text.
final mushafLayoutProvider = FutureProvider<MushafLayout?>((ref) async {
  await ref.watch(quranDataProvider.future);
  return ref.watch(quranRepositoryProvider).layout();
});

/// Per-page mushaf fonts, alive for the session (loaded fonts stay registered with the engine).
final mushafFontsProvider = Provider<MushafFonts>((ref) {
  final fonts = MushafFonts(root: ref.watch(filesDirProvider), baseUrl: Env.mushafFontBaseUrl, queue: ref.watch(downloadQueueProvider));
  ref.onDispose(fonts.dispose);
  return fonts;
});
