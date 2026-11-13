import 'server-only';
import type { HijriDay, HijriMonthResponse } from '@yaqeen/contracts';
import { api } from './api';

const cairoDay = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo' });

/** The Cairo calendar day (YYYY-MM-DD) of an instant. */
export const cairoDate = (d: Date | string) => cairoDay.format(new Date(d));

/** Gregorian YYYY-MM-DD + n days (calendar arithmetic, no time zone). */
export function addDays(day: string, n: number): string {
  const t = Date.parse(`${day}T00:00:00Z`) + n * 86_400_000;
  return new Date(t).toISOString().slice(0, 10);
}

/**
 * Hijri days for the Gregorian months that hold `days`, from the API calendar (Umm al-Qura with the
 * Egypt offset the religious reviewer set). Missing months simply have no Hijri caption.
 */
export async function hijriDays(days: string[]): Promise<Map<string, HijriDay>> {
  const months = [...new Set(days.map((d) => d.slice(0, 7)))];
  const out = new Map<string, HijriDay>();
  const res = await Promise.all(
    months.map((m) => api<HijriMonthResponse>(`/v1/calendar/hijri?year=${m.slice(0, 4)}&month=${Number(m.slice(5, 7))}`).catch(() => null)),
  );
  for (const r of res) for (const d of r?.days ?? []) out.set(d.gregorian, d);
  return out;
}

export interface TournamentPreset {
  key: 'ramadan' | 'dhul_hijja_10';
  label: string;
  startsOn: string;
  lastDay: string;
}

/**
 * «رمضان {year}» and «العشر من ذي الحجة {year}»: the next occurrence of each, read from
 * the Hijri calendar with the Egypt offset, scanning up to 14 Gregorian months ahead.
 */
export async function tournamentPresets(today: string): Promise<TournamentPreset[]> {
  const days = Array.from({ length: 14 }, (_, i) => {
    const d = new Date(Date.UTC(Number(today.slice(0, 4)), Number(today.slice(5, 7)) - 1 + i, 1));
    return d.toISOString().slice(0, 10);
  });
  const all = [...(await hijriDays(days)).values()].filter((d) => d.gregorian >= today).sort((a, b) => a.gregorian.localeCompare(b.gregorian));
  const presets: TournamentPreset[] = [];
  // Windows that start today or later (a month already under way is not offered).
  const firstRun = (match: (d: HijriDay) => boolean) => {
    const start = all.findIndex((d) => d.hijriDay === 1 && match(d));
    if (start < 0) return null;
    let end = start;
    while (end + 1 < all.length && match(all[end + 1]!) && all[end + 1]!.hijriYear === all[start]!.hijriYear) end++;
    return { first: all[start]!, last: all[end]! };
  };
  const ramadan = firstRun((d) => d.hijriMonth === 9);
  // A month that is still running when the scan ends would be cut short: keep only whole windows.
  if (ramadan && ramadan.last.hijriDay >= 29) presets.push({ key: 'ramadan', label: `رمضان ${ramadan.first.hijriYear}`, startsOn: ramadan.first.gregorian, lastDay: ramadan.last.gregorian });
  const ten = firstRun((d) => d.hijriMonth === 12 && d.hijriDay <= 10);
  if (ten && ten.last.hijriDay === 10) presets.push({ key: 'dhul_hijja_10', label: `العشر من ذي الحجة ${ten.first.hijriYear}`, startsOn: ten.first.gregorian, lastDay: ten.last.gregorian });
  return presets;
}
