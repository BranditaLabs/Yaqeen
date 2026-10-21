/**
 * End-to-end tests against a real Postgres. Skipped unless TEST_DATABASE_URL is set
 * (CI provides one; locally: `docker compose up -d postgres` then
 *  TEST_DATABASE_URL=postgres://yaqeen:yaqeen@localhost:5432/yaqeen_test pnpm test`).
 *
 * The database is wiped and migrated at the start of the run.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { eq, sql } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { generateTotpSecret, hashPassword, totp, base32Decode } from '../src/lib/crypto.js';
import { signUserToken } from '../src/lib/tokens.js';

const url = process.env.TEST_DATABASE_URL;
const NOW = new Date('2026-10-20T08:00:00Z'); // 11:00 Cairo, Tuesday — 9 Jumada I 1448

describe.skipIf(!url)('integration (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? '' });
  const auth = (t: string) => ({ authorization: `Bearer ${t}` });

  beforeAll(async () => {
    const reset = new pg.Client({ connectionString: url });
    await reset.connect();
    await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
    await reset.end();

    ({ db, pool } = createDb(url!));
    await migrate(db, { migrationsFolder: new URL('../drizzle', import.meta.url).pathname });
    await db.insert(s.taskRules).values([
      { key: 'wird', labelAr: 'وِرد', labelEn: 'Wird', points: 20, sortOrder: 1 },
      { key: 'morning_azkar', labelAr: 'الصباح', labelEn: 'Morning', points: 10, sortOrder: 2 },
      { key: 'five_prayers', labelAr: 'الصلوات', labelEn: 'Prayers', points: 25, sortOrder: 3 },
      { key: 'evening_azkar', labelAr: 'المساء', labelEn: 'Evening', points: 10, sortOrder: 4 },
      { key: 'listen', labelAr: 'الاستماع', labelEn: 'Listen', points: 10, sortOrder: 5 },
      { key: 'daily_task', labelAr: 'مهمة اليوم', labelEn: 'Daily task', points: 25, sortOrder: 6 },
    ]);

    app = await buildApp({
      env,
      db,
      redis: null,
      aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }), // unconfigured on purpose
      fcm: new FcmSender(''),
      now: () => NOW,
    });
  });

  afterAll(async () => {
    await app?.close();
    await pool?.end();
  });

  async function makeUser(name = 'Ahmed'): Promise<{ id: string; token: string }> {
    const [u] = await db.insert(s.users).values({ displayName: name, email: `${name.toLowerCase()}@example.com` }).returning();
    await db.insert(s.authIdentities).values({ userId: u!.id, provider: 'google', subject: `sub-${u!.id}` });
    return { id: u!.id, token: await signUserToken({ sub: u!.id, guest: false }, env.JWT_SECRET) };
  }

  async function makeAdmin(role: 'super_admin' | 'religious_reviewer' | 'content_editor' | 'support', email: string) {
    const secret = generateTotpSecret();
    await db.insert(s.adminUsers).values({ name: role, email, role, passwordHash: await hashPassword('a-strong-password'), totpSecret: secret });
    const res = await app.inject({
      method: 'POST',
      url: '/admin/auth/login',
      payload: { email, password: 'a-strong-password', totp: totp(base32Decode(secret), NOW.getTime()) },
    });
    expect(res.statusCode).toBe(200);
    return res.json().token as string;
  }

  it('guest can sign in but cannot enroll (points need a real account)', async () => {
    const signIn = await app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'guest' } });
    expect(signIn.statusCode).toBe(200);
    const { accessToken, refreshToken } = signIn.json();
    const enroll = await app.inject({ method: 'POST', url: '/v1/challenge/enroll', headers: auth(accessToken) });
    expect(enroll.json().error.code).toBe('account_required');

    // Refresh rotates: the old refresh token is single-use.
    const r1 = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } });
    expect(r1.statusCode).toBe(200);
    const r2 = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken } });
    expect(r2.statusCode).toBe(401);
  });

  it('challenge: today = 100, a made-up day = 80, retries are idempotent', async () => {
    const u = await makeUser('Sara');
    await app.inject({ method: 'POST', url: '/v1/challenge/enroll', headers: auth(u.token) });
    await db.update(s.challengeEnrollments).set({ startedOn: '2026-10-15' }).where(eq(s.challengeEnrollments.userId, u.id));

    const tasks = ['wird', 'morning_azkar', 'five_prayers', 'evening_azkar', 'listen', 'daily_task'];
    for (const t of tasks) {
      const res = await app.inject({
        method: 'POST',
        url: `/v1/challenge/tasks/${t}/complete`,
        headers: auth(u.token),
        payload: { date: '2026-10-20', clientEventId: `today-${t}` },
      });
      expect(res.statusCode).toBe(200);
    }
    // Offline queue retry of the same event → no double credit.
    const retry = await app.inject({
      method: 'POST',
      url: '/v1/challenge/tasks/wird/complete',
      headers: auth(u.token),
      payload: { date: '2026-10-20', clientEventId: 'today-wird' },
    });
    expect(retry.json().awarded).toBe(0);

    for (const t of tasks) {
      await app.inject({
        method: 'POST',
        url: `/v1/challenge/tasks/${t}/complete`,
        headers: auth(u.token),
        payload: { date: '2026-10-18', clientEventId: `qada-${t}` },
      });
    }

    const summary = (await app.inject({ method: 'GET', url: '/v1/challenge/summary', headers: auth(u.token) })).json();
    expect(summary.balance).toBe(180);
    expect(summary.dayNumber).toBe(6);
    expect(summary.today.status).toBe('done');
    expect(summary.streak).toBe(1); // 19 Oct was missed

    const days = (
      await app.inject({ method: 'GET', url: '/v1/challenge/days?from=2026-10-15&to=2026-10-21', headers: auth(u.token) })
    ).json();
    const byDate = Object.fromEntries(days.map((d: { date: string; status: string; points: number }) => [d.date, d]));
    expect(byDate['2026-10-18']).toMatchObject({ status: 'qada', points: 80 });
    expect(byDate['2026-10-19']).toMatchObject({ status: 'missed', points: 0 });
    expect(byDate['2026-10-21']).toMatchObject({ status: 'future' });
  });

  it('redeem: failed Shopify call refunds the points', async () => {
    const u = await makeUser('Omar');
    await db.insert(s.pointsLedger).values({ userId: u.id, delta: 1200, reason: 'admin_adjustment', refKey: 'test:grant' });
    const [reward] = await db
      .insert(s.rewards)
      .values({ titleAr: 'خصم 50', titleEn: '50 off', kind: 'fixed_amount', value: 50, costPoints: 1000 })
      .returning();
    const res = await app.inject({ method: 'POST', url: `/v1/rewards/${reward!.id}/redeem`, headers: auth(u.token) });
    expect(res.statusCode).toBe(503);
    const [b] = await db
      .select({ s: sql<string>`sum(${s.pointsLedger.delta})` })
      .from(s.pointsLedger)
      .where(eq(s.pointsLedger.userId, u.id));
    expect(Number(b!.s)).toBe(1200);
    const [r] = await db.select().from(s.redemptions).where(eq(s.redemptions.userId, u.id));
    expect(r!.status).toBe('void');
  });

  it('consents are recorded with history', async () => {
    const u = await makeUser('Mona');
    await app.inject({ method: 'PUT', url: '/v1/me/consents', headers: auth(u.token), payload: { kind: 'store_offers', granted: true, source: 'onboarding' } });
    await app.inject({ method: 'PUT', url: '/v1/me/consents', headers: auth(u.token), payload: { kind: 'store_offers', granted: false, source: 'settings' } });
    const cur = (await app.inject({ method: 'GET', url: '/v1/me/consents', headers: auth(u.token) })).json();
    expect(cur.store_offers).toBe(false);
    const events = await db.select().from(s.consentEvents).where(eq(s.consentEvents.userId, u.id));
    expect(events.map((e) => e.granted)).toEqual([true, false]);
  });

  it('admin: points adjustment is audited; content needs a second reviewer', async () => {
    const superToken = await makeAdmin('super_admin', 'root@yaqin-brand.com');
    const reviewerToken = await makeAdmin('religious_reviewer', 'sheikh@yaqin-brand.com');
    const u = await makeUser('Khaled');

    const adj = await app.inject({
      method: 'POST',
      url: `/admin/users/${u.id}/points`,
      headers: auth(superToken),
      payload: { delta: 100, reason: 'technical_compensation', note: 'sync bug' },
    });
    expect(adj.statusCode).toBe(200);
    const audits = await db.select().from(s.auditLog).where(eq(s.auditLog.targetId, u.id));
    expect(audits[0]?.action).toBe('user.points.adjust');

    const list = (await app.inject({ method: 'GET', url: '/admin/users?search=Khaled', headers: auth(superToken) })).json();
    expect(list.items[0]).toMatchObject({ emailMasked: 'k***@example.com', balance: 100 });

    const created = (
      await app.inject({
        method: 'POST',
        url: '/admin/content',
        headers: auth(superToken),
        payload: { type: 'dua', category: 'عام', title: 'دعاء', textAr: 'رَبِّ زِدْنِي عِلْمًا', source: 'طه: 114' },
      })
    ).json();
    await app.inject({ method: 'POST', url: `/admin/content/${created.id}/submit`, headers: auth(superToken) });

    const own = await app.inject({ method: 'POST', url: `/admin/content/${created.id}/review`, headers: auth(superToken), payload: { decision: 'approve' } });
    expect(own.json().error.code).toBe('cannot_review_own_edit');

    const ok = await app.inject({ method: 'POST', url: `/admin/content/${created.id}/review`, headers: auth(reviewerToken), payload: { decision: 'approve' } });
    expect(ok.json().status).toBe('published');

    const pub = (await app.inject({ method: 'GET', url: '/v1/content?type=dua' })).json();
    expect(pub.map((c: { id: string }) => c.id)).toContain(created.id);
  });

  it('admin login rejects a wrong TOTP', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/admin/auth/login',
      payload: { email: 'root@yaqin-brand.com', password: 'a-strong-password', totp: '000000' },
    });
    expect(res.statusCode).toBe(401);
  });
  it('dashboard controls the points program end-to-end', async () => {
    const root = await makeAdmin('super_admin', 'program@yaqin-brand.com');
    const H = auth(root);

    // 1) New program: day = 120, qada cap 60, window 3 days; "listen" switched off.
    const tasks = [
      { key: 'wird', labelAr: 'وِرد القرآن', labelEn: 'Quran wird', points: 40, active: true },
      { key: 'morning_azkar', labelAr: 'أذكار الصباح', labelEn: 'Morning azkar', points: 10, active: true },
      { key: 'five_prayers', labelAr: 'الصلوات الخمس', labelEn: 'Five prayers', points: 25, active: true },
      { key: 'evening_azkar', labelAr: 'أذكار المساء', labelEn: 'Evening azkar', points: 10, active: true },
      { key: 'listen', labelAr: 'الاستماع', labelEn: 'Listening', points: 0, active: false },
      { key: 'daily_task', labelAr: 'مهمة اليوم', labelEn: 'Daily task', points: 35, active: true },
    ];
    const settings = { dailyTotal: 120, qadaDayPoints: 60, qadaWindowDays: 3, challengeLengthDays: 365 };
    const bad = await app.inject({ method: 'PUT', url: '/admin/rewards/program', headers: H, payload: { settings: { ...settings, dailyTotal: 100 }, tasks } });
    expect(bad.json().error.code).toBe('invalid_total');
    expect((await app.inject({ method: 'PUT', url: '/admin/rewards/program', headers: H, payload: { settings, tasks } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'PUT', url: '/admin/rewards/milestones', headers: H, payload: [{ days: 2, points: 70, labelAr: 'يومان', active: true }] })).statusCode).toBe(200);

    const cfg = (await app.inject({ method: 'GET', url: '/v1/config' })).json();
    expect(cfg.points).toEqual({ qadaDayPoints: 60, qadaWindowDays: 3, challengeLengthDays: 365 });

    // 2) The app follows the new rules immediately.
    const u = await makeUser('Huda');
    await app.inject({ method: 'POST', url: '/v1/challenge/enroll', headers: auth(u.token) });
    await db.update(s.challengeEnrollments).set({ startedOn: '2026-10-19' }).where(eq(s.challengeEnrollments.userId, u.id));
    const off = await app.inject({ method: 'POST', url: '/v1/challenge/tasks/listen/complete', headers: auth(u.token), payload: { date: '2026-10-20', clientEventId: 'huda-listen' } });
    expect(off.json().error.code).toBe('task_inactive');

    const active = tasks.filter((t) => t.active).map((t) => t.key);
    for (const t of active) {
      await app.inject({ method: 'POST', url: `/v1/challenge/tasks/${t}/complete`, headers: auth(u.token), payload: { date: '2026-10-19', clientEventId: `h-q-${t}` } });
    }
    let last: { awarded: number; milestoneAwarded: number } | undefined;
    for (const t of active) {
      last = (await app.inject({ method: 'POST', url: `/v1/challenge/tasks/${t}/complete`, headers: auth(u.token), payload: { date: '2026-10-20', clientEventId: `h-t-${t}` } })).json();
    }
    expect(last?.milestoneAwarded).toBe(70);

    const sum = (await app.inject({ method: 'GET', url: '/v1/challenge/summary', headers: auth(u.token) })).json();
    expect(sum.tasks).toHaveLength(5);
    expect(sum.today.status).toBe('done');
    expect(sum.streak).toBe(2);
    expect(sum.balance).toBe(60 + 120 + 70);
    expect(sum.nextMilestone).toBeNull();

    // 3) Bulk grant to everyone enrolled.
    const preview = (await app.inject({ method: 'POST', url: '/admin/rewards/grants/preview', headers: H, payload: { segment: 'all_enrolled', points: 25, reasonAr: 'هدية رمضان' } })).json();
    expect(preview.recipients).toBeGreaterThanOrEqual(1);
    const grant = (await app.inject({ method: 'POST', url: '/admin/rewards/grants', headers: H, payload: { segment: 'all_enrolled', points: 25, reasonAr: 'هدية رمضان' } })).json();
    expect(grant.recipients).toBe(preview.recipients);
    const afterGrant = (await app.inject({ method: 'GET', url: '/v1/challenge/summary', headers: auth(u.token) })).json();
    expect(afterGrant.balance).toBe(275);

    // 4) Per-user monthly limit on a reward (Shopify stubbed to succeed).
    const [reward] = await db
      .insert(s.rewards)
      .values({ titleAr: 'خصم', titleEn: 'Off', kind: 'fixed_amount', value: 20, costPoints: 100, perUserMonthlyLimit: 1 })
      .returning();
    const shopify = app.ctx.shopify as unknown as { createDiscount: () => Promise<string> };
    const original = shopify.createDiscount;
    shopify.createDiscount = async () => 'gid://shopify/DiscountCodeNode/1';
    try {
      const r1 = await app.inject({ method: 'POST', url: `/v1/rewards/${reward!.id}/redeem`, headers: auth(u.token) });
      expect(r1.statusCode).toBe(200);
      expect(r1.json().balanceAfter).toBe(175);
      const r2 = await app.inject({ method: 'POST', url: `/v1/rewards/${reward!.id}/redeem`, headers: auth(u.token) });
      expect(r2.json().error.code).toBe('user_reward_limit_reached');
    } finally {
      shopify.createDiscount = original;
    }

    // 5) Everything above is in the audit log.
    const actions = (await db.select({ a: s.auditLog.action }).from(s.auditLog)).map((r) => r.a);
    expect(actions).toEqual(expect.arrayContaining(['points.program.update', 'points.milestones.update', 'points.grant']));
  });
});
