/**
 * Server-side `purchase` conversion payloads — pure functions.
 *
 * Data minimisation (CLAUDE.md rule 1, docs/SECURITY_PRIVACY.md): a payload carries ONLY the event
 * name, its time, the order id (dedupe), the order total + currency and a salted SHA-256 of the user
 * id. Never an email, phone, name, IP, user agent, address, item list, or anything about worship.
 * The builders take a `Purchase` and nothing else, so nothing more can leak in.
 */
import { createHash } from 'node:crypto';
import type { Env } from '../config/env.js';

export const CONVERSION_PLATFORMS = ['meta', 'ga4', 'tiktok'] as const;
export type ConversionPlatform = (typeof CONVERSION_PLATFORMS)[number];

/** Everything a conversion is built from. */
export interface Purchase {
  /** Shopify order id (numeric part) — the event id every platform dedupes on. */
  eventId: string;
  /** Unix seconds. */
  eventTime: number;
  /** Order total the customer paid (after the discount), 2 dp. */
  value: number;
  /** ISO 4217 from the order (EGP for the Yaqeen store). */
  currency: string;
  /** Salted SHA-256 hex of the user id, per platform (see `externalIdFor`). */
  externalId: string;
}

/** Platforms whose credentials are set (each one optional). */
export function configuredPlatforms(env: Env): Record<ConversionPlatform, boolean> {
  return {
    meta: Boolean(env.META_PIXEL_ID && env.META_CAPI_TOKEN),
    ga4: Boolean(env.GA4_MEASUREMENT_ID && env.GA4_API_SECRET),
    tiktok: Boolean(env.TIKTOK_PIXEL_ID && env.TIKTOK_ACCESS_TOKEN),
  };
}

/**
 * Pseudonymous id: SHA-256(salt:platform:userId). The secret salt stops anyone re-deriving it from
 * a user id; the platform in the input gives each ad platform a different id, so they can't join
 * their data on ours. Stable per user, so repeat purchases count as one person.
 */
export function externalIdFor(salt: string, platform: ConversionPlatform, userId: string): string {
  if (!salt) throw new Error('CONVERSIONS_ID_SALT is not set');
  return createHash('sha256').update(`${salt}:${platform}:${userId}`).digest('hex');
}

/** `gid://shopify/Order/123` or 123 → "123" (text: big ids lose precision as JSON numbers). */
export function orderEventId(orderRef: string): string | null {
  const m = /(\d+)$/.exec(orderRef.trim());
  return m ? m[1]! : null;
}

const MAX_AGE_S = 72 * 3600; // GA4 rejects older timestamps; Meta allows 7 days.

/**
 * The order facts we may send: event id, time, total and currency. Returns null when the order
 * can't give a valid one (then nothing is sent).
 */
export function purchaseFacts(order: unknown, orderRef: string, now: Date): Omit<Purchase, 'externalId'> | null {
  const o = (order ?? {}) as { total_price?: unknown; current_total_price?: unknown; currency?: unknown; processed_at?: unknown };
  const eventId = orderEventId(orderRef);
  if (!eventId) return null;
  const value = Number(o.total_price ?? o.current_total_price);
  if (!Number.isFinite(value) || value < 0) return null;
  const currency = typeof o.currency === 'string' && /^[A-Z]{3}$/.test(o.currency) ? o.currency : 'EGP';
  const nowS = Math.floor(now.getTime() / 1000);
  const processed = typeof o.processed_at === 'string' ? Math.floor(Date.parse(o.processed_at) / 1000) : NaN;
  const eventTime = Number.isFinite(processed) && processed <= nowS && processed > nowS - MAX_AGE_S ? processed : nowS;
  return { eventId, eventTime, value: Math.round(value * 100) / 100, currency };
}

/** Meta Conversions API: POST graph.facebook.com/{version}/{pixel}/events. */
export function metaPayload(p: Purchase, opts: { eventSourceUrl: string; testEventCode?: string }) {
  return {
    data: [
      {
        event_name: 'Purchase',
        event_time: p.eventTime,
        event_id: p.eventId,
        // The purchase happens on the Shopify web store.
        action_source: 'website',
        event_source_url: opts.eventSourceUrl,
        user_data: { external_id: [p.externalId] },
        custom_data: { value: p.value, currency: p.currency },
      },
    ],
    ...(opts.testEventCode ? { test_event_code: opts.testEventCode } : {}),
  };
}

/** GA4 Measurement Protocol: POST /mp/collect?measurement_id=…&api_secret=…. */
export function ga4Payload(p: Purchase) {
  return {
    // Pseudonymous: our salted hash, never the user id; no user_id, no user properties.
    client_id: p.externalId,
    timestamp_micros: p.eventTime * 1_000_000,
    // Measurement only — the consent covers measuring, not ad personalisation / remarketing.
    consent: { ad_user_data: 'GRANTED', ad_personalization: 'DENIED' },
    events: [{ name: 'purchase', params: { transaction_id: p.eventId, value: p.value, currency: p.currency } }],
  };
}

/** TikTok Events API 2.0: POST business-api.tiktok.com/open_api/v1.3/event/track/. */
export function tiktokPayload(p: Purchase, opts: { pixelId: string; pageUrl: string; testEventCode?: string }) {
  return {
    event_source: 'web',
    event_source_id: opts.pixelId,
    ...(opts.testEventCode ? { test_event_code: opts.testEventCode } : {}),
    data: [
      {
        event: 'CompletePayment',
        event_time: p.eventTime,
        event_id: p.eventId,
        user: { external_id: p.externalId },
        properties: { value: p.value, currency: p.currency },
        page: { url: opts.pageUrl },
      },
    ],
  };
}
