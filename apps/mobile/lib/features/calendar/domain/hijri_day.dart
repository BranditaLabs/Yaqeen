/// English Hijri month names (the API sends only the Arabic name and the month number).
const hijriMonthsEn = [
  'Muharram', 'Safar', 'Rabiʿ al-Awwal', 'Rabiʿ al-Thani', 'Jumada al-Ula', 'Jumada al-Akhirah',
  'Rajab', 'Shaʿban', 'Ramadan', 'Shawwal', 'Dhu al-Qaʿdah', 'Dhu al-Hijjah', //
];

/// The month's name in the app language: the API's Arabic name, or the English table.
String hijriMonthNameFor(int month, String nameAr, String locale) => locale == 'ar' ? nameAr : hijriMonthsEn[(month - 1).clamp(0, 11)];

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

  String monthName(String locale) => hijriMonthNameFor(hijriMonth, monthNameAr, locale);

  /// «12 Rajab 1448» in English, the API's Arabic label otherwise.
  String label(String locale) => locale == 'ar' ? labelAr : '$hijriDay ${monthName(locale)} $hijriYear';

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
