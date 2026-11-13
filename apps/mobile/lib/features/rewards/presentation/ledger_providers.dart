import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../domain/reward.dart';

/// The caller's own points ledger (GET /v1/me/ledger): amounts and reasons, never which worship act.
/// Read by «سجل النقاط» and by the card preview (a level before the card is published).
final ledgerProvider = FutureProvider.autoDispose<List<LedgerEntry>>((ref) => ref.watch(rewardsRepositoryProvider).ledger());
