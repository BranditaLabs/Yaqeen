import 'package:intl/intl.dart';

/// The app always shows Western digits (0-9), in both Arabic and English (`ar-EG-u-nu-latn`).
/// Mushaf ayah markers are the only exception and use [toArabicIndic].
abstract final class YqFormat {
  static final _int = NumberFormat.decimalPattern('en_US');

  static String number(num value) => _int.format(value);

  static String clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  static String toArabicIndic(int n) {
    const digits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => digits[int.parse(c)]).join();
  }

  static const _weekdaysAr = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  static const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  static const _monthsEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// 12-hour wall clock: «3:55 م» / «3:55 PM». [suffix] false → «3:55».
  static String time(DateTime local, String locale, {bool suffix = true}) {
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final base = '$h:${local.minute.toString().padLeft(2, '0')}';
    if (!suffix) return base;
    final pm = local.hour >= 12;
    return locale == 'ar' ? '$base ${pm ? 'م' : 'ص'}' : '$base ${pm ? 'PM' : 'AM'}';
  }

  static String weekday(DateTime d, String locale) => (locale == 'ar' ? _weekdaysAr : _weekdaysEn)[d.weekday - 1];

  static String month(int m, String locale) => (locale == 'ar' ? _monthsAr : _monthsEn)[m - 1];

  /// «19 أكتوبر» / «19 October».
  static String dayMonth(DateTime d, String locale) =>
      locale == 'ar' ? '${d.day} ${month(d.month, locale)}' : '${d.day} ${month(d.month, locale)}';

  /// «الإثنين 19 أكتوبر» / «Monday 19 October».
  static String weekdayDayMonth(DateTime d, String locale) => '${weekday(d, locale)} ${dayMonth(d, locale)}';

  /// «19 أكتوبر 2026».
  static String fullDate(DateTime d, String locale) => '${dayMonth(d, locale)} ${d.year}';

  /// Minutes since midnight → «5:00 ص».
  static String minutesOfDay(int minutes, String locale) => time(DateTime(2000, 1, 1, minutes ~/ 60, minutes % 60), locale);
}
