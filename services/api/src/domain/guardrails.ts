/**
 * Push-campaign guardrails — pure functions.
 *
 * A marketing push must never interrupt worship or rest:
 *  - quiet hours 22:00–07:00 (user's local time),
 *  - no sends from 20 min before to 30 min after any prayer time,
 *  - no sends during Friday Jumu'ah window 11:30–13:30,
 *  - at most one `offers`/`rewards` push per user per local day, two `challenge` pushes,
 *  - the matching consent bucket must be granted.
 * Worship reminders (adhan, azkar) are local notifications on the device and are NOT
 * governed here.
 */
import type { CampaignKind, ConsentKind } from '@yaqeen/contracts';

export const QUIET_START_MIN = 22 * 60;
export const QUIET_END_MIN = 7 * 60;
export const PRAYER_BEFORE_MIN = 20;
export const PRAYER_AFTER_MIN = 30;
export const JUMUAH_START_MIN = 11 * 60 + 30;
export const JUMUAH_END_MIN = 13 * 60 + 30;
export const DAILY_CAP: Record<CampaignKind, number> = { offers: 1, rewards: 1, challenge: 2 };

export const CONSENT_FOR_KIND: Record<CampaignKind, ConsentKind> = {
  offers: 'store_offers',
  rewards: 'challenge_rewards',
  challenge: 'challenge_rewards',
};

export type BlockReason = 'no_consent' | 'quiet_hours' | 'near_prayer' | 'jumuah' | 'daily_cap';

export interface LocalClock {
  /** minutes since local midnight */
  minutes: number;
  /** 0 = Sunday … 5 = Friday */
  weekday: number;
}

export function localClock(now: Date, timeZone: string): LocalClock {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    weekday: 'short',
    hourCycle: 'h23',
  }).formatToParts(now);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  const weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(get('weekday'));
  return { minutes: Number(get('hour')) * 60 + Number(get('minute')), weekday };
}

export function checkSend(args: {
  kind: CampaignKind;
  clock: LocalClock;
  /** Today's prayer times as minutes since local midnight. */
  prayerMinutes: number[];
  consents: Partial<Record<ConsentKind, boolean>>;
  sentTodayOfKind: number;
}): { ok: true } | { ok: false; reason: BlockReason } {
  const { kind, clock, prayerMinutes, consents, sentTodayOfKind } = args;
  if (!consents[CONSENT_FOR_KIND[kind]]) return { ok: false, reason: 'no_consent' };

  const m = clock.minutes;
  if (m >= QUIET_START_MIN || m < QUIET_END_MIN) return { ok: false, reason: 'quiet_hours' };
  if (clock.weekday === 5 && m >= JUMUAH_START_MIN && m < JUMUAH_END_MIN) return { ok: false, reason: 'jumuah' };
  if (prayerMinutes.some((p) => m >= p - PRAYER_BEFORE_MIN && m < p + PRAYER_AFTER_MIN)) {
    return { ok: false, reason: 'near_prayer' };
  }
  if (sentTodayOfKind >= DAILY_CAP[kind]) return { ok: false, reason: 'daily_cap' };
  return { ok: true };
}

/**
 * For "smart" schedule: the first allowed minute at/after `fromMinutes` today, or null.
 * Ignores consent/cap (those are per user) — this is about the clock only.
 */
export function nextAllowedMinute(fromMinutes: number, weekday: number, prayerMinutes: number[]): number | null {
  for (let m = Math.max(fromMinutes, QUIET_END_MIN); m < QUIET_START_MIN; m++) {
    const res = checkSend({
      kind: 'challenge',
      clock: { minutes: m, weekday },
      prayerMinutes,
      consents: { challenge_rewards: true },
      sentTodayOfKind: 0,
    });
    if (res.ok) return m;
  }
  return null;
}

/** Validate campaign copy before it can be scheduled (admin-side). */
export function lintCampaignCopy(c: { titleAr: string; bodyAr: string }): string[] {
  const issues: string[] = [];
  if (c.titleAr.length > 40) issues.push('العنوان أطول من 40 حرفاً وقد يُقص على شاشة القفل');
  if (c.bodyAr.length > 110) issues.push('النص أطول من 110 حرفاً وقد يُقص على شاشة القفل');
  if (/[!]{2,}/.test(c.titleAr + c.bodyAr)) issues.push('تجنّب علامات التعجب المتكررة');
  if (/(آخر فرصة|الحق|بسرعة)/.test(c.titleAr + c.bodyAr)) issues.push('تجنّب لغة الاستعجال في سياق العبادة');
  return issues;
}
