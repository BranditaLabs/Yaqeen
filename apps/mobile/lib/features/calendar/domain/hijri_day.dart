/// Hijri month names for English (the API sends the Arabic name).
const hijriMonthsEn = [
  'Muharram', 'Safar', 'Rabiʿ al-Awwal', 'Rabiʿ al-Thani', 'Jumada al-Ula', 'Jumada al-Akhirah',
  'Rajab', 'Shaʿban', 'Ramadan', 'Shawwal', 'Dhu al-Qaʿdah', 'Dhu al-Hijjah', //
];

/// One Gregorian day with its Hijri date (Umm al-Qura + Egypt adjustment, from the API).
class HijriDay {
  const HijriDay({
    required this.gregorian,
    required this.hijriDay,
    required this.hijriMonth,
    required this.hijriYear,
    required this.monthNameAr,
    required this.weekday,
  });

  final String gregorian; // YYYY-MM-DD
  final int hijriDay;
  final int hijriMonth;
  final int hijriYear;
  final String monthNameAr;
  final int weekday; // 0 = Sunday

  /// White days (13–15) are highlighted in the merged calendar.
  bool get isWhiteDay => hijriDay >= 13 && hijriDay <= 15;

  String get labelAr => '$hijriDay $monthNameAr $hijriYear';

  /// «12 Rajab 1448» in English, the API's Arabic month name otherwise.
  String label(String locale) =>
      locale == 'ar' ? labelAr : '$hijriDay ${hijriMonthsEn[(hijriMonth - 1).clamp(0, 11)]} $hijriYear';

  factory HijriDay.fromJson(Map<String, dynamic> j) => HijriDay(
        gregorian: j['gregorian'] as String,
        hijriDay: j['hijriDay'] as int,
        hijriMonth: j['hijriMonth'] as int,
        hijriYear: j['hijriYear'] as int,
        monthNameAr: j['hijriMonthNameAr'] as String,
        weekday: j['weekday'] as int,
      );

  Map<String, dynamic> toJson() => {
        'gregorian': gregorian,
        'hijriDay': hijriDay,
        'hijriMonth': hijriMonth,
        'hijriYear': hijriYear,
        'hijriMonthNameAr': monthNameAr,
        'weekday': weekday,
      };
}
