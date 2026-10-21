import { describe, expect, it } from 'vitest';
import { checkSend, lintCampaignCopy, localClock, nextAllowedMinute } from '../src/domain/guardrails.js';

const hm = (h: number, m = 0) => h * 60 + m;
// Approximate Cairo prayer times for late October 2026.
const PRAYERS = [hm(4, 30), hm(11, 40), hm(14, 50), hm(17, 15), hm(18, 35)];
const ALL_CONSENT = { store_offers: true, challenge_rewards: true };

const base = { kind: 'offers' as const, prayerMinutes: PRAYERS, consents: ALL_CONSENT, sentTodayOfKind: 0 };

describe('checkSend', () => {
  it('allows a mid-morning weekday send', () => {
    expect(checkSend({ ...base, clock: { minutes: hm(10), weekday: 2 } })).toEqual({ ok: true });
  });
  it('requires the matching consent', () => {
    expect(
      checkSend({ ...base, consents: { challenge_rewards: true }, clock: { minutes: hm(10), weekday: 2 } }),
    ).toEqual({ ok: false, reason: 'no_consent' });
  });
  it('blocks quiet hours', () => {
    expect(checkSend({ ...base, clock: { minutes: hm(23), weekday: 2 } })).toMatchObject({ reason: 'quiet_hours' });
    expect(checkSend({ ...base, clock: { minutes: hm(6, 59), weekday: 2 } })).toMatchObject({ reason: 'quiet_hours' });
  });
  it('blocks 20 min before to 30 min after a prayer', () => {
    expect(checkSend({ ...base, clock: { minutes: hm(17, 0), weekday: 2 } })).toMatchObject({ reason: 'near_prayer' });
    expect(checkSend({ ...base, clock: { minutes: hm(17, 40), weekday: 2 } })).toMatchObject({ reason: 'near_prayer' });
    expect(checkSend({ ...base, clock: { minutes: hm(17, 45), weekday: 2 } })).toEqual({ ok: true });
  });
  it("blocks the Jumu'ah window on Friday only", () => {
    expect(checkSend({ ...base, prayerMinutes: [], clock: { minutes: hm(12), weekday: 5 } })).toMatchObject({
      reason: 'jumuah',
    });
    expect(checkSend({ ...base, prayerMinutes: [], clock: { minutes: hm(12), weekday: 4 } })).toEqual({ ok: true });
  });
  it('enforces the daily cap per kind', () => {
    expect(checkSend({ ...base, sentTodayOfKind: 1, clock: { minutes: hm(10), weekday: 2 } })).toMatchObject({
      reason: 'daily_cap',
    });
    expect(
      checkSend({ ...base, kind: 'challenge', sentTodayOfKind: 1, clock: { minutes: hm(10), weekday: 2 } }),
    ).toEqual({ ok: true });
  });
});

describe('nextAllowedMinute', () => {
  it('skips past a prayer window', () => {
    expect(nextAllowedMinute(hm(17, 0), 2, PRAYERS)).toBe(hm(17, 45));
  });
  it('returns null after quiet hours start', () => {
    expect(nextAllowedMinute(hm(22, 30), 2, PRAYERS)).toBeNull();
  });
});

describe('localClock', () => {
  it('reads Cairo local time and weekday', () => {
    const c = localClock(new Date('2026-10-23T09:00:00Z'), 'Africa/Cairo'); // Friday
    expect(c.weekday).toBe(5);
    expect(c.minutes === hm(11) || c.minutes === hm(12)).toBe(true); // UTC+2 or +3 depending on DST rules
  });
});

describe('lintCampaignCopy', () => {
  it('flags urgency language', () => {
    expect(lintCampaignCopy({ titleAr: 'آخر فرصة!!', bodyAr: 'خصم' }).length).toBe(2);
    expect(lintCampaignCopy({ titleAr: 'هديتك تنتظرك', bodyAr: 'لديك 1200 نقطة' })).toEqual([]);
  });
});
