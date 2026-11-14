import '../../recite/domain/recitation.dart';
import 'review_scheduler.dart';

/// The grade a guided test suggests («اقتراح: {grade}») — the user always confirms it (spec §6.14).
///
/// With a recitation ([recite], aligned on the device): every word heard as written, nothing
/// revealed and no help → easy; notes, words not reached and «مساعدة» together at most one word in
/// ten, and at most a quarter of the ayat revealed → good; else hard. Without one (memorise «words»
/// + self-check), only the reveals count: none → easy, up to a third of the [ayat] → good, more →
/// hard.
ReviewGrade suggestGrade({List<AyahResult>? recite, int reveals = 0, int helps = 0, required int ayat}) {
  final n = ayat < 1 ? 1 : ayat;
  final words = [for (final r in recite ?? const <AyahResult>[]) ...r.words];
  if (words.isNotEmpty) {
    final missed = words.where((w) => w.mark != WordMark.ok).length;
    if (missed == 0 && reveals == 0 && helps == 0) return ReviewGrade.easy;
    if ((missed + helps) * 10 <= words.length && reveals * 4 <= n) return ReviewGrade.good;
    return ReviewGrade.hard;
  }
  if (reveals <= 0) return ReviewGrade.easy;
  if (reveals * 3 <= n) return ReviewGrade.good;
  return ReviewGrade.hard;
}
