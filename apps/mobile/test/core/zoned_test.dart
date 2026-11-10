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

  test('nextMidnight is the instant the place\'s date changes', () {
    Zoned.ensureInitialized();
    // Cairo is UTC+2 in November: 21:59Z is 23:59 local, so the day turns at 22:00Z.
    expect(Zoned.nextMidnight('Africa/Cairo', DateTime.utc(2026, 11, 10, 21, 59)), DateTime.utc(2026, 11, 10, 22));
    expect(Zoned.nextMidnight('Africa/Cairo', DateTime.utc(2026, 11, 10, 22, 30)), DateTime.utc(2026, 11, 11, 22));
    expect(Zoned.nextMidnight('Asia/Riyadh', DateTime.utc(2026, 11, 10, 12)), DateTime.utc(2026, 11, 10, 21));
  });
}
