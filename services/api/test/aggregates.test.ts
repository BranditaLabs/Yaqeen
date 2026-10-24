import { describe, expect, it } from 'vitest';
import { inRollout, rolloutBucket } from '@yaqeen/contracts';
import { fillSeries, pct, suppress } from '../src/domain/aggregates.js';
import { specialDays } from '../src/domain/hijri.js';
import { addDays } from '../src/domain/points.js';

describe('k-anonymity', () => {
  it('suppresses small non-zero counts', () => {
    expect(suppress(0)).toBe(0);
    expect(suppress(5)).toBeNull();
    expect(suppress(19)).toBeNull();
    expect(suppress(20)).toBe(20);
  });

  it('percentages need at least K people in the denominator', () => {
    expect(pct(3, 10)).toBeNull();
    expect(pct(7, 40)).toBe(17.5);
  });

  it('fills every day of the range', () => {
    const s = fillSeries('2026-10-01', '2026-10-03', [{ date: '2026-10-02', n: 25 }, { date: '2026-10-03', n: 3 }], addDays);
    expect(s).toEqual([
      { date: '2026-10-01', value: 0 },
      { date: '2026-10-02', value: 25 },
      { date: '2026-10-03', value: null },
    ]);
  });
});

describe('special days', () => {
  it('marks white days, Friday and Mon/Thu', () => {
    expect(specialDays({ hijriDay: 13, hijriMonth: 5, weekday: 5 })).toEqual(['white_day', 'friday']);
    expect(specialDays({ hijriDay: 2, hijriMonth: 5, weekday: 1 })).toEqual(['mon_thu']);
  });

  it('knows Ramadan, the Eids, Arafah and Ashura — and no fasting pips on Eid', () => {
    expect(specialDays({ hijriDay: 1, hijriMonth: 9, weekday: 2 })).toEqual(['ramadan']);
    expect(specialDays({ hijriDay: 1, hijriMonth: 10, weekday: 4 })).toEqual(['eid_fitr']);
    expect(specialDays({ hijriDay: 9, hijriMonth: 12, weekday: 3 })).toEqual(['arafah']);
    expect(specialDays({ hijriDay: 13, hijriMonth: 12, weekday: 1 })).toEqual(['eid_adha']);
    expect(specialDays({ hijriDay: 10, hijriMonth: 1, weekday: 0 })).toEqual(['ashura']);
  });
});

describe('feature rollout', () => {
  // Same vectors are asserted in apps/mobile/test/core/rollout_test.dart.
  it('buckets are stable and match the Dart implementation', () => {
    expect(rolloutBucket('u1', 'recite')).toBe(53);
    expect(rolloutBucket('00000000-0000-4000-8000-000000000001', 'recite')).toBe(40);
    expect(rolloutBucket('يقين', 'recite')).toBe(43);
  });

  it('0 % hides, 100 % or unset shows', () => {
    expect(inRollout('u1', 'recite', 0)).toBe(false);
    expect(inRollout('u1', 'recite', undefined)).toBe(true);
    expect(inRollout('u1', 'recite', 54)).toBe(true);
    expect(inRollout('u1', 'recite', 53)).toBe(false);
    expect(inRollout(null, 'recite', 50)).toBe(false);
  });
});
