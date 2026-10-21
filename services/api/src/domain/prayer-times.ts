/**
 * Server-side prayer times, used ONLY to keep marketing pushes away from prayer.
 * (The app computes the user's real times on-device from their location.)
 */
import { CalculationMethod, Coordinates, PrayerTimes } from 'adhan';

export const CAIRO = { lat: 30.0444, lng: 31.2357 };

/** Prayer times for `date` as minutes since local midnight in `timeZone`. */
export function prayerMinutes(date: Date, timeZone: string, coords = CAIRO): number[] {
  const pt = new PrayerTimes(new Coordinates(coords.lat, coords.lng), date, CalculationMethod.Egyptian());
  const fmt = new Intl.DateTimeFormat('en-US', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  return [pt.fajr, pt.dhuhr, pt.asr, pt.maghrib, pt.isha].map((t) => {
    const [h, m] = fmt.format(t).split(':').map(Number);
    return (h ?? 0) * 60 + (m ?? 0);
  });
}
