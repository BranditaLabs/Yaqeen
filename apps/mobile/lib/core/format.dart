import 'package:intl/intl.dart';

/// The app always shows Western digits (0-9), in both Arabic and English.
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
}
