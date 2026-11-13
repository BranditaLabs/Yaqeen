import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows «انتهى الأسبوع» once per finished week (from the cached profile, never waiting on the
/// network) and returns whether it showed. Home calls it after the first frame.
///
/// Stub created by the contracts stream: shows nothing yet; the competitions stream implements it.
Future<bool> maybeShowWeekResult(BuildContext context, WidgetRef ref) async => false;
