/**
 * Server-side purchase conversions against Postgres: consent gating (granted / withdrawn / missing /
 * guest), the `serverConversions` flag and credentials, idempotency on webhook replay, retry of a
 * failed send, and the admin status. fetch is mocked — no network.
 */
import { fileURLToPath } from 'node:url';
import { createHmac } from 'node:crypto';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { eq } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import type { AppContext } from '../src/context.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { externalIdFor } from '../src/domain/conversions.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { signAdminToken } from '../src/lib/tokens.js';
import { MAX_ATTEMPTS, sendPurchaseConversions } from '../src/services/conversions.service.js';

const url = process.env.TEST_DATABASE_URL;
const NOW = new Date('2026-10-20T08:00:00Z');
const WEBHOOK_SECRET = 'shpss_test_secret';
const SALT = 'conv-test-salt';
const CREDS = {
  CONVERSIONS_ID_SALT: SALT,
  META_PIXEL_ID: 'PIXEL1',
  META_CAPI_TOKEN: 'meta-token',
  GA4_MEASUREMENT_ID: 'G-TEST',
  GA4_API_SECRET: 'ga4-secret',
  TIKTOK_PIXEL_ID: 'TTPIX',
  TIKTOK_ACCESS_TOKEN: 'tt-token',
};

type Call = [string, RequestInit];
const okFetch = () => vi.fn(async (..._a: Call) => new Response(JSON.stringify({ code: 0 }), { status: 200 }));

describe.skipIf(!url)('server-side purchase conversions (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  let ctx: AppContext;
  let seq = 0;
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip', SHOPIFY_WEBHOOK_SECRET: WEBHOOK_SECRET, ...CREDS });

  beforeAll(async () => {
    const reset = new pg.Client({ connectionString: url });
    await reset.connect();
    await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
    await reset.end();
    ({ db, pool } = createDb(url!));
    await migrate(db, { migrationsFolder: fileURLToPath(new URL('../drizzle', import.meta.url)) });
    app = await buildApp({
      env,
      db,
      redis: null,
      aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
      fcm: new FcmSender(''),
      now: () => NOW,
    });
    ctx = app.ctx;
  });

  afterEach(() => vi.unstubAllGlobals());

  afterAll(async () => {
    await app?.close();
    await pool?.end();
  });

  async function setFlag(on: boolean) {
    await db
      .insert(s.appConfig)
      .values({ key: 'features', value: { serverConversions: on } })
      .onConflictDoUpdate({ target: s.appConfig.key, set: { value: { serverConversions: on } } });
    await ctx.cache.bumpNamespace('config');
  }

  /** A buyer with one used code on a fresh order; returns the order and the user id. */
  async function paidOrder(opts: { consent?: boolean | null; guest?: boolean } = {}) {
    const n = ++seq;
    const [u] = await db.insert(s.users).values({ displayName: 'Buyer', email: 'buyer@example.com', isGuest: opts.guest ?? false }).returning();
    if (opts.consent !== null) await db.insert(s.consents).values({ userId: u!.id, kind: 'ads_measurement', granted: opts.consent ?? true });
    const [r] = await db.insert(s.rewards).values({ titleAr: 'خصم', titleEn: 'Off', kind: 'fixed_amount', value: 50, costPoints: 500 }).returning();
    const code = `YQ-TEST-${String(n).padStart(4, '0')}`;
    const orderRef = `gid://shopify/Order/${9000 + n}`;
    await db.insert(s.redemptions).values({ userId: u!.id, rewardId: r!.id, costPoints: 500, code, expiresAt: new Date(NOW.getTime() + 86_400_000) });
    const order = {
      id: 9000 + n,
      admin_graphql_api_id: orderRef,
      total_price: '450.00',
      currency: 'EGP',
      processed_at: '2026-10-20T07:59:00Z',
      email: 'buyer@example.com',
      phone: '+201000000000',
      browser_ip: '41.0.0.1',
      customer: { first_name: 'Buyer', last_name: 'Name' },
      discount_codes: [{ code }],
    };
    return { order, orderRef, eventId: String(9000 + n), userId: u!.id };
  }

  const signed = (body: object) => {
    const raw = JSON.stringify(body);
    return {
      method: 'POST' as const,
      url: '/webhooks/shopify/orders-paid',
      headers: { 'content-type': 'application/json', 'x-shopify-hmac-sha256': createHmac('sha256', WEBHOOK_SECRET).update(raw).digest('base64') },
      payload: raw,
    };
  };
  const sends = (orderId: string) => db.select().from(s.conversionSends).where(eq(s.conversionSends.orderId, orderId));

  it('flag OFF by default: nothing is sent even with consent and credentials', async () => {
    const f = okFetch();
    const { order, orderRef, userId } = await paidOrder();
    await db.update(s.redemptions).set({ status: 'used', shopifyOrderId: orderRef }).where(eq(s.redemptions.userId, userId));
    expect(await sendPurchaseConversions(ctx, order, orderRef, f as unknown as typeof fetch)).toEqual({});
    expect(f).not.toHaveBeenCalled();
  });

  it('webhook → one minimal purchase per platform for a consenting buyer; a replay sends nothing', async () => {
    await setFlag(true);
    const f = okFetch();
    vi.stubGlobal('fetch', f);
    const { order, eventId, userId } = await paidOrder();

    const res = await app.inject(signed(order));
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, used: 1 });
    await vi.waitFor(async () => expect((await sends(eventId)).filter((r) => r.status === 'sent')).toHaveLength(3));

    const calls = f.mock.calls as Call[];
    expect(calls).toHaveLength(3);
    const bodies = Object.fromEntries(calls.map(([u, init]) => [new URL(u).hostname, init.body as string]));
    // No personal data from the order, no raw user id; the per-platform hash and the order id are there.
    for (const body of Object.values(bodies)) {
      expect(body).not.toMatch(/buyer@example\.com|\+20100|41\.0\.0\.1|Buyer|YQ-TEST/);
      expect(body).not.toContain(userId);
      expect(body).toContain(`"${eventId}"`);
    }
    expect(JSON.parse(bodies['graph.facebook.com']!).data[0]).toMatchObject({
      event_name: 'Purchase',
      event_id: eventId,
      user_data: { external_id: [externalIdFor(SALT, 'meta', userId)] },
      custom_data: { value: 450, currency: 'EGP' },
    });
    expect(JSON.parse(bodies['www.google-analytics.com']!)).toMatchObject({ client_id: externalIdFor(SALT, 'ga4', userId) });
    expect(JSON.parse(bodies['business-api.tiktok.com']!).data[0]).toMatchObject({ event: 'CompletePayment', user: { external_id: externalIdFor(SALT, 'tiktok', userId) } });

    // The idempotency table keeps no user id or amount.
    expect(Object.keys((await sends(eventId))[0]!).sort()).toEqual(['attempts', 'createdAt', 'orderId', 'platform', 'sentAt', 'status', 'updatedAt']);

    // Shopify replays the webhook: codes stay used, conversions are not resent.
    expect((await app.inject(signed(order))).json()).toEqual({ ok: true, used: 0 });
    expect(await sendPurchaseConversions(ctx, order, order.admin_graphql_api_id, f as unknown as typeof fetch)).toEqual({ meta: 'duplicate', ga4: 'duplicate', tiktok: 'duplicate' });
    await new Promise((r) => setTimeout(r, 50));
    expect(f).toHaveBeenCalledTimes(3);
  });

  it('consent is read at webhook time: withdrawn, never given and guests send nothing', async () => {
    await setFlag(true);
    for (const opts of [{ consent: false }, { consent: null }, { guest: true }]) {
      const f = okFetch();
      const { order, orderRef, eventId } = await paidOrder(opts);
      await db.update(s.redemptions).set({ status: 'used', shopifyOrderId: orderRef }).where(eq(s.redemptions.code, order.discount_codes[0]!.code));
      expect(await sendPurchaseConversions(ctx, order, orderRef, f as unknown as typeof fetch)).toEqual({});
      expect(f).not.toHaveBeenCalled();
      expect(await sends(eventId)).toHaveLength(0);
    }

    // Granted, then withdrawn before the order is paid → nothing.
    const f = okFetch();
    const { order, orderRef, userId } = await paidOrder({ consent: true });
    await db.update(s.consents).set({ granted: false }).where(eq(s.consents.userId, userId));
    await db.update(s.redemptions).set({ status: 'used', shopifyOrderId: orderRef }).where(eq(s.redemptions.userId, userId));
    expect(await sendPurchaseConversions(ctx, order, orderRef, f as unknown as typeof fetch)).toEqual({});
    expect(f).not.toHaveBeenCalled();
  });

  it('only configured platforms send, and nothing without the salt', async () => {
    await setFlag(true);
    const use = async () => {
      const p = await paidOrder();
      await db.update(s.redemptions).set({ status: 'used', shopifyOrderId: p.orderRef }).where(eq(s.redemptions.userId, p.userId));
      return p;
    };
    const only = (extra: Record<string, string>) => ({ ...ctx, env: loadEnv({ NODE_ENV: 'test', ...extra }) });

    const a = await use();
    const f = okFetch();
    expect(await sendPurchaseConversions(only({ CONVERSIONS_ID_SALT: SALT, GA4_MEASUREMENT_ID: 'G-1', GA4_API_SECRET: 'x', META_PIXEL_ID: 'no-token' }), a.order, a.orderRef, f as unknown as typeof fetch)).toEqual({ ga4: 'sent' });
    expect(f).toHaveBeenCalledTimes(1);

    const b = await use();
    const g = okFetch();
    const { CONVERSIONS_ID_SALT: _salt, ...noSalt } = CREDS;
    expect(await sendPurchaseConversions(only(noSalt), b.order, b.orderRef, g as unknown as typeof fetch)).toEqual({});
    expect(await sendPurchaseConversions(only({}), b.order, b.orderRef, g as unknown as typeof fetch)).toEqual({});
    expect(g).not.toHaveBeenCalled();
  });

  it('a failed send is recorded, retried on a later replay, and capped', async () => {
    await setFlag(true);
    const p = await paidOrder();
    await db.update(s.redemptions).set({ status: 'used', shopifyOrderId: p.orderRef }).where(eq(s.redemptions.userId, p.userId));
    const metaOnly = { ...ctx, env: loadEnv({ NODE_ENV: 'test', CONVERSIONS_ID_SALT: SALT, META_PIXEL_ID: 'P', META_CAPI_TOKEN: 'T' }) };
    const down = vi.fn(async () => new Response('', { status: 500 }));

    expect(await sendPurchaseConversions(metaOnly, p.order, p.orderRef, down as unknown as typeof fetch)).toEqual({ meta: 'failed' });
    expect(down).toHaveBeenCalledTimes(2); // one retry
    expect((await sends(p.eventId))[0]).toMatchObject({ status: 'failed', attempts: 1, sentAt: null });

    const f = okFetch();
    expect(await sendPurchaseConversions(metaOnly, p.order, p.orderRef, f as unknown as typeof fetch)).toEqual({ meta: 'sent' });
    expect((await sends(p.eventId))[0]).toMatchObject({ status: 'sent', attempts: 2 });
    expect(await sendPurchaseConversions(metaOnly, p.order, p.orderRef, f as unknown as typeof fetch)).toEqual({ meta: 'duplicate' });

    // Failing every time stops after MAX_ATTEMPTS.
    const q = await paidOrder();
    await db.update(s.redemptions).set({ status: 'used', shopifyOrderId: q.orderRef }).where(eq(s.redemptions.userId, q.userId));
    for (let i = 0; i < MAX_ATTEMPTS; i++) expect(await sendPurchaseConversions(metaOnly, q.order, q.orderRef, down as unknown as typeof fetch)).toEqual({ meta: 'failed' });
    expect(await sendPurchaseConversions(metaOnly, q.order, q.orderRef, down as unknown as typeof fetch)).toEqual({ meta: 'duplicate' });
  });

  it('admin status: flag, salt and platforms as booleans — never a credential', async () => {
    await setFlag(true);
    const [a] = await db.insert(s.adminUsers).values({ name: 'M', email: 'mk-conv@example.com', role: 'marketing', passwordHash: 'x', totpSecret: 'x' }).returning();
    const res = await app.inject({
      method: 'GET',
      url: '/admin/rewards/shopify/status',
      headers: { authorization: `Bearer ${await signAdminToken({ sub: a!.id, role: 'marketing' }, env.ADMIN_JWT_SECRET)}` },
    });
    expect(res.json().conversions).toEqual({ enabled: true, salted: true, platforms: { meta: true, ga4: true, tiktok: true }, lastSentAt: NOW.toISOString() });
    expect(res.body).not.toMatch(/meta-token|ga4-secret|tt-token|conv-test-salt|PIXEL1|G-TEST|TTPIX/);
  });
});
