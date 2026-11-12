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

/* ------------------------------------------------------- product analytics */

/**
 * Product analytics («تحسين التطبيق»): how people move through the app, so we can improve it.
 * Sent only with the `product_analytics` consent (off by default), to our own API, keyed by a
 * random per-install id that is never linked to the account. The server stores aggregates-ready
 * rows and may forward the same events to PostHog (EU).
 *
 * Closed list with closed property values. **No worship activity** — never which surah, prayer,
 * zikr, dua, task or hifz step; worship tabs aren't tracked either. Adding an event or a value
 * needs a privacy review (CLAUDE.md rules 1–2).
 */
export const PRODUCT_EVENTS = {
  app_open: {},
  onboarding_step: { step: ['welcome', 'language', 'prayer', 'consent', 'goal', 'routine', 'download'] },
  onboarding_complete: {},
  sign_in: { provider: ['google', 'apple', 'guest'] },
  tab_view: { tab: ['home', 'challenge', 'profile'] },
  card_published: {},
  card_shared: { channel: ['link', 'qr'] },
  medal_activated: { via: ['code', 'link'] },
  redeem_view: {},
  reward_redeem: {},
  store_click: { from: ['profile', 'redeem', 'card', 'medal'] },
  notification_open: { kind: ['reminder', 'campaign', 'challenge'] },
  settings_change: { setting: ['language', 'reminders', 'privacy', 'routine'] },
  update_prompt: { action: ['shown', 'update', 'later'] },
} as const satisfies Record<string, Record<string, readonly string[]>>;

export type ProductEventName = keyof typeof PRODUCT_EVENTS;
export const PRODUCT_EVENT_NAMES = Object.keys(PRODUCT_EVENTS) as ProductEventName[];

export const isProductEvent = (name: string): name is ProductEventName => Object.hasOwn(PRODUCT_EVENTS, name);

/** True when every prop is declared for the event and every value is one of its allowed values. */
export function validProductProps(name: ProductEventName, props: Record<string, string>): boolean {
  const spec = PRODUCT_EVENTS[name] as Record<string, readonly string[]>;
  return Object.entries(props).every(([k, v]) => Object.hasOwn(spec, k) && spec[k]!.includes(v));
}
