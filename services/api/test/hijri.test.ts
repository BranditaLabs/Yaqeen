import { describe, expect, it } from 'vitest';
import type { HijriDay } from '@yaqeen/contracts';
import { HIJRI_MONTHS_AR, applyAdjustments, fromAlAdhan, resolveOffset, validateSequence } from '../src/domain/hijri.js';
import { addDays } from '../src/domain/points.js';

/**
 * Build a run of UAQ days from known month starts (verified against AlAdhan UAQ):
 *   1 Jumada I 1448 = 2026-10-12 (30 days), 1 Jumada II 1448 = 2026-11-11 (29 days), 1 Rajab = 2026-12-10.
 */
function uaqRun(from: string, to: string): HijriDay[] {
  const starts = [
    { g: '2026-10-12', m: 5, len: 30 },
    { g: '2026-11-11', m: 6, len: 29 },
    { g: '2026-12-10', m: 7, len: 30 },
  ];
  const out: HijriDay[] = [];
  for (let g = from; g <= to; g = addDays(g, 1)) {
    const s = [...starts].reverse().find((x) => x.g <= g)!;
    const day = Math.round((Date.parse(g) - Date.parse(s.g)) / 86_400_000) + 1;
    out.push({
      gregorian: g,
      weekday: new Date(g).getUTCDay(),
      hijriDay: day,
      hijriMonth: s.m,
      hijriYear: 1448,
      hijriMonthNameAr: HIJRI_MONTHS_AR[s.m - 1]!,
    });
  }
  return out;
}

describe('resolveOffset', () => {
  const adj = [
    { offsetDays: 1, effectiveHijriYear: 1448, effectiveHijriMonth: 6, createdAt: new Date('2026-11-10') },
    { offsetDays: 0, effectiveHijriYear: 1448, effectiveHijriMonth: 7, createdAt: new Date('2026-12-09') },
  ];
  it('picks the latest adjustment at or before the month', () => {
    expect(resolveOffset(adj, 1448, 5)).toBe(0);
    expect(resolveOffset(adj, 1448, 6)).toBe(1);
    expect(resolveOffset(adj, 1448, 7)).toBe(0);
    expect(resolveOffset(adj, 1449, 1)).toBe(0);
  });
});

describe('applyAdjustments', () => {
  it('is the identity with no adjustments', () => {
    const run = uaqRun('2026-11-08', '2026-11-14');
    expect(applyAdjustments(run, [])).toEqual(run);
  });

  it('+1 in Jumada II shifts the month start one day later', () => {
    const run = uaqRun('2026-11-08', '2026-11-14');
    const adj = [{ offsetDays: 1, effectiveHijriYear: 1448, effectiveHijriMonth: 6, createdAt: new Date() }];
    const out = applyAdjustments(run, adj);
    const nov11 = out.find((d) => d.gregorian === '2026-11-11')!;
    const nov12 = out.find((d) => d.gregorian === '2026-11-12')!;
    expect([nov11.hijriDay, nov11.hijriMonth]).toEqual([30, 5]);
    expect([nov12.hijriDay, nov12.hijriMonth]).toEqual([1, 6]);
  });

  it('flags an impossible 31-day month so the admin preview can block it', () => {
    // UAQ Jumada I already has 30 days; delaying Jumada II by a day makes 30 appear twice.
    const run = uaqRun('2026-11-08', '2026-11-14');
    const adj = [{ offsetDays: 1, effectiveHijriYear: 1448, effectiveHijriMonth: 6, createdAt: new Date() }];
    const warnings = validateSequence(applyAdjustments(run, adj));
    expect(warnings.length).toBeGreaterThan(0);
  });

  it('a clean UAQ run has no warnings', () => {
    expect(validateSequence(uaqRun('2026-10-12', '2026-12-20'))).toEqual([]);
  });
});

describe('fromAlAdhan', () => {
  it('maps the AlAdhan payload', () => {
    const d = fromAlAdhan({
      gregorian: { date: '20-10-2026', weekday: { en: 'Tuesday' } },
      hijri: { day: '09', month: { number: 5 }, year: '1448' },
    });
    expect(d).toEqual({
      gregorian: '2026-10-20',
      weekday: 2,
      hijriDay: 9,
      hijriMonth: 5,
      hijriYear: 1448,
      hijriMonthNameAr: 'جمادى الأولى',
    });
  });
});
