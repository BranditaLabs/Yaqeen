/**
 * Marketing events that MAY be sent to ad platforms (Google Ads via Firebase,
 * Meta, TikTok) — and only when the user granted `ads_measurement`.
 *
 * Worship activity (reading, prayer, azkar, hifz, recitation) is never an ad
 * event. Keep this list closed: adding an event requires a privacy review.
 */
export const AD_EVENTS = [
  'first_open',
  'sign_up',
  'onboarding_complete',
  'challenge_join',
  'streak_7',
  'streak_30',
  'reward_redeem',
  'store_click',
  'purchase',
] as const;

export type AdEvent = (typeof AD_EVENTS)[number];

export const isAdEvent = (name: string): name is AdEvent => (AD_EVENTS as readonly string[]).includes(name);
