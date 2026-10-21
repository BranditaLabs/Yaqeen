/**
 * AlAdhan Hijri calendar client (Umm al-Qura method), cached in Redis.
 * Month calendars are immutable for a given method, so they are cached for 30 days.
 */
import type { Redis } from 'ioredis';
import type { HijriDay } from '@yaqeen/contracts';
import { type AlAdhanDay, fromAlAdhan } from '../domain/hijri.js';
import { AppError } from '../lib/errors.js';

const TTL_SEC = 30 * 24 * 3600;

export class AlAdhanClient {
  constructor(
    private readonly baseUrl: string,
    private readonly redis: Redis | null,
  ) {}

  /** Gregorian month → UAQ Hijri days. */
  async gregorianMonth(year: number, month: number): Promise<HijriDay[]> {
    const cacheKey = `aladhan:gToH:UAQ:${year}-${month}`;
    const cached = await this.redis?.get(cacheKey);
    if (cached) return JSON.parse(cached) as HijriDay[];

    const url = `${this.baseUrl}/gToHCalendar/${month}/${year}?calendarMethod=UAQ`;
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new AppError(502, 'hijri_upstream', `AlAdhan ${res.status}`);
    const body = (await res.json()) as { code: number; data: AlAdhanDay[] };
    const days = body.data.map(fromAlAdhan);
    await this.redis?.set(cacheKey, JSON.stringify(days), 'EX', TTL_SEC);
    return days;
  }

  /** Consecutive days covering [from, to] inclusive (fetches every month touched). */
  async range(fromIso: string, toIso: string): Promise<HijriDay[]> {
    const months: [number, number][] = [];
    const d = new Date(`${fromIso.slice(0, 7)}-01T00:00:00Z`);
    const end = new Date(`${toIso.slice(0, 7)}-01T00:00:00Z`);
    while (d <= end) {
      months.push([d.getUTCFullYear(), d.getUTCMonth() + 1]);
      d.setUTCMonth(d.getUTCMonth() + 1);
    }
    const all = (await Promise.all(months.map(([y, m]) => this.gregorianMonth(y, m)))).flat();
    return all.filter((x) => x.gregorian >= fromIso && x.gregorian <= toIso);
  }
}
