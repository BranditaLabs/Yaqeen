import '../../../core/settings/app_settings.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/prayer_calculator.dart';
import '../domain/qibla.dart';

String prayerLabel(AppLocalizations t, PrayerName p, {bool friday = false}) => switch (p) {
      PrayerName.fajr => t.prayerFajr,
      PrayerName.sunrise => t.prayerSunrise,
      PrayerName.dhuhr => friday ? t.prayerJumuah : t.prayerDhuhr,
      PrayerName.asr => t.prayerAsr,
      PrayerName.maghrib => t.prayerMaghrib,
      PrayerName.isha => t.prayerIsha,
    };

String methodLabel(AppLocalizations t, CalcMethod m) => switch (m) {
      CalcMethod.egypt => t.methodEgypt,
      CalcMethod.mwl => t.methodMwl,
      CalcMethod.ummAlQura => t.methodUmmAlQura,
      CalcMethod.karachi => t.methodKarachi,
      CalcMethod.isna => t.methodIsna,
      CalcMethod.dubai => t.methodDubai,
      CalcMethod.kuwait => t.methodKuwait,
      CalcMethod.qatar => t.methodQatar,
      CalcMethod.singapore => t.methodSingapore,
      CalcMethod.turkey => t.methodTurkey,
    };

String directionLabel(AppLocalizations t, CompassPoint p) => switch (p) {
      CompassPoint.n => t.dirN,
      CompassPoint.ne => t.dirNE,
      CompassPoint.e => t.dirE,
      CompassPoint.se => t.dirSE,
      CompassPoint.s => t.dirS,
      CompassPoint.sw => t.dirSW,
      CompassPoint.w => t.dirW,
      CompassPoint.nw => t.dirNW,
    };

String alertLabel(AppLocalizations t, AlertMode m) => switch (m) {
      AlertMode.adhan => t.alertAdhan,
      AlertMode.notify => t.alertNotify,
      AlertMode.silent => t.alertSilent,
    };
