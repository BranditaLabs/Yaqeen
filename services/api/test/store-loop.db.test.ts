/**
 * Store loop + hardening against Postgres: Shopify orders/paid webhook marks codes used (signed,
 * idempotent), unused codes expire, an edit in review never takes approved content offline, and
 * admin TOTP secrets are sealed at rest (legacy plain ones sealed on the next good login).
 */
import { fileURLToPath } from 'node:url';
import { createHmac, randomBytes } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { eq } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { base32Decode, generateTotpSecret, hashPassword, isSealed, openSecret, secretsKey, totp } from '../src/lib/crypto.js';
import { signAdminToken } from '../src/lib/tokens.js';
import { expireDue } from '../src/services/rewards.service.js';

const url = process.env.TEST_DATABASE_URL;
const NOW = new Date('2026-10-20T08:00:00Z');
const WEBHOOK_SECRET = 'shpss_test_secret';
const KEY_B64 = randomBytes(32).toString('base64');

describe.skipIf(!url)('store loop + hardening (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const env = loadEnv({
    NODE_ENV: 'test',
    DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip',
    SHOPIFY_WEBHOOK_SECRET: WEBHOOK_SECRET,
    ADMIN_SECRETS_KEY: KEY_B64,
  });
  const auth = (t: string) => ({ authorization: `Bearer ${t}` });

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
  });

  afterAll(async () => {
    await app?.close();
    await pool?.end();
  });

  async function codes(...list: { code: string; expiresAt: Date; status?: 'issued' | 'used' }[]) {
    const [u] = await db.insert(s.users).values({ displayName: 'Buyer' }).returning();
    const [r] = await db.insert(s.rewards).values({ titleAr: 'خصم', titleEn: 'Off', kind: 'fixed_amount', value: 50, costPoints: 500 }).returning();
    await db.insert(s.redemptions).values(list.map((c) => ({ userId: u!.id, rewardId: r!.id, costPoints: 500, ...c })));
  }
  const status = async (code: string) => (await db.select().from(s.redemptions).where(eq(s.redemptions.code, code)))[0];
  const signed = (body: object) => {
    const raw = JSON.stringify(body);
    return {
      method: 'POST' as const,
      url: '/webhooks/shopify/orders-paid',
      headers: { 'content-type': 'application/json', 'x-shopify-hmac-sha256': createHmac('sha256', WEBHOOK_SECRET).update(raw).digest('base64') },
      payload: raw,
    };
  };

  it('orders/paid: signed orders mark our codes used, once; others are ignored', async () => {
    const later = new Date(NOW.getTime() + 10 * 86_400_000);
    await codes({ code: 'YQ-AAAA-BBBB', expiresAt: later }, { code: 'YQ-CCCC-DDDD', expiresAt: later });

    const order = { id: 820982911946154500, admin_graphql_api_id: 'gid://shopify/Order/1', discount_codes: [{ code: 'yq-aaaa-bbbb' }, { code: 'SUMMER10' }] };
    const unsigned = await app.inject({ ...signed(order), headers: { 'content-type': 'application/json', 'x-shopify-hmac-sha256': 'bad' } });
    expect(unsigned.statusCode).toBe(401);
    expect((await status('YQ-AAAA-BBBB'))!.status).toBe('issued');

    const ok = await app.inject(signed(order));
    expect(ok.statusCode).toBe(200);
    expect(ok.json()).toEqual({ ok: true, used: 1 });
    const used = (await status('YQ-AAAA-BBBB'))!;
    expect(used).toMatchObject({ status: 'used', shopifyOrderId: 'gid://shopify/Order/1' });
    expect(used.usedAt?.toISOString()).toBe(NOW.toISOString());
    expect((await status('YQ-CCCC-DDDD'))!.status).toBe('issued');

    // Shopify retries: a replay changes nothing.
    expect((await app.inject(signed(order))).json()).toEqual({ ok: true, used: 0 });

    // The admin pill reports the webhook.
    const [a] = await db.insert(s.adminUsers).values({ name: 'M', email: 'mk@example.com', role: 'marketing', passwordHash: 'x', totpSecret: 'x' }).returning();
    const st = (await app.inject({ method: 'GET', url: '/admin/rewards/shopify/status', headers: auth(await signAdminToken({ sub: a!.id, role: 'marketing' }, env.ADMIN_JWT_SECRET)) })).json();
    expect(st.webhook).toEqual({ configured: true, lastUsedAt: NOW.toISOString() });
  });

  it('expires unused codes past their date, and only those', async () => {
    await codes(
      { code: 'YQ-EEEE-0001', expiresAt: new Date(NOW.getTime() - 1000) },
      { code: 'YQ-EEEE-0002', expiresAt: new Date(NOW.getTime() + 1000) },
      { code: 'YQ-EEEE-0003', expiresAt: new Date(NOW.getTime() - 1000), status: 'used' },
    );
    expect(await expireDue(db, NOW)).toBe(1);
    expect((await status('YQ-EEEE-0001'))!.status).toBe('expired');
    expect((await status('YQ-EEEE-0002'))!.status).toBe('issued');
    expect((await status('YQ-EEEE-0003'))!.status).toBe('used');
    expect(await expireDue(db, NOW)).toBe(0);
  });

  it('content: an edit in review keeps the approved version live until approved', async () => {
    const [ed] = await db.insert(s.adminUsers).values({ name: 'Ed', email: 'ed@example.com', role: 'content_editor', passwordHash: 'x', totpSecret: 'x' }).returning();
    const [rv] = await db.insert(s.adminUsers).values({ name: 'Rv', email: 'rv@example.com', role: 'religious_reviewer', passwordHash: 'x', totpSecret: 'x' }).returning();
    const editor = auth(await signAdminToken({ sub: ed!.id, role: 'content_editor' }, env.ADMIN_JWT_SECRET));
    const reviewer = auth(await signAdminToken({ sub: rv!.id, role: 'religious_reviewer' }, env.ADMIN_JWT_SECRET));
    const base = { type: 'dua', category: 'general', title: 'دعاء العلم', textAr: 'رَبِّ زِدْنِي عِلْمًا', source: 'طه: 114' };

    const item = (await app.inject({ method: 'POST', url: '/admin/content', headers: editor, payload: base })).json();
    const served = async () => (await app.inject({ method: 'GET', url: '/v1/content?type=dua' })).json() as { id: string; textAr: string; version: number }[];
    expect(await served()).toEqual([]); // drafts are never served

    await app.inject({ method: 'POST', url: `/admin/content/${item.id}/submit`, headers: editor });
    await app.inject({ method: 'POST', url: `/admin/content/${item.id}/review`, headers: reviewer, payload: { decision: 'approve' } });
    expect((await served())[0]).toMatchObject({ id: item.id, textAr: 'رَبِّ زِدْنِي عِلْمًا', version: 1 });

    // Edit → draft → in review: still served at v1, and the dashboard says so.
    await app.inject({ method: 'PUT', url: `/admin/content/${item.id}`, headers: editor, payload: { ...base, title: 'دعاء طلب العلم' } });
    await app.inject({ method: 'POST', url: `/admin/content/${item.id}/submit`, headers: editor });
    expect((await served())[0]).toMatchObject({ title: 'دعاء العلم', version: 1 });
    const rows = (await app.inject({ method: 'GET', url: '/admin/content', headers: editor })).json();
    expect(rows[0]).toMatchObject({ status: 'pending_review', version: 2, liveVersion: 1 });
    expect(rows[0]).not.toHaveProperty('live');

    // Changes requested: still v1. Approved: v2 replaces it.
    await app.inject({ method: 'POST', url: `/admin/content/${item.id}/review`, headers: reviewer, payload: { decision: 'request_changes', note: 'راجع العنوان' } });
    expect((await served())[0]).toMatchObject({ version: 1 });
    await app.inject({ method: 'POST', url: `/admin/content/${item.id}/submit`, headers: editor });
    await app.inject({ method: 'POST', url: `/admin/content/${item.id}/review`, headers: reviewer, payload: { decision: 'approve' } });
    expect((await served())[0]).toMatchObject({ title: 'دعاء طلب العلم', version: 2 });
  });

  it('admin TOTP secrets are sealed at rest; a legacy plain secret is sealed on login', async () => {
    const key = secretsKey(KEY_B64);
    const secret = generateTotpSecret();
    const [a] = await db
      .insert(s.adminUsers)
      .values({ name: 'Old', email: 'old@example.com', role: 'support', passwordHash: await hashPassword('a-strong-password'), totpSecret: secret })
      .returning();
    const login = (code: string) =>
      app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'old@example.com', password: 'a-strong-password', totp: code } });

    expect((await login(totp(base32Decode(secret), NOW.getTime()))).statusCode).toBe(200);
    const [after] = await db.select().from(s.adminUsers).where(eq(s.adminUsers.id, a!.id));
    expect(isSealed(after!.totpSecret)).toBe(true);
    expect(after!.totpSecret).not.toContain(secret);
    expect(openSecret(after!.totpSecret, key)).toBe(secret);
    // Still logs in with the sealed secret; a wrong code still fails.
    expect((await login(totp(base32Decode(secret), NOW.getTime()))).statusCode).toBe(200);
    expect((await login('000000')).statusCode).toBe(401);

    // New team members are sealed from the start (the plain secret is shown once, never stored).
    const [root] = await db.insert(s.adminUsers).values({ name: 'Root', email: 'root@example.com', role: 'super_admin', passwordHash: 'x', totpSecret: 'x' }).returning();
    const res = await app.inject({
      method: 'POST',
      url: '/admin/settings/team',
      headers: auth(await signAdminToken({ sub: root!.id, role: 'super_admin' }, env.ADMIN_JWT_SECRET)),
      payload: { name: 'New', email: 'new@example.com', role: 'marketing', password: 'another-strong-password' },
    });
    expect(res.statusCode).toBe(200);
    const [fresh] = await db.select().from(s.adminUsers).where(eq(s.adminUsers.email, 'new@example.com'));
    expect(isSealed(fresh!.totpSecret)).toBe(true);
    expect(openSecret(fresh!.totpSecret, key)).toBe(res.json().totpSecret);
  });

  it('Ramadan bonus rules appear in the dashboard switched off, and existing rules are left alone', async () => {
    await db.insert(s.bonusRules).values({ kind: 'friday_kahf', labelAr: 'الكهف', points: 25, enabled: true });
    const [a] = await db.insert(s.adminUsers).values({ name: 'S', email: 'sup-r@example.com', role: 'support', passwordHash: 'x', totpSecret: 'x' }).returning();
    const res = await app.inject({ method: 'GET', url: '/admin/rewards/program', headers: auth(await signAdminToken({ sub: a!.id, role: 'support' }, env.ADMIN_JWT_SECRET)) });
    const bonuses = res.json().bonuses as { kind: string; enabled: boolean; points: number }[];
    for (const k of ['ramadan_fast', 'taraweeh', 'ramadan_juz', 'white_days_fast']) {
      expect(bonuses.find((b) => b.kind === k)).toMatchObject({ enabled: false });
    }
    expect(bonuses.find((b) => b.kind === 'friday_kahf')).toMatchObject({ enabled: true, points: 25 });
  });
});
