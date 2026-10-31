import { describe, expect, it } from 'vitest';
import { CAIRO, coordsFor, prayerMinutes } from '../src/domain/prayer-times.js';

describe('server prayer times (push guardrails)', () => {
  it('uses the picked city, then the zone, then Cairo', () => {
    expect(coordsFor('Riyadh', 'Asia/Riyadh')).toEqual({ lat: 24.64, lng: 46.77 });
    expect(coordsFor(null, 'Asia/Riyadh')).toEqual({ lat: 24.64, lng: 46.77 });
    expect(coordsFor('Alexandria', 'Africa/Cairo').lat).toBeCloseTo(31.2, 1);
    expect(coordsFor('Nowhere', 'Mars/Base')).toEqual(CAIRO);
  });

  it('follows the user rather than Cairo', () => {
    const day = new Date('2026-10-27T09:00:00Z');
    const cairo = prayerMinutes(day, 'Africa/Cairo');
    const alex = prayerMinutes(day, 'Africa/Cairo', coordsFor('Alexandria', 'Africa/Cairo'));
    const aswan = prayerMinutes(day, 'Africa/Cairo', coordsFor('Aswan', 'Africa/Cairo'));
    // Same clock, different sun: Aswan prays Maghrib before Alexandria.
    expect(aswan[3]).toBeLessThan(alex[3]!);
    expect(cairo).toHaveLength(5);
    // Umm al-Qura sets Isha 90 min after Maghrib.
    const riyadh = prayerMinutes(day, 'Asia/Riyadh', coordsFor('Riyadh', 'Asia/Riyadh'), 'umm_al_qura');
    expect(riyadh[4]! - riyadh[3]!).toBe(90);
  });
});
