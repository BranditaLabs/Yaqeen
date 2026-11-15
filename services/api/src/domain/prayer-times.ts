/**
 * Server-side prayer times, used ONLY to keep marketing pushes away from prayer.
 * (The app computes the user's real times on-device from their location.) The server knows only
 * the city name the user picked and their time zone, so it uses that city's coarse coordinates.
 */
import { CalculationMethod, Coordinates, type CalculationParameters, PrayerTimes } from 'adhan';
import type { PrayerMethod } from '@yaqeen/contracts';
import { CITY_COORDS, ZONE_COORDS } from './city-coords.js';

export const CAIRO = { lat: 30.0444, lng: 31.2357 };

export interface Coords {
  lat: number;
  lng: number;
}

/** The picked city if we know it, else the largest city in the user's zone, else Cairo. */
export function coordsFor(city: string | null | undefined, timeZone: string): Coords {
  const hit = (city && CITY_COORDS[`${city}|${timeZone}`]) || ZONE_COORDS[timeZone];
  return hit ? { lat: hit[0], lng: hit[1] } : CAIRO;
}

function params(method: PrayerMethod | string | undefined): CalculationParameters {
  switch (method) {
    case 'mwl':
      return CalculationMethod.MuslimWorldLeague();
    case 'umm_al_qura':
      return CalculationMethod.UmmAlQura();
    default:
      return CalculationMethod.Egyptian();
  }
}

/** Prayer times for `date` as minutes since local midnight in `timeZone`. */
export function prayerMinutes(date: Date, timeZone: string, coords: Coords = CAIRO, method?: PrayerMethod | string): number[] {
  const pt = new PrayerTimes(new Coordinates(coords.lat, coords.lng), date, params(method));
  const fmt = new Intl.DateTimeFormat('en-US', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
  return [pt.fajr, pt.dhuhr, pt.asr, pt.maghrib, pt.isha].map((t) => {
    const [h, m] = fmt.format(t).split(':').map(Number);
    return (h ?? 0) * 60 + (m ?? 0);
  });
}
