import '../../features/prayer/domain/prayer_calculator.dart';
import 'routine_slot.dart';

export 'routine_slot.dart';

/// How a prayer alerts: full adhan, a plain notification, or nothing (spec §5.17).
enum AlertMode { adhan, notify, silent }

enum AdhanVoice { makkah, madinah, calm, takbir }

enum MushafTheme { paper, white, night }

enum QuranScript { uthmani, indopak }

/// A place used for prayer times. Coordinates never leave the device (spec §5.5).
class Place {
  const Place({
    required this.nameAr,
    required this.nameEn,
    required this.country,
    required this.lat,
    required this.lng,
    required this.timezone,
    this.auto = false,
  });

  final String nameAr;
  final String nameEn;
  final String country;
  final double lat;
  final double lng;
  final String timezone;

  /// true = from the device's location, false = picked from the city list.
  final bool auto;

  String name(String locale) => locale == 'ar' ? nameAr : nameEn;

  Map<String, dynamic> toJson() => {'ar': nameAr, 'en': nameEn, 'c': country, 'lat': lat, 'lng': lng, 'tz': timezone, 'auto': auto};
  factory Place.fromJson(Map<String, dynamic> j) => Place(
        nameAr: j['ar'] as String,
        nameEn: j['en'] as String,
        country: j['c'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        timezone: j['tz'] as String,
        auto: (j['auto'] as bool?) ?? false,
      );

  static const cairo = Place(nameAr: 'القاهرة', nameEn: 'Cairo', country: 'EG', lat: 30.0444, lng: 31.2357, timezone: 'Africa/Cairo');
}

/// Everything the user can set. Local source of truth (spec §6.2); a subset syncs to the API.
class AppSettings {
  const AppSettings({
    this.locale = 'ar',
    this.script = QuranScript.uthmani,
    this.quranFontSize = 26,
    this.mushafTheme = MushafTheme.paper,
    this.comfortableSpacing = false,
    this.keepAwake = true,
    this.place,
    this.method = CalcMethod.egypt,
    this.asr = AsrSchool.standard,
    this.highLatitude = HighLatitudeRule.twilightAngle,
    this.adjustments = const PrayerAdjustments(),
    this.alertModes = defaultAlertModes,
    this.adhanVoice = AdhanVoice.makkah,
    this.preReminderMinutes = 10,
    this.morningAzkar = true,
    this.eveningAzkar = true,
    this.kahfFriday = true,
    this.wirdMissing = false,
    this.hifzDue = true,
    this.quietStartMinutes = 21 * 60,
    this.quietEndMinutes = 5 * 60,
    this.quietHours = true,
    this.haptics = true,
    this.azkarSound = false,
    this.volumeKeysCount = false,
    this.wirdGoalPages = 2,
    this.quranSlot = defaultQuranSlot,
    this.hifzSlot = RoutineSlot.off,
    this.dhikrSlot = RoutineSlot.off,
    this.hijriOffsetDays = 0,
    this.onboardingStep = 0,
    this.onboardingCompletedAt,
    this.lastSplashDay,
    this.readerHintSeen = false,
  });

  static const defaultAlertModes = {
    PrayerName.fajr: AlertMode.adhan,
    PrayerName.sunrise: AlertMode.silent,
    PrayerName.dhuhr: AlertMode.adhan,
    PrayerName.asr: AlertMode.adhan,
    PrayerName.maghrib: AlertMode.adhan,
    PrayerName.isha: AlertMode.notify,
  };

  /// Quran reading a quarter of an hour after Fajr until the user picks their own time.
  static const defaultQuranSlot = RoutineSlot.afterPrayer(PrayerName.fajr);

  /// Font sizes for S / M / L / XL (spec §5.4).
  static const fontSizes = [22.0, 26.0, 30.0, 34.0];

  final String locale;
  final QuranScript script;
  final double quranFontSize;
  final MushafTheme mushafTheme;
  final bool comfortableSpacing;
  final bool keepAwake;
  final Place? place;
  final CalcMethod method;
  final AsrSchool asr;
  final HighLatitudeRule highLatitude;
  final PrayerAdjustments adjustments;
  final Map<PrayerName, AlertMode> alertModes;
  final AdhanVoice adhanVoice;

  /// 0 = no reminder before the adhan.
  final int preReminderMinutes;
  final bool morningAzkar;
  final bool eveningAzkar;
  final bool kahfFriday;
  final bool wirdMissing;
  final bool hifzDue;

  /// Minutes since midnight. Quiet hours never silence the adhan.
  final int quietStartMinutes;
  final int quietEndMinutes;
  final bool quietHours;
  final bool haptics;
  final bool azkarSound;
  final bool volumeKeysCount;
  final int wirdGoalPages;

  /// The daily routine (routine step, spec §5.2): when the user reads Quran, reviews hifz and
  /// does a dhikr session. Drives the Home timeline and the local reminders. Device-only.
  final RoutineSlot quranSlot;
  final RoutineSlot hifzSlot;
  final RoutineSlot dhikrSlot;
  final int hijriOffsetDays;
  final int onboardingStep;
  final DateTime? onboardingCompletedAt;

  /// YYYY-MM-DD of the last full splash animation (later launches that day use the short hold).
  final String? lastSplashDay;
  final bool readerHintSeen;

  bool get onboarded => onboardingCompletedAt != null;
  Place get placeOrDefault => place ?? Place.cairo;
  PrayerParams prayerParams({bool ramadan = false}) =>
      PrayerParams(method: method, asr: asr, highLatitude: highLatitude, adjustments: adjustments, ramadan: ramadan);

  AppSettings copyWith({
    String? locale,
    QuranScript? script,
    double? quranFontSize,
    MushafTheme? mushafTheme,
    bool? comfortableSpacing,
    bool? keepAwake,
    Place? place,
    CalcMethod? method,
    AsrSchool? asr,
    HighLatitudeRule? highLatitude,
    PrayerAdjustments? adjustments,
    Map<PrayerName, AlertMode>? alertModes,
    AdhanVoice? adhanVoice,
    int? preReminderMinutes,
    bool? morningAzkar,
    bool? eveningAzkar,
    bool? kahfFriday,
    bool? wirdMissing,
    bool? hifzDue,
    int? quietStartMinutes,
    int? quietEndMinutes,
    bool? quietHours,
    bool? haptics,
    bool? azkarSound,
    bool? volumeKeysCount,
    int? wirdGoalPages,
    RoutineSlot? quranSlot,
    RoutineSlot? hifzSlot,
    RoutineSlot? dhikrSlot,
    int? hijriOffsetDays,
    int? onboardingStep,
    DateTime? onboardingCompletedAt,
    String? lastSplashDay,
    bool? readerHintSeen,
  }) =>
      AppSettings(
        locale: locale ?? this.locale,
        script: script ?? this.script,
        quranFontSize: quranFontSize ?? this.quranFontSize,
        mushafTheme: mushafTheme ?? this.mushafTheme,
        comfortableSpacing: comfortableSpacing ?? this.comfortableSpacing,
        keepAwake: keepAwake ?? this.keepAwake,
        place: place ?? this.place,
        method: method ?? this.method,
        asr: asr ?? this.asr,
        highLatitude: highLatitude ?? this.highLatitude,
        adjustments: adjustments ?? this.adjustments,
        alertModes: alertModes ?? this.alertModes,
        adhanVoice: adhanVoice ?? this.adhanVoice,
        preReminderMinutes: preReminderMinutes ?? this.preReminderMinutes,
        morningAzkar: morningAzkar ?? this.morningAzkar,
        eveningAzkar: eveningAzkar ?? this.eveningAzkar,
        kahfFriday: kahfFriday ?? this.kahfFriday,
        wirdMissing: wirdMissing ?? this.wirdMissing,
        hifzDue: hifzDue ?? this.hifzDue,
        quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
        quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
        quietHours: quietHours ?? this.quietHours,
        haptics: haptics ?? this.haptics,
        azkarSound: azkarSound ?? this.azkarSound,
        volumeKeysCount: volumeKeysCount ?? this.volumeKeysCount,
        wirdGoalPages: wirdGoalPages ?? this.wirdGoalPages,
        quranSlot: quranSlot ?? this.quranSlot,
        hifzSlot: hifzSlot ?? this.hifzSlot,
        dhikrSlot: dhikrSlot ?? this.dhikrSlot,
        hijriOffsetDays: hijriOffsetDays ?? this.hijriOffsetDays,
        onboardingStep: onboardingStep ?? this.onboardingStep,
        onboardingCompletedAt: onboardingCompletedAt ?? this.onboardingCompletedAt,
        lastSplashDay: lastSplashDay ?? this.lastSplashDay,
        readerHintSeen: readerHintSeen ?? this.readerHintSeen,
      );

  Map<String, dynamic> toJson() => {
        'locale': locale,
        'script': script.name,
        'quranFontSize': quranFontSize,
        'mushafTheme': mushafTheme.name,
        'comfortableSpacing': comfortableSpacing,
        'keepAwake': keepAwake,
        'place': place?.toJson(),
        'method': method.wire,
        'asr': asr.wire,
        'highLatitude': highLatitude.name,
        'adjustments': adjustments.toJson(),
        'alertModes': {for (final e in alertModes.entries) e.key.name: e.value.name},
        'adhanVoice': adhanVoice.name,
        'preReminderMinutes': preReminderMinutes,
        'morningAzkar': morningAzkar,
        'eveningAzkar': eveningAzkar,
        'kahfFriday': kahfFriday,
        'wirdMissing': wirdMissing,
        'hifzDue': hifzDue,
        'quietStartMinutes': quietStartMinutes,
        'quietEndMinutes': quietEndMinutes,
        'quietHours': quietHours,
        'haptics': haptics,
        'azkarSound': azkarSound,
        'volumeKeysCount': volumeKeysCount,
        'wirdGoalPages': wirdGoalPages,
        'quranSlot': quranSlot.toJson(),
        'hifzSlot': hifzSlot.toJson(),
        'dhikrSlot': dhikrSlot.toJson(),
        'hijriOffsetDays': hijriOffsetDays,
        'onboardingStep': onboardingStep,
        'onboardingCompletedAt': onboardingCompletedAt?.toIso8601String(),
        'lastSplashDay': lastSplashDay,
        'readerHintSeen': readerHintSeen,
      };

  /// Tolerant: unknown or missing keys fall back to defaults (older app versions, partial writes).
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    E byName<E extends Enum>(List<E> values, String k, E fallback) => values.firstWhere((v) => v.name == j[k], orElse: () => fallback);
    final modes = (j['alertModes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AppSettings(
      locale: pick('locale', d.locale) == 'en' ? 'en' : 'ar',
      script: byName(QuranScript.values, 'script', d.script),
      quranFontSize: (j['quranFontSize'] as num?)?.toDouble().clamp(22.0, 34.0) ?? d.quranFontSize,
      mushafTheme: byName(MushafTheme.values, 'mushafTheme', d.mushafTheme),
      comfortableSpacing: pick('comfortableSpacing', d.comfortableSpacing),
      keepAwake: pick('keepAwake', d.keepAwake),
      place: j['place'] is Map ? Place.fromJson((j['place'] as Map).cast<String, dynamic>()) : null,
      method: CalcMethod.fromWire(j['method'] as String?),
      asr: AsrSchool.fromWire(j['asr'] as String?),
      highLatitude: byName(HighLatitudeRule.values, 'highLatitude', d.highLatitude),
      adjustments: j['adjustments'] is Map ? PrayerAdjustments.fromJson((j['adjustments'] as Map).cast<String, dynamic>()) : d.adjustments,
      alertModes: {
        for (final p in PrayerName.values)
          p: AlertMode.values.firstWhere((m) => m.name == modes[p.name], orElse: () => defaultAlertModes[p]!),
      },
      adhanVoice: byName(AdhanVoice.values, 'adhanVoice', d.adhanVoice),
      preReminderMinutes: pick('preReminderMinutes', d.preReminderMinutes),
      morningAzkar: pick('morningAzkar', d.morningAzkar),
      eveningAzkar: pick('eveningAzkar', d.eveningAzkar),
      kahfFriday: pick('kahfFriday', d.kahfFriday),
      wirdMissing: pick('wirdMissing', d.wirdMissing),
      hifzDue: pick('hifzDue', d.hifzDue),
      quietStartMinutes: pick('quietStartMinutes', d.quietStartMinutes),
      quietEndMinutes: pick('quietEndMinutes', d.quietEndMinutes),
      quietHours: pick('quietHours', d.quietHours),
      haptics: pick('haptics', d.haptics),
      azkarSound: pick('azkarSound', d.azkarSound),
      volumeKeysCount: pick('volumeKeysCount', d.volumeKeysCount),
      wirdGoalPages: pick('wirdGoalPages', d.wirdGoalPages),
      // Before the routine existed the wird had a fixed clock time; a changed one is kept as such.
      quranSlot: RoutineSlot.fromJson(
        j['quranSlot'],
        j['wirdReminderMinutes'] is int && j['wirdReminderMinutes'] != 6 * 60
            ? RoutineSlot.at((j['wirdReminderMinutes'] as int).clamp(0, 24 * 60 - 1))
            : d.quranSlot,
      ),
      hifzSlot: RoutineSlot.fromJson(j['hifzSlot'], d.hifzSlot),
      dhikrSlot: RoutineSlot.fromJson(j['dhikrSlot'], d.dhikrSlot),
      hijriOffsetDays: pick('hijriOffsetDays', d.hijriOffsetDays),
      onboardingStep: pick('onboardingStep', d.onboardingStep),
      onboardingCompletedAt: DateTime.tryParse(j['onboardingCompletedAt'] as String? ?? ''),
      lastSplashDay: j['lastSplashDay'] as String?,
      readerHintSeen: pick('readerHintSeen', d.readerHintSeen),
    );
  }

  /// The fields the API stores (spec §6.2). Coordinates are deliberately absent.
  Map<String, dynamic> serverPatch() => {
        'locale': locale,
        'city': place?.nameEn,
        'timezone': placeOrDefault.timezone,
        'prayerMethod': method.apiWire,
        'asrSchool': asr.wire,
        'hijriOffsetDays': hijriOffsetDays,
      };
}
