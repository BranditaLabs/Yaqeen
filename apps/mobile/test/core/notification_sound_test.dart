import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/notifications/notification_planner.dart';

PlannedNotification _n(ReminderKind kind, {PrayerAlert? alert, Prayer? prayer}) =>
    PlannedNotification(id: 1, at: DateTime(2026, 10, 28, 15), kind: kind, alert: alert, prayer: prayer);

void main() {
  test('the adhan keeps its licensed voice (no Yaqeen sound)', () {
    final n = _n(ReminderKind.adhan, alert: PrayerAlert.adhan, prayer: Prayer.asr);
    expect(n.channel, NotificationChannel.adhan);
    expect(n.sound, isNull);
  });

  test('every reminder kind has a Yaqeen sound', () {
    final expected = {
      ReminderKind.adhan: NotificationSound.prayer, // alert «تنبيه»
      ReminderKind.prePrayer: NotificationSound.prayerSoon,
      ReminderKind.morningAzkar: NotificationSound.azkar,
      ReminderKind.eveningAzkar: NotificationSound.azkar,
      ReminderKind.dhikr: NotificationSound.azkar,
      ReminderKind.wird: NotificationSound.quran,
      ReminderKind.wirdMissing: NotificationSound.quran,
      ReminderKind.kahfFriday: NotificationSound.quran,
      ReminderKind.khatma: NotificationSound.quran,
      ReminderKind.hifzDue: NotificationSound.hifz,
      ReminderKind.suhoor: NotificationSound.suhoor,
      ReminderKind.iftar: NotificationSound.iftar,
    };
    expect(expected.keys.toSet(), ReminderKind.values.toSet());
    for (final e in expected.entries) {
      expect(_n(e.key, alert: PrayerAlert.notify).sound, e.value, reason: e.key.name);
    }
  });

  test('push channels match what the API sends', () {
    expect(NotificationSound.forPushChannel(NotificationChannel.challenge).channelId, 'challenge');
    expect(NotificationSound.forPushChannel(NotificationChannel.offers).channelId, 'offers');
    expect(NotificationSound.challenge.resource, 'yq_challenge');
    expect(NotificationSound.offers.resource, 'yq_offers');
  });

  test('every sound is bundled for Android and iOS', () {
    for (final s in NotificationSound.values) {
      expect(File('android/app/src/main/res/raw/${s.resource}.ogg').existsSync(), isTrue, reason: s.resource);
      expect(File('ios/Runner/Sounds/${s.resource}.caf').existsSync(), isTrue, reason: s.resource);
    }
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    for (final s in NotificationSound.values) {
      expect(pbx, contains('${s.resource}.caf in Resources'), reason: 'add ${s.resource}.caf to the Runner target');
    }
  });
}
