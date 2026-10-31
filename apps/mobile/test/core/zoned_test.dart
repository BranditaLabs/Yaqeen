import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/time/zoned.dart';

void main() {
  test('addDays moves by calendar days, across month ends and DST switches, keeping UTC-ness', () {
    // Egypt falls back on the last Friday of October; the plan must still end on the right date.
    expect(Zoned.isoDate(Zoned.addDays(DateTime(2026, 10, 20), 29)), '2026-11-18');
    expect(Zoned.isoDate(Zoned.addDays(DateTime(2026, 10, 28), 30)), '2026-11-27');
    expect(Zoned.addDays(DateTime(2026, 10, 31), 1), DateTime(2026, 11, 1));
    expect(Zoned.addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    final u = Zoned.addDays(DateTime.utc(2026, 12, 31), 1);
    expect(u.isUtc, isTrue);
    expect(u, DateTime.utc(2027, 1, 1));
  });
}
