/**
 * Product analytics against Postgres: consent gate, closed list, no account link, PostHog forwarding
 * shape, aggregates with small counts withheld, retention purge.
 */
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { signAdminToken, signUserToken } from '../src/lib/tokens.js';
import { purgeOld } from '../src/services/product-analytics.service.js';

const url = process.env.TEST_DATABASE_URL;
const NOW = new Date('2026-10-20T08:00:00Z');

describe.skipIf(!url)('product analytics (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip', POSTHOG_KEY: 'phc_test' });
  const auth = (t: string) => ({ authorization: `Bearer ${t}` });
  const posted: unknown[] = [];

  beforeAll(async () => {
    const reset = new pg.Client({ connectionString: url });
    await reset.connect();
    await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
    await reset.end();
    ({ db, pool } = createDb(url!));
    await migrate(db, { migrationsFolder: fileURLToPath(new URL('../drizzle', import.meta.url)) });
    vi.stubGlobal('fetch', async (u: string, init: RequestInit) => {
      posted.push({ url: u, body: JSON.parse(String(init.body)) });
      return new Response('{}', { status: 200 });
    });
    app = await buildApp({
      env,
      db,
      redis: null,
      aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
      fcm: new FcmSender(''),
      now: () => NOW,
    });
  });

  afterAll(async () => {
    vi.unstubAllGlobals();
    await app?.close();
    await pool?.end();
  });

  async function user(consent: boolean) {
    const [u] = await db.insert(s.users).values({ displayName: 'A', isGuest: true }).returning();
    if (consent) await db.insert(s.consents).values({ userId: u!.id, kind: 'product_analytics', granted: true });
    return { id: u!.id, token: await signUserToken({ sub: u!.id, guest: true }, env.JWT_SECRET) };
  }
  const anon = (i: number) => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`;
  const batch = (anonId: string, events: { name: string; props?: Record<string, string>; at?: string }[]) => ({
    anonId,
    platform: 'android',
    appVersion: '1.0.0',
    locale: 'ar',
    events: events.map((e) => ({ props: {}, at: NOW.toISOString(), ...e })),
  });

  it('stores nothing without consent, only closed-list events with it, and never the account', async () => {
    const no = await user(false);
    const r0 = await app.inject({ method: 'POST', url: '/v1/me/events', headers: auth(no.token), payload: batch(anon(1), [{ name: 'app_open' }]) });
    expect(r0.statusCode).toBe(202);
    expect(r0.json().accepted).toBe(0);

    const yes = await user(true);
    const r1 = await app.inject({
      method: 'POST',
      url: '/v1/me/events',
      headers: auth(yes.token),
      payload: batch(anon(2), [
        { name: 'app_open' },
        { name: 'tab_view', props: { tab: 'home' } },
        { name: 'tab_view', props: { tab: 'quran' } }, // worship tab: not allowed
        { name: 'prayer_done' }, // not an event
        { name: 'onboarding_step', props: { step: 'consent', surah: '18' } }, // unknown prop
        { name: 'store_click', props: { from: 'redeem' }, at: '2020-01-01T00:00:00.000Z' }, // implausible time → now
      ]),
    });
    expect(r1.json().accepted).toBe(3);
    const rows = await db.select().from(s.productEvents);
    expect(rows.map((r) => r.name).sort()).toEqual(['app_open', 'store_click', 'tab_view']);
    expect(rows.every((r) => r.anonId === anon(2))).toBe(true);
    expect(JSON.stringify(rows)).not.toContain(yes.id);
    expect(rows.find((r) => r.name === 'store_click')!.occurredAt.toISOString()).toBe(NOW.toISOString());

    // Forwarded to PostHog EU without IP, GeoIP or person profiles; keyed by the install id only.
    await new Promise((r) => setTimeout(r, 10));
    const ph = posted.at(-1) as { url: string; body: { api_key: string; batch: { distinct_id: string; properties: Record<string, unknown> }[] } };
    expect(ph.url).toBe('https://eu.i.posthog.com/batch/');
    expect(ph.body.batch).toHaveLength(3);
    expect(ph.body.batch[0]!.distinct_id).toBe(anon(2));
    expect(ph.body.batch[0]!.properties).toMatchObject({ $ip: null, $geoip_disable: true, $process_person_profile: false });
    expect(JSON.stringify(ph.body)).not.toContain(yes.id);

    // Validation: bad install id or oversized batch is refused outright.
    expect((await app.inject({ method: 'POST', url: '/v1/me/events', headers: auth(yes.token), payload: batch('not-a-uuid', [{ name: 'app_open' }]) })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: '/v1/me/events', payload: batch(anon(3), [{ name: 'app_open' }]) })).statusCode).toBe(401);
  });

  it('admins see aggregates only, with small counts withheld', async () => {
    const yes = await user(true);
    for (let i = 10; i < 35; i++) {
      await app.inject({
        method: 'POST',
        url: '/v1/me/events',
        headers: auth(yes.token),
        payload: batch(anon(i), [{ name: 'app_open' }, { name: 'onboarding_step', props: { step: 'welcome' } }, ...(i < 20 ? [{ name: 'onboarding_complete' }] : [])]),
      });
    }
    const [a] = await db.insert(s.adminUsers).values({ name: 'M', email: 'm@example.com', role: 'marketing', passwordHash: 'x', totpSecret: 'x' }).returning();
    const tok = await signAdminToken({ sub: a!.id, role: 'marketing' }, env.ADMIN_JWT_SECRET);
    const rep = (await app.inject({ method: 'GET', url: '/admin/analytics?days=7', headers: auth(tok) })).json();
    expect(rep.activeInstalls.at(-1)).toEqual({ date: '2026-10-20', value: 26 });
    expect(rep.events.find((e: { name: string }) => e.name === 'app_open')).toMatchObject({ total: 26, installs: 26 });
    expect(rep.onboardingFunnel).toEqual([
      { step: 'welcome', installs: 25 },
      { step: 'complete', installs: null }, // 10 < 20: withheld
    ]);
    expect(rep.events.find((e: { name: string }) => e.name === 'tab_view').total).toBeNull();
    expect(JSON.stringify(rep)).not.toMatch(/0000-4000-8000/);
    const editor = await signAdminToken({ sub: a!.id, role: 'content_editor' }, env.ADMIN_JWT_SECRET);
    expect((await app.inject({ method: 'GET', url: '/admin/analytics', headers: auth(editor) })).statusCode).toBe(403);
  });

  it('retention removes events older than 180 days', async () => {
    await db.insert(s.productEvents).values({ anonId: anon(99), name: 'app_open', platform: 'ios', appVersion: '1', locale: 'en', occurredAt: new Date('2026-01-01T00:00:00Z') });
    expect(await purgeOld(db, NOW)).toBe(1);
  });
});
