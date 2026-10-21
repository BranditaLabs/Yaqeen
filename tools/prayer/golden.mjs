// Generates apps/mobile/test/fixtures/prayer_golden.json from the adhan JS library (the reference
// the Dart engine is ported from). Run with TZ=UTC:
//   TZ=UTC node tools/prayer/golden.mjs
import { writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

// `adhan` is a dependency of services/api; resolve it from there.
const require = createRequire(new URL('../../services/api/package.json', import.meta.url));
const { CalculationMethod, Coordinates, HighLatitudeRule, Madhab, PrayerTimes } = await import(pathToFileURL(require.resolve('adhan')).href);

const places = [
  { name: 'Cairo', lat: 30.0444, lng: 31.2357, method: 'Egyptian', wire: 'egypt' },
  { name: 'Alexandria', lat: 31.2001, lng: 29.9187, method: 'Egyptian', wire: 'egypt' },
  { name: 'Aswan', lat: 24.0889, lng: 32.8998, method: 'Egyptian', wire: 'egypt' },
  { name: 'Makkah', lat: 21.4225, lng: 39.8262, method: 'UmmAlQura', wire: 'umm_al_qura' },
  { name: 'London', lat: 51.5074, lng: -0.1278, method: 'MuslimWorldLeague', wire: 'mwl' },
  { name: 'Jakarta', lat: -6.2088, lng: 106.8456, method: 'Singapore', wire: 'singapore' },
  { name: 'Istanbul', lat: 41.0082, lng: 28.9784, method: 'Turkey', wire: 'turkey' },
  { name: 'Dubai', lat: 25.2048, lng: 55.2708, method: 'Dubai', wire: 'dubai' },
];
// Includes Egypt's DST switches (last Friday of April, last Thursday of October 2026) and solstices.
const dates = ['2026-01-15', '2026-03-20', '2026-04-23', '2026-04-24', '2026-06-21', '2026-10-20', '2026-10-29', '2026-10-30', '2026-12-21'];
const out = [];
for (const p of places) {
  for (const asr of ['standard', 'hanafi']) {
    for (const d of dates) {
      const [y, m, day] = d.split('-').map(Number);
      const params = CalculationMethod[p.method]();
      params.madhab = asr === 'hanafi' ? Madhab.Hanafi : Madhab.Shafi;
      params.highLatitudeRule = HighLatitudeRule.TwilightAngle;
      // Local calendar date: construct in the process TZ (run with TZ=UTC) like the app does.
      const t = new PrayerTimes(new Coordinates(p.lat, p.lng), new Date(y, m - 1, day), params);
      out.push({ place: p.name, lat: p.lat, lng: p.lng, method: p.wire, asr, date: d,
        fajr: t.fajr.toISOString(), sunrise: t.sunrise.toISOString(), dhuhr: t.dhuhr.toISOString(),
        asrTime: t.asr.toISOString(), maghrib: t.maghrib.toISOString(), isha: t.isha.toISOString() });
    }
  }
}
writeFileSync(new URL('../../apps/mobile/test/fixtures/prayer_golden.json', import.meta.url), JSON.stringify(out, null, 1));
console.log(`wrote ${out.length} golden days`);
