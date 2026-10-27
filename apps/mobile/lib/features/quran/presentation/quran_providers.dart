import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../domain/annotations.dart';
import '../domain/khatma.dart';
import '../domain/reading_stats.dart';

/// Highlights and notes the reader paints (device only).
final annotationsProvider = FutureProvider.autoDispose<Annotations>((ref) => ref.watch(readingRepositoryProvider).annotations());

/// The active khatma plan, if any.
final khatmaProvider = FutureProvider.autoDispose<Khatma?>((ref) => ref.watch(readingRepositoryProvider).khatma());

final khatmaHistoryProvider = FutureProvider.autoDispose<List<KhatmaRecord>>((ref) => ref.watch(readingRepositoryProvider).khatmaHistory());

final readingStatsProvider = FutureProvider.autoDispose<ReadingStats>((ref) => ref.watch(readingRepositoryProvider).stats());
