/**
 * Server-side purchase conversions — pure payload builders and the HTTP sender (fetch mocked).
 * The privacy rule under test: a payload holds only event, time, order id, total + currency and a
 * salted hash of the user id.
 */
import { createHash } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { loadEnv } from '../src/config/env.js';
import {
  configuredPlatforms,
  externalIdFor,
  ga4Payload,
  metaPayload,
  orderEventId,
  type Purchase,
  purchaseFacts,
  tiktokPayload,
} from '../src/domain/conversions.js';
import { ConversionSendError, sendConversion } from '../src/integrations/conversions.js';

const USER_ID = '7d5f0b8e-9c1a-4c39-8f3e-2b1d6a4e9f10';
const SALT = 'test-salt-not-secret';
const NOW = new Date('2026-10-20T08:00:00Z');
const P: Purchase = { eventId: '5550001', eventTime: 1_792_483_200, value: 450, currency: 'EGP', externalId: externalIdFor(SALT, 'meta', USER_ID) };

/** Every key anywhere in a JSON value. */
function keysOf(v: unknown, out = new Set<string>()): Set<string> {
  if (Array.isArray(v)) v.forEach((x) => keysOf(x, out));
  else if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) (out.add(k), keysOf(x, out));
  return out;
}
const FORBIDDEN = ['email', 'em', 'phone', 'ph', 'fn', 'ln', 'first_name', 'last_name', 'ip', 'client_ip_address', 'client_user_agent', 'user_agent', 'address', 'ct', 'zp', 'country', 'user_id', 'fbp', 'fbc', 'ttclid', 'contents', 'line_items', 'items'];

/** The only keys any payload may have (an allowlist, so a new field fails here first). */
const ALLOWED = new Set([
  'data', 'event_name', 'event_time', 'event_id', 'action_source', 'event_source_url', 'user_data', 'external_id', 'custom_data',
  'value', 'currency', 'test_event_code', 'client_id', 'timestamp_micros', 'consent', 'ad_user_data', 'ad_personalization', 'events',
  'name', 'params', 'transaction_id', 'event_source', 'event_source_id', 'event', 'user', 'properties', 'page', 'url',
]);

function expectMinimal(payload: unknown) {
  const keys = keysOf(payload);
  expect([...keys].filter((k) => !ALLOWED.has(k))).toEqual([]);
  for (const k of FORBIDDEN) expect(keys.has(k), `payload must not carry "${k}"`).toBe(false);
  const text = JSON.stringify(payload);
  expect(text).not.toContain(USER_ID);
  expect(text).not.toMatch(/prayer|azkar|zikr|dua|quran|hifz|salah/i);
}

describe('pseudonymous id', () => {
  it('is SHA-256(salt:platform:user) — stable, never the raw id, different per platform', () => {
    const a = externalIdFor(SALT, 'meta', USER_ID);
    expect(a).toBe(createHash('sha256').update(`${SALT}:meta:${USER_ID}`).digest('hex'));
    expect(a).toMatch(/^[0-9a-f]{64}$/);
    expect(externalIdFor(SALT, 'meta', USER_ID)).toBe(a);
    expect(a).not.toContain(USER_ID);
    expect(externalIdFor(SALT, 'ga4', USER_ID)).not.toBe(a);
    expect(externalIdFor('other-salt', 'meta', USER_ID)).not.toBe(a);
  });

  it('refuses to hash without a salt', () => {
    expect(() => externalIdFor('', 'meta', USER_ID)).toThrow(/CONVERSIONS_ID_SALT/);
  });
});

describe('order facts', () => {
  it('takes the order id, paid total and currency only', () => {
    const order = {
      id: 5550001,
      total_price: '450.00',
      currency: 'EGP',
      processed_at: '2026-10-20T07:30:00Z',
      email: 'buyer@example.com',
      customer: { first_name: 'A', phone: '+20100' },
      browser_ip: '1.2.3.4',
    };
    const f = purchaseFacts(order, 'gid://shopify/Order/5550001', NOW)!;
    expect(f).toEqual({ eventId: '5550001', eventTime: Date.parse('2026-10-20T07:30:00Z') / 1000, value: 450, currency: 'EGP' });
  });

  it('falls back sensibly and rejects what it cannot use', () => {
    expect(orderEventId('gid://shopify/Order/820982911946154508')).toBe('820982911946154508');
    expect(orderEventId('')).toBeNull();
    // Stale or future processed_at → now; missing currency → EGP.
    const f = purchaseFacts({ total_price: '99.999', processed_at: '2026-01-01T00:00:00Z' }, 'gid://shopify/Order/1', NOW)!;
    expect(f).toMatchObject({ eventTime: NOW.getTime() / 1000, value: 100, currency: 'EGP' });
    expect(purchaseFacts({ total_price: 'abc' }, 'gid://shopify/Order/1', NOW)).toBeNull();
    expect(purchaseFacts({ total_price: '-5' }, 'gid://shopify/Order/1', NOW)).toBeNull();
    expect(purchaseFacts({ total_price: '5' }, 'no-id', NOW)).toBeNull();
  });
});

describe('payload builders', () => {
  it('Meta: Purchase, website, event_id = order id, hashed external_id, value + currency', () => {
    const body = metaPayload(P, { eventSourceUrl: 'https://www.yaqin-brand.com' });
    expect(body).toEqual({
      data: [
        {
          event_name: 'Purchase',
          event_time: P.eventTime,
          event_id: '5550001',
          action_source: 'website',
          event_source_url: 'https://www.yaqin-brand.com',
          user_data: { external_id: [P.externalId] },
          custom_data: { value: 450, currency: 'EGP' },
        },
      ],
    });
    expectMinimal(body);
    expect(metaPayload(P, { eventSourceUrl: 'x', testEventCode: 'TEST1' }).test_event_code).toBe('TEST1');
  });

  it('GA4: purchase with transaction_id = order id, pseudonymous client_id, no user_id', () => {
    const body = ga4Payload(P);
    expect(body).toEqual({
      client_id: P.externalId,
      timestamp_micros: P.eventTime * 1_000_000,
      consent: { ad_user_data: 'GRANTED', ad_personalization: 'DENIED' },
      events: [{ name: 'purchase', params: { transaction_id: '5550001', value: 450, currency: 'EGP' } }],
    });
    expectMinimal(body);
  });

  it('TikTok: CompletePayment, event_id = order id, hashed external_id', () => {
    const body = tiktokPayload(P, { pixelId: 'PIX', pageUrl: 'https://www.yaqin-brand.com' });
    expect(body).toEqual({
      event_source: 'web',
      event_source_id: 'PIX',
      data: [
        {
          event: 'CompletePayment',
          event_time: P.eventTime,
          event_id: '5550001',
          user: { external_id: P.externalId },
          properties: { value: 450, currency: 'EGP' },
          page: { url: 'https://www.yaqin-brand.com' },
        },
      ],
    });
    expectMinimal(body);
  });
});

describe('configuration', () => {
  it('each platform needs both of its credentials', () => {
    expect(configuredPlatforms(loadEnv({ NODE_ENV: 'test' }))).toEqual({ meta: false, ga4: false, tiktok: false });
    expect(configuredPlatforms(loadEnv({ NODE_ENV: 'test', META_PIXEL_ID: '1', GA4_MEASUREMENT_ID: 'G-1', GA4_API_SECRET: 's', TIKTOK_ACCESS_TOKEN: 't' }))).toEqual({
      meta: false,
      ga4: true,
      tiktok: false,
    });
  });
});

describe('sender', () => {
  const env = loadEnv({
    NODE_ENV: 'test',
    META_PIXEL_ID: 'PIXEL1',
    META_CAPI_TOKEN: 'meta-secret-token',
    GA4_MEASUREMENT_ID: 'G-TEST',
    GA4_API_SECRET: 'ga4-secret',
    TIKTOK_PIXEL_ID: 'TTPIX',
    TIKTOK_ACCESS_TOKEN: 'tt-secret-token',
  });
  const ok = (body: unknown = {}) => new Response(JSON.stringify(body), { status: 200 });

  it('posts to each platform with credentials outside the payload', async () => {
    const f = vi.fn(async () => ok({ code: 0 }));
    await sendConversion(env, 'meta', P, f as unknown as typeof fetch);
    await sendConversion(env, 'ga4', P, f as unknown as typeof fetch);
    await sendConversion(env, 'tiktok', P, f as unknown as typeof fetch);
    const calls = f.mock.calls as unknown as [string, RequestInit][];
    expect(calls.map((c) => c[0])).toEqual([
      'https://graph.facebook.com/v21.0/PIXEL1/events',
      'https://www.google-analytics.com/mp/collect?measurement_id=G-TEST&api_secret=ga4-secret',
      'https://business-api.tiktok.com/open_api/v1.3/event/track/',
    ]);
    expect((calls[0]![1].headers as Record<string, string>).Authorization).toBe('Bearer meta-secret-token');
    expect((calls[2]![1].headers as Record<string, string>)['Access-Token']).toBe('tt-secret-token');
    for (const [, init] of calls) {
      expect(init.body).not.toMatch(/secret/);
      expectMinimal(JSON.parse(init.body as string));
    }
  });

  it('retries once on 5xx / network errors, then gives up', async () => {
    const flaky = vi.fn().mockResolvedValueOnce(new Response('', { status: 503 })).mockResolvedValueOnce(ok());
    await sendConversion(env, 'meta', P, flaky as unknown as typeof fetch);
    expect(flaky).toHaveBeenCalledTimes(2);

    const down = vi.fn().mockRejectedValue(new TypeError('fetch failed'));
    await expect(sendConversion(env, 'ga4', P, down as unknown as typeof fetch)).rejects.toThrow(ConversionSendError);
    expect(down).toHaveBeenCalledTimes(2);
  });

  it('does not retry a rejected payload, and errors never carry the URL or token', async () => {
    const bad = vi.fn(async () => new Response('{"error":{}}', { status: 400 }));
    const err = await sendConversion(env, 'ga4', P, bad as unknown as typeof fetch).catch((e: unknown) => e);
    expect(bad).toHaveBeenCalledTimes(1);
    expect(err).toBeInstanceOf(ConversionSendError);
    expect(String((err as Error).message)).toBe('conversions: ga4 HTTP 400');

    const tt = vi.fn(async () => ok({ code: 40001, message: 'invalid' }));
    await expect(sendConversion(env, 'tiktok', P, tt as unknown as typeof fetch)).rejects.toThrow('conversions: tiktok code 40001');
    expect(tt).toHaveBeenCalledTimes(1);
  });
});
