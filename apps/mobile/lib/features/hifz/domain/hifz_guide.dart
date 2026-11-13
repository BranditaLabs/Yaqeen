import '../../quran/domain/quran_data.dart';
import 'hifz_plan.dart';

/// The guided halaqa (spec §5.25) in the reader: «استماع ×3» → «تكرار ×10» → «اختبار». Each stage
/// ticks its step of the plan (`HifzController.completeStep`) by itself; the grade is suggested and
/// confirmed. A due review opens straight at the test.
abstract final class HifzGuide {
  /// Listening rounds before repeating.
  static const listenTimes = 3;

  /// Repetitions (echo or «كرّرت») before the test.
  static const repeatTimes = 10;

  /// The plan's steps, in order: listen, repeat, test.
  static const steps = 3;

  /// Today's halaqa in the reader, on the passage's first page.
  static String halaqaLocation(QuranData q, ({int surah, int from, int to}) p) =>
      '/quran/read/${q.pageOf(AyahRef(p.surah, p.from))}?session=hifz&surah=${p.surah}&from=${p.from}&to=${p.to}';

  /// A due review in the reader, at the test.
  static String reviewLocation(QuranData q, HifzPortion p) =>
      '/quran/read/${q.pageOf(AyahRef(p.surah, p.from))}?session=review&surah=${p.surah}&from=${p.from}&to=${p.to}'
      '&portion=${Uri.encodeQueryComponent(p.id)}';

  /// Whether today's halaqa was started (a step ticked): «أكمل الحلقة» instead of «ابدأ الحلقة».
  static bool started(HifzPlan plan, DateTime today) => plan.stepsFor(today).isNotEmpty;
}
