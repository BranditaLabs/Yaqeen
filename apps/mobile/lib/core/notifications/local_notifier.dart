import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../time/zoned.dart';
import 'notification_planner.dart';

/// Title/body for a planned notification (localised by the caller — see NotificationCopy).
typedef NotificationCopyFn = (String title, String body) Function(PlannedNotification n);

/// Channel names (localised), keyed by [NotificationChannel].
typedef ChannelNames = Map<NotificationChannel, String>;

/// flutter_local_notifications adapter for [LocalNotificationScheduler] (spec §6.5).
///
/// - Android channels: adhan · reminders · challenge · offers (users can silence each in the OS).
/// - Exact alarms (Android 12+) when granted; otherwise inexact — the settings screen explains it.
/// - Custom adhan audio is used only when the licensed recordings are bundled
///   (`--dart-define=ADHAN_SOUNDS=true`, files in android/app/src/main/res/raw and ios/Runner);
///   until then the adhan channel uses the default sound so a missing file can never crash.
class PluginLocalNotifier implements LocalNotificationScheduler {
  PluginLocalNotifier({required this.copy, required this.channelNames, required this.timezone, required this.adhanVoice});

  final NotificationCopyFn Function() copy;
  final ChannelNames Function() channelNames;

  /// The place's IANA zone (times are scheduled on its wall clock).
  final String Function() timezone;
  final String Function() adhanVoice;

  static const bundledAdhan = bool.fromEnvironment('ADHAN_SOUNDS');

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<Uri>.broadcast();
  Future<void>? _init;

  /// Deep links of tapped notifications.
  Stream<Uri> get taps => _taps.stream;

  /// Idempotent and shared by concurrent callers; started after the first frame, so it never
  /// delays start-up. A failure is retried on the next call.
  Future<void> init() => _init ??= _setUp().catchError((Object e) {
        _init = null;
        throw e;
      });

  Future<void> _setUp() async {
    Zoned.ensureInitialized();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (r) {
        final link = r.payload;
        if (link != null && link.isNotEmpty) _taps.add(Uri.parse(link));
      },
    );
    // Campaign pushes (FCM) post to the offers channel; create it now so the first one, which can
    // arrive before any local offer is scheduled, lands there with its localized name.
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    const offers = NotificationChannel.offers;
    await android?.createNotificationChannel(AndroidNotificationChannel(offers.name, channelNames()[offers] ?? offers.name));
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final link = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && link != null) _taps.add(Uri.parse(link));
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true, badge: true) ?? false;
  }

  /// Android 12+: ask for exact alarms (prayer alerts are alarm-clock-like). Returns whether granted.
  Future<bool> ensureExactAlarms() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (await android?.canScheduleExactNotifications() ?? true) return true;
    return await android?.requestExactAlarmsPermission() ?? false;
  }

  NotificationDetails _details(PlannedNotification n) {
    final names = channelNames();
    final channel = n.channel;
    final adhan = channel == NotificationChannel.adhan;
    final voice = adhanVoice();
    final sound = adhan && bundledAdhan ? 'adhan_$voice${n.prayer == Prayer.fajr ? '_fajr' : ''}' : null;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        sound == null ? channel.name : 'adhan_$voice',
        names[channel] ?? channel.name,
        importance: adhan ? Importance.max : Importance.defaultImportance,
        priority: adhan ? Priority.high : Priority.defaultPriority,
        category: adhan ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
        sound: sound == null ? null : RawResourceAndroidNotificationSound(sound),
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(
        sound: sound == null ? null : '$sound.caf',
        interruptionLevel: adhan ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
        threadIdentifier: adhan ? 'yaqeen-prayer' : 'yaqeen-reminders',
      ),
    );
  }

  @override
  Future<void> replaceAll(List<PlannedNotification> plan) async {
    await init();
    await _plugin.cancelAllPendingNotifications();
    final exact = Platform.isAndroid ? await ensureExactAlarmsQuietly() : true;
    final loc = Zoned.location(timezone());
    final text = copy();
    for (final n in plan) {
      final (title, body) = text(n);
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(n.at.toUtc(), loc),
        notificationDetails: _details(n),
        androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: n.link,
      );
    }
  }

  /// Checks without prompting (prompting happens from the settings screen).
  Future<bool> ensureExactAlarmsQuietly() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAllPendingNotifications();
  }
}
