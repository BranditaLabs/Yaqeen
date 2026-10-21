import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/format.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/text/arabic.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/features/prayer/data/prayer_repository.dart';
import 'package:yaqeen/features/prayer/domain/prayer_calculator.dart';

void main() {
  setUpAll(Zoned.ensureInitialized);
  const repo = PrayerRepository();
  const s = AppSettings(place: Place.cairo);

  test('next prayer through the day, the 20-minute adhan window, and across midnight', () {
    // 20 Oct 2026 Cairo (UTC+3): asr 15:53, maghrib 18:19, isha 19:37.
    final beforeAsr = DateTime.utc(2026, 10, 20, 12, 0); // 15:00 local
    expect(repo.moment(s, beforeAsr).next, PrayerName.asr);
    expect(repo.moment(s, beforeAsr).isPrayerTime, isFalse);

    final atAsr = DateTime.utc(2026, 10, 20, 13, 0); // 16:00 local, 7 min after Asr
    final m = repo.moment(s, atAsr);
    expect(m.current, PrayerName.asr);
    expect(m.next, PrayerName.maghrib);

    final lateNight = DateTime.utc(2026, 10, 20, 21, 30); // 00:30 on the 21st local
    final n = repo.moment(s, lateNight);
    expect(n.next, PrayerName.fajr);
    expect(repo.local(s, n.at).day, 21);
    final afterIsha = DateTime.utc(2026, 10, 20, 20, 0); // 23:00 local
    expect(repo.local(s, repo.moment(s, afterIsha).at).day, 21);
  });

  test('Egypt DST: the clock moves back on 30 Oct 2026 and times stay right', () {
    final thu = repo.forDate(s, DateTime(2026, 10, 29));
    final fri = repo.forDate(s, DateTime(2026, 10, 30));
    expect(repo.local(s, thu.dhuhr).timeZoneOffset, const Duration(hours: 3));
    expect(repo.local(s, fri.dhuhr).timeZoneOffset, const Duration(hours: 2));
    // Solar noon barely moves day to day, so the wall clock jumps back about an hour.
    expect(repo.local(s, thu.dhuhr).hour - repo.local(s, fri.dhuhr).hour, 1);
    expect(fri.dhuhr.difference(thu.dhuhr).inMinutes, closeTo(24 * 60, 1));
  });

  test('today follows the place, not the device', () {
    final now = DateTime.utc(2026, 10, 20, 22, 30); // 01:30 on the 21st in Cairo
    expect(repo.today(s, now), DateTime(2026, 10, 21));
  });

  test('12-hour Arabic and English times with Western digits', () {
    expect(YqFormat.time(DateTime(2026, 1, 1, 15, 55), 'ar'), '3:55 م');
    expect(YqFormat.time(DateTime(2026, 1, 1, 5, 30), 'ar'), '5:30 ص');
    expect(YqFormat.time(DateTime(2026, 1, 1, 0, 5), 'en'), '12:05 AM');
    expect(YqFormat.weekdayDayMonth(DateTime(2026, 10, 19), 'ar'), 'الإثنين 19 أكتوبر');
  });

  test('Arabic search normalisation', () {
    expect(ArabicText.normalize('الْكَهْفِ'), 'الكهف');
    expect(ArabicText.normalize('إبراهيم'), 'ابراهيم');
    expect(ArabicText.normalize('سورة يس'), 'سوره يس');
    expect(ArabicText.normalize('١٨'), '18');
    expect(ArabicText.withoutArticle('الكهف'), 'كهف');
  });
}
