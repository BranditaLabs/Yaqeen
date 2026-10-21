/**
 * Privacy rules for dashboard aggregates — pure functions.
 * A count describing fewer than K people could single someone out, so it is suppressed (null).
 */
import { K_ANONYMITY } from '@yaqeen/contracts';

export function suppress(n: number, k = K_ANONYMITY): number | null {
  return n > 0 && n < k ? null : n;
}

/** Percentage (one decimal) of `part` in `whole`, or null when `whole` is too small to publish. */
export function pct(part: number, whole: number, k = K_ANONYMITY): number | null {
  if (whole < k) return null;
  return Math.round((1000 * part) / whole) / 10;
}

export const RANGE_DAYS = { '7d': 7, '30d': 30, '90d': 90 } as const;

/** Every date in [from, to] with a value (missing dates → 0), suppressing small counts. */
export function fillSeries(from: string, to: string, rows: { date: string; n: number }[], addDays: (d: string, n: number) => string) {
  const byDate = new Map(rows.map((r) => [r.date, r.n]));
  const out: { date: string; value: number | null }[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) out.push({ date: d, value: suppress(byDate.get(d) ?? 0) });
  return out;
}

/** Funnel step days shown on the dashboard: joined → 7 → 30 → 100. */
export const FUNNEL_DAYS = [1, 7, 30, 100] as const;
