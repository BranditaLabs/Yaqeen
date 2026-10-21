/**
 * Hijri calendar helpers — pure functions.
 *
 * Source of truth is AlAdhan with calendarMethod=UAQ (Umm al-Qura). Egypt's Dar al-Ifta
 * can differ from UAQ by ±1 day after moon sighting, so admins can set a regional offset
 * that applies from a given Hijri month onwards.
 *
 * Convention: offset +1 means the regional month starts ONE DAY LATER than UAQ,
 * i.e. regional(D) = UAQ(D − 1).
 */
import type { HijriDay } from '@yaqeen/contracts';
import { addDays } from './points.js';

export const HIJRI_MONTHS_AR = [
  'محرم',
  'صفر',
  'ربيع الأول',
  'ربيع الآخر',
  'جمادى الأولى',
  'جمادى الآخرة',
  'رجب',
  'شعبان',
  'رمضان',
  'شوال',
  'ذو القعدة',
  'ذو الحجة',
] as const;

export interface HijriAdjustment {
  offsetDays: number;
  effectiveHijriYear: number;
  effectiveHijriMonth: number;
  createdAt: Date;
}

const ym = (y: number, m: number) => y * 100 + m;

/** The offset in force for a UAQ Hijri month: latest adjustment whose effective month ≤ it. */
export function resolveOffset(adjustments: HijriAdjustment[], hijriYear: number, hijriMonth: number): number {
  const target = ym(hijriYear, hijriMonth);
  const applicable = adjustments
    .filter((a) => ym(a.effectiveHijriYear, a.effectiveHijriMonth) <= target)
    .sort(
      (a, b) =>
        ym(b.effectiveHijriYear, b.effectiveHijriMonth) - ym(a.effectiveHijriYear, a.effectiveHijriMonth) ||
        b.createdAt.getTime() - a.createdAt.getTime(),
    );
  return applicable[0]?.offsetDays ?? 0;
}

/**
 * Apply regional adjustments to a run of consecutive UAQ days.
 * `uaq` must be padded by at least 2 days on each side of the range you want back;
 * days whose shifted source falls outside the input are dropped.
 */
export function applyAdjustments(uaq: HijriDay[], adjustments: HijriAdjustment[], extraOffset = 0): HijriDay[] {
  const byDate = new Map(uaq.map((d) => [d.gregorian, d]));
  const out: HijriDay[] = [];
  for (const day of uaq) {
    const offset = resolveOffset(adjustments, day.hijriYear, day.hijriMonth) + extraOffset;
    const source = byDate.get(addDays(day.gregorian, -offset));
    if (!source) continue;
    out.push({
      gregorian: day.gregorian,
      weekday: day.weekday,
      hijriDay: source.hijriDay,
      hijriMonth: source.hijriMonth,
      hijriYear: source.hijriYear,
      hijriMonthNameAr: source.hijriMonthNameAr,
    });
  }
  return out;
}

/**
 * Sanity check after adjusting: a Hijri month is 29 or 30 days, and days must be
 * strictly sequential. Returned as warnings so the admin preview can block the save.
 */
export function validateSequence(days: HijriDay[]): string[] {
  const warnings: string[] = [];
  for (let i = 1; i < days.length; i++) {
    const prev = days[i - 1]!;
    const cur = days[i]!;
    const sameMonth = prev.hijriMonth === cur.hijriMonth && prev.hijriYear === cur.hijriYear;
    if (sameMonth && cur.hijriDay !== prev.hijriDay + 1) {
      warnings.push(`${cur.gregorian}: ${cur.hijriDay} ${cur.hijriMonthNameAr} repeats or skips (previous ${prev.hijriDay})`);
    }
    if (!sameMonth) {
      if (cur.hijriDay !== 1) warnings.push(`${cur.gregorian}: month starts on day ${cur.hijriDay}`);
      if (prev.hijriDay < 29 || prev.hijriDay > 30) {
        warnings.push(`${prev.hijriMonthNameAr} ${prev.hijriYear} would have ${prev.hijriDay} days`);
      }
    }
    if (cur.hijriDay > 30) warnings.push(`${cur.gregorian}: day ${cur.hijriDay} exceeds 30`);
  }
  return warnings;
}

/** Map an AlAdhan `data[]` entry to our HijriDay. */
export interface AlAdhanDay {
  gregorian: { date: string; weekday: { en: string } };
  hijri: { day: string; month: { number: number }; year: string };
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

export function fromAlAdhan(d: AlAdhanDay): HijriDay {
  // AlAdhan gregorian.date is DD-MM-YYYY
  const [dd, mm, yyyy] = d.gregorian.date.split('-');
  const month = d.hijri.month.number;
  return {
    gregorian: `${yyyy}-${mm}-${dd}`,
    weekday: Math.max(0, WEEKDAYS.indexOf(d.gregorian.weekday.en)),
    hijriDay: Number(d.hijri.day),
    hijriMonth: month,
    hijriYear: Number(d.hijri.year),
    hijriMonthNameAr: HIJRI_MONTHS_AR[month - 1] ?? '',
  };
}

/* ------------------------------------------------------------ special days */

export type SpecialDay = 'white_day' | 'friday' | 'mon_thu' | 'ramadan' | 'eid_fitr' | 'eid_adha' | 'arafah' | 'ashura';

/**
 * Days the calendar marks with a pip (and that may carry a bonus task).
 * `weekday` is 0 = Sunday … 5 = Friday. Eid days are not marked as fasting days.
 */
export function specialDays(d: Pick<HijriDay, 'hijriDay' | 'hijriMonth' | 'weekday'>): SpecialDay[] {
  const out: SpecialDay[] = [];
  const eidFitr = d.hijriMonth === 10 && d.hijriDay <= 3;
  const eidAdha = d.hijriMonth === 12 && d.hijriDay >= 10 && d.hijriDay <= 13;
  if (d.hijriMonth === 9) out.push('ramadan');
  if (eidFitr) out.push('eid_fitr');
  if (eidAdha) out.push('eid_adha');
  if (d.hijriMonth === 12 && d.hijriDay === 9) out.push('arafah');
  if (d.hijriMonth === 1 && d.hijriDay === 10) out.push('ashura');
  // 13 Dhu al-Hijjah is a day of Tashreeq, not a white fasting day.
  if (d.hijriDay >= 13 && d.hijriDay <= 15 && !eidAdha) out.push('white_day');
  if (d.weekday === 5) out.push('friday');
  if ((d.weekday === 1 || d.weekday === 4) && !eidFitr && !eidAdha) out.push('mon_thu');
  return out;
}
