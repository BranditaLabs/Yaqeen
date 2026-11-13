import assert from 'node:assert/strict';
import { afterEach, describe, test } from 'node:test';
import type { HijriDay } from '@yaqeen/contracts';
import { addDays, tournamentPresets } from './hijri.ts';

/**
 * A synthetic Umm al-Qura-like calendar: 1 Muharram 1448 = 2026-06-16, odd months 30 days, even
 * months 29 (a 354-day year). Ramadan 1448 = 2027-02-07…2027-03-08, Dhul Hijjah 1448 starts
 * 2027-05-07, Ramadan 1449 = 2028-01-27…2028-02-25.
 */
function calendar(): HijriDay[] {
  const out: HijriDay[] = [];
  let t = Date.parse('2026-06-16T00:00:00Z');
  for (let year = 1448; year <= 1450; year++) {
    for (let month = 1; month <= 12; month++) {
      const len = month % 2 === 1 ? 30 : 29;
      for (let day = 1; day <= len; day++) {
        const d = new Date(t);
        out.push({ gregorian: d.toISOString().slice(0, 10), hijriDay: day, hijriMonth: month, hijriYear: year, hijriMonthNameAr: `شهر ${month}`, weekday: d.getUTCDay() });
        t += 86_400_000;
      }
    }
  }
  return out;
}

const DAYS = calendar();
const realFetch = globalThis.fetch;

/** Serves /v1/calendar/hijri?year&month from the synthetic calendar; months after `until` (YYYY-MM) fail. */
function serveCalendar(until = '9999-12') {
  globalThis.fetch = (async (input: string | URL | Request) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
    const ym = `${url.searchParams.get('year')}-${String(url.searchParams.get('month')).padStart(2, '0')}`;
    if (ym > until) return new Response('{}', { status: 503 });
    const days = DAYS.filter((d) => d.gregorian.startsWith(ym));
    return new Response(JSON.stringify({ method: 'UAQ', offsetDays: 0, days }), { status: 200, headers: { 'content-type': 'application/json' } });
  }) as typeof fetch;
}

afterEach(() => {
  globalThis.fetch = realFetch;
});

describe('addDays', () => {
  test('crosses months, years and leap days', () => {
    assert.equal(addDays('2026-12-31', 1), '2027-01-01');
    assert.equal(addDays('2028-02-28', 1), '2028-02-29');
    assert.equal(addDays('2028-03-01', -1), '2028-02-29');
    assert.equal(addDays('2026-11-13', 0), '2026-11-13');
  });
});

describe('tournamentPresets', () => {
  test('offers the next Ramadan and the first ten of Dhul Hijjah, whole and labelled with the Hijri year', async () => {
    serveCalendar();
    assert.deepEqual(await tournamentPresets('2026-11-13'), [
      { key: 'ramadan', label: 'رمضان 1448', startsOn: '2027-02-07', lastDay: '2027-03-08' },
      { key: 'dhul_hijja_10', label: 'العشر من ذي الحجة 1448', startsOn: '2027-05-07', lastDay: '2027-05-16' },
    ]);
  });

  test('a Dhul Hijjah that starts today is offered from today', async () => {
    serveCalendar();
    const presets = await tournamentPresets('2027-05-07');
    assert.deepEqual(
      presets.find((p) => p.key === 'dhul_hijja_10'),
      { key: 'dhul_hijja_10', label: 'العشر من ذي الحجة 1448', startsOn: '2027-05-07', lastDay: '2027-05-16' },
    );
    // Ramadan 1448 is over: next year's is offered instead.
    assert.deepEqual(presets.find((p) => p.key === 'ramadan'), { key: 'ramadan', label: 'رمضان 1449', startsOn: '2028-01-27', lastDay: '2028-02-25' });
  });

  test('a Ramadan already under way is not offered; the next one is', async () => {
    serveCalendar();
    const presets = await tournamentPresets('2027-02-08');
    assert.deepEqual(presets.find((p) => p.key === 'ramadan'), { key: 'ramadan', label: 'رمضان 1449', startsOn: '2028-01-27', lastDay: '2028-02-25' });
  });

  test('a Ramadan cut off at the end of the scan is not offered', async () => {
    // The calendar answers only until January 2028: Ramadan 1449 starts on 2028-01-27 and the scan
    // would see five of its days.
    serveCalendar('2028-01');
    const presets = await tournamentPresets('2027-02-08');
    assert.equal(presets.find((p) => p.key === 'ramadan'), undefined);
    // Dhul Hijjah 1448 is whole inside the scan.
    assert.deepEqual(presets.find((p) => p.key === 'dhul_hijja_10')?.startsOn, '2027-05-07');
  });

  test('ten days of Dhul Hijjah cut off by the scan are not offered', async () => {
    // Dhul Hijjah 1448 is under way on 2027-05-08; Dhul Hijjah 1449 starts on 2028-04-25 and the
    // calendar answers only until April 2028, so the scan sees six of its ten days.
    serveCalendar('2028-04');
    assert.deepEqual(
      (await tournamentPresets('2027-05-08')).map((p) => p.key),
      ['ramadan'],
    );
  });

  test('no calendar (API down): no presets, no throw', async () => {
    serveCalendar('0000-00');
    assert.deepEqual(await tournamentPresets('2026-11-13'), []);
  });
});
