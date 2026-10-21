/**
 * Postgres tests for the endpoints added by APP_SPEC §8.2 (guest link, campaign opens, merged
 * calendar, catalogues, admin aggregates, exports, splash-verse review, erasure). Skipped
 * without TEST_DATABASE_URL — see integration.db.test.ts.
 */
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { eq, sql } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import type { HijriDay } from '@yaqeen/contracts';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { HIJRI_MONTHS_AR } from '../src/domain/hijri.js';
import { addDays } from '../src/domain/points.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender, type PushMessage } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { purgeDeleted } from '../src/jobs/purge-deleted.js';
import { signAdminToken, signUserToken } from '../src/lib/tokens.js';
import { resetActivityCache } from '../src/services/activity.service.js';

// ID tokens are verified against Google/Apple JWKS in production; here the token *is* the subject.
vi.mock('../src/integrations/oidc.js', () => ({
  verifyGoogleIdToken: async (t: string) => ({ subject: t, email: `${t}@gmail.com`, name: 'Linked User' }),
  verifyAppleIdToken: async (t: string) => ({ subject: t, email: null, name: null }),
}));

const url = process.env.TEST_DATABASE_URL;
const NOW = new Date('2026-10-20T08:00:00Z'); // Tuesday — 9 Jumada I 1448 (UAQ)

/** Synthetic UAQ days around NOW: 20 Oct 2026 = 9/5/1448; Jumada I has 30 days here. */
function fakeUaq(from: string, to: string): HijriDay[] {
  const out: HijriDay[] = [];
  for (let d = from; d <= to; d = addDays(d, 1)) {
    const offset = Math.round((Date.parse(d) - Date.parse('2026-10-20')) / 86_400_000);
    let day = 9 + offset;
    let month = 5;
    while (day > 30) {
      day -= 30;
      month += 1;
    }
    while (day < 1) {
      day += 30;
      month -= 1;
    }
    out.push({ gregorian: d, hijriDay: day, hijriMonth: month, hijriYear: 1448, hijriMonthNameAr: HIJRI_MONTHS_AR[month - 1]!, weekday: new Date(`${d}T00:00:00Z`).getUTCDay() });
  }
  return out;
}

describe.skipIf(!url)('spec v1 endpoints (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip' });
  const auth = (t: string) => ({ authorization: `Bearer ${t}` });
  const pushes: PushMessage[] = [];

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
    const aladhan = new AlAdhanClient(env.ALADHAN_BASE_URL, null);
    aladhan.range = async (from: string, to: string) => fakeUaq(from, to);
    const fcm = new FcmSender('');
    Object.defineProperty(fcm, 'configured', { get: () => true });
    fcm.sendMany = async (m: PushMessage[]) => {
      pushes.push(...m);
      return { ok: m.length, invalidTokens: [] };
    };
    resetActivityCache();
    app = await buildApp({
      env,
      db,
      redis: null,
      aladhan,
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
      fcm,
      now: () => NOW,
    });
  });

  afterAll(async () => {
    await app?.close();
    await pool?.end();
  });

  async function makeUser(name: string): Promise<{ id: string; token: string }> {
    const [u] = await db.insert(s.users).values({ displayName: name, email: `${name.toLowerCase()}@example.com` }).returning();
    await db.insert(s.authIdentities).values({ userId: u!.id, provider: 'google', subject: `sub-${name}` });
    return { id: u!.id, token: await signUserToken({ sub: u!.id, guest: false }, env.JWT_SECRET) };
  }

  // Login itself is covered in integration.db.test.ts (and rate-limited to 5 per 5 min).
  async function makeAdmin(role: 'super_admin' | 'religious_reviewer' | 'content_editor' | 'support' | 'marketing', email: string) {
    const [a] = await db.insert(s.adminUsers).values({ name: role, email, role, passwordHash: 'unused', totpSecret: 'unused' }).returning();
    return signAdminToken({ sub: a!.id, role }, env.ADMIN_JWT_SECRET);
  }

  it('config exposes dailyTotal, the cheapest reward and new flags (off by default)', async () => {
    await db.insert(s.rewards).values({ titleAr: 'خصم', titleEn: 'Off', kind: 'fixed_amount', value: 50, costPoints: 1000 });
    const cfg = (await app.inject({ method: 'GET', url: '/v1/config' })).json();
    expect(cfg.points).toMatchObject({ dailyTotal: 100, cheapestRewardPoints: 1000 });
    expect(cfg.features).toMatchObject({ recite: false, ramadan: false, tafsirFull: false, challenge: true });
    expect(cfg.featureRollout).toEqual({});
  });

  it('guest → new Google identity keeps the same account', async () => {
    const guest = (await app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'guest' } })).json();
    const res = await app.inject({ method: 'POST', url: '/v1/auth/link', headers: auth(guest.accessToken), payload: { provider: 'google', idToken: 'google-new-person' } });
    expect(res.statusCode).toBe(200);
    expect(res.json().user).toMatchObject({ id: guest.user.id, isGuest: false, displayName: 'Linked User' });
    const again = await app.inject({ method: 'POST', url: '/v1/auth/link', headers: auth(res.json().accessToken), payload: { provider: 'google', idToken: 'google-new-person' } });
    expect(again.json().error.code).toBe('not_a_guest');
  });

  it('guest → existing account: points move with two ledger rows, audited', async () => {
    const owner = await makeUser('AccountOwner');
    await db.insert(s.pointsLedger).values({ userId: owner.id, delta: 500, reason: 'task', refKey: 'seed:owner' });
    const guest = (await app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'guest' } })).json();
    await db.insert(s.pointsLedger).values({ userId: guest.user.id, delta: 70, reason: 'grant', refKey: 'seed:guest' });

    const res = await app.inject({ method: 'POST', url: '/v1/auth/link', headers: auth(guest.accessToken), payload: { provider: 'google', idToken: 'sub-AccountOwner' } });
    expect(res.json().user.id).toBe(owner.id);
    const bal = async (id: string) => Number((await db.select({ t: sql<string>`sum(${s.pointsLedger.delta})` }).from(s.pointsLedger).where(eq(s.pointsLedger.userId, id)))[0]!.t);
    expect(await bal(owner.id)).toBe(570);
    expect(await bal(guest.user.id)).toBe(0);
    const [g] = await db.select().from(s.users).where(eq(s.users.id, guest.user.id));
    expect(g!.mergedInto).toBe(owner.id);
    const [a] = await db.select().from(s.auditLog).where(eq(s.auditLog.action, 'auth.link'));
    expect(a).toBeDefined();
    // The guest session is over.
    const refresh = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: guest.refreshToken } });
    expect(refresh.statusCode).toBe(401);
  });

  it('campaign opens count once', async () => {
    const u = await makeUser('Reader');
    const [admin] = await db.insert(s.adminUsers).values({ name: 'm', email: 'm0@x.com', role: 'marketing', passwordHash: 'x', totpSecret: 'x' }).returning();
    const [c] = await db
      .insert(s.campaigns)
      .values({ name: 'c', kind: 'offers', segment: 'all', titleAr: 'ت', bodyAr: 'ن', titleEn: 't', bodyEn: 'b', deepLink: 'store', schedule: 'now', status: 'sent', sentCount: 1, createdBy: admin!.id })
      .returning();
    await db.insert(s.campaignDeliveries).values({ campaignId: c!.id, userId: u.id, kind: 'offers' });
    const r1 = await app.inject({ method: 'POST', url: `/v1/me/campaigns/${c!.id}/opened`, headers: auth(u.token) });
    const r2 = await app.inject({ method: 'POST', url: `/v1/me/campaigns/${c!.id}/opened`, headers: auth(u.token) });
    expect([r1.json().counted, r2.json().counted]).toEqual([true, false]);
    const [after] = await db.select().from(s.campaigns).where(eq(s.campaigns.id, c!.id));
    expect(after!.openCount).toBe(1);
  });

  it('merged calendar: Hijri + statuses + special days for one month', async () => {
    const u = await makeUser('Cal');
    await app.inject({ method: 'POST', url: '/v1/challenge/enroll', headers: auth(u.token) });
    await db.update(s.challengeEnrollments).set({ startedOn: '2026-10-15' }).where(eq(s.challengeEnrollments.userId, u.id));
    await app.inject({ method: 'POST', url: '/v1/challenge/tasks/wird/complete', headers: auth(u.token), payload: { date: '2026-10-18', clientEventId: 'cal-qada-wird' } });

    const res = await app.inject({ method: 'GET', url: '/v1/challenge/calendar?month=2026-10', headers: auth(u.token) });
    expect(res.statusCode).toBe(200);
    const cal = res.json();
    expect(cal).toMatchObject({ month: '2026-10', enrolled: true, startedOn: '2026-10-15', endsOn: '2027-10-14', today: '2026-10-20', dayNumber: 6, qadaWindowDays: 7 });
    expect(cal.days).toHaveLength(31);
    const byDate = Object.fromEntries(cal.days.map((d: { gregorian: string }) => [d.gregorian, d]));
    expect(byDate['2026-10-01'].challenge).toBeNull(); // outside the journey
    expect(byDate['2026-10-18'].challenge.status).toBe('partial');
    expect(byDate['2026-10-19'].challenge.status).toBe('missed');
    expect(byDate['2026-10-24']).toMatchObject({ hijriDay: 13, special: expect.arrayContaining(['white_day']) });
    expect(byDate['2026-10-23'].special).toContain('friday');
  });

  it('reciters and packs catalogues', async () => {
    await db.insert(s.reciters).values([
      { id: 'b', nameAr: 'ب', nameEn: 'B', baseUrl: 'https://cdn/b', sortOrder: 2 },
      { id: 'a', nameAr: 'أ', nameEn: 'A', baseUrl: 'https://cdn/a', sortOrder: 1 },
      { id: 'off', nameAr: 'x', nameEn: 'x', baseUrl: 'https://cdn/x', active: false },
    ]);
    await db.insert(s.contentPacks).values({ id: 'tafsir-muyassar', kind: 'tafsir', titleAr: 'التفسير الميسر', titleEn: 'Al-Muyassar', version: 1, url: 'https://cdn/t.db', sha256: 'a'.repeat(64), sizeBytes: 19_000_000 });
    const rec = (await app.inject({ method: 'GET', url: '/v1/content/reciters' })).json();
    expect(rec.map((r: { id: string }) => r.id)).toEqual(['a', 'b']);
    const packs = (await app.inject({ method: 'GET', url: '/v1/content/packs' })).json();
    expect(packs[0]).toMatchObject({ id: 'tafsir-muyassar', kind: 'tafsir', sha256: 'a'.repeat(64) });
  });

  it('admin aggregates are k-anonymous', async () => {
    const token = await makeAdmin('marketing', 'mk@yaqin-brand.com');
    const H = auth(token);
    // 24 active users today, 3 yesterday.
    const ids: string[] = [];
    for (let i = 0; i < 24; i++) {
      const [u] = await db.insert(s.users).values({ displayName: `k${i}` }).returning();
      ids.push(u!.id);
    }
    await db.insert(s.userActivityDays).values(ids.map((userId) => ({ userId, date: '2026-10-20' })));
    await db.insert(s.userActivityDays).values(ids.slice(0, 3).map((userId) => ({ userId, date: '2026-10-19' })));
    const series = (await app.inject({ method: 'GET', url: '/admin/overview/series?metric=dau&range=7d', headers: H })).json();
    expect(series.points).toHaveLength(7);
    const at = (d: string) => series.points.find((p: { date: string }) => p.date === d).value;
    expect(at('2026-10-20')).toBeGreaterThanOrEqual(24);
    expect(at('2026-10-19')).toBeNull();
    expect(at('2026-10-14')).toBe(0);

    // Fewer than 20 participants → percentages are suppressed.
    const adh = (await app.inject({ method: 'GET', url: '/admin/overview/adherence', headers: H })).json();
    expect(adh.participants).toBeLessThan(20);
    expect(adh.wirdPct).toBeNull();
    const funnel = (await app.inject({ method: 'GET', url: '/admin/overview/funnel', headers: H })).json();
    expect(funnel.steps.map((x: { days: number }) => x.days)).toEqual([1, 7, 30, 100]);
    expect(funnel.steps[0].users).toBeNull();

    const alerts = (await app.inject({ method: 'GET', url: '/admin/overview/alerts', headers: H })).json();
    expect(alerts.map((a: { kind: string }) => a.kind)).toContain('daily_task_missing');
  });

  it('support export leaves out worship history and is audited', async () => {
    const support = await makeAdmin('support', 'sp@yaqin-brand.com');
    const u = await makeUser('Exported');
    await app.inject({ method: 'POST', url: '/v1/challenge/enroll', headers: auth(u.token) });
    await app.inject({ method: 'POST', url: '/v1/challenge/tasks/five_prayers/complete', headers: auth(u.token), payload: { date: '2026-10-20', clientEventId: 'exp-prayers' } });

    const mine = (await app.inject({ method: 'GET', url: '/v1/me/export', headers: auth(u.token) })).json();
    expect(mine.taskCompletions).toHaveLength(1);
    const res = await app.inject({ method: 'GET', url: `/admin/users/${u.id}/export`, headers: auth(support) });
    expect(res.statusCode).toBe(200);
    const exp = res.json();
    expect(exp.taskCompletions).toBeUndefined();
    expect(JSON.stringify(exp)).not.toContain('five_prayers');
    expect(exp.pointsLedger).toHaveLength(1);
    const audits = await db.select().from(s.auditLog).where(eq(s.auditLog.action, 'user.export'));
    expect(audits[0]!.targetId).toBe(u.id);
  });

  it('campaign test send goes only to the admin test devices', async () => {
    const token = await makeAdmin('marketing', 'mk2@yaqin-brand.com');
    const H = auth(token);
    const payload = { titleAr: 'عرض الجمعة', bodyAr: 'خصم على سجاد الصلاة', deepLink: 'store' };
    expect((await app.inject({ method: 'POST', url: '/admin/campaigns/test', headers: H, payload })).json().error.code).toBe('no_test_devices');
    await app.inject({ method: 'PUT', url: '/admin/auth/me/test-devices', headers: H, payload: { tokens: ['fcm-test-token-0123456789'] } });
    pushes.length = 0;
    const res = await app.inject({ method: 'POST', url: '/admin/campaigns/test', headers: H, payload });
    expect(res.json()).toEqual({ sent: 1, invalid: 0 });
    expect(pushes).toEqual([expect.objectContaining({ token: 'fcm-test-token-0123456789', link: 'yaqeen://store', title: '[تجربة] عرض الجمعة' })]);
    const lint = await app.inject({ method: 'POST', url: '/admin/campaigns/test', headers: H, payload: { ...payload, bodyAr: 'آخر فرصة للخصم' } });
    expect(lint.json().error.code).toBe('copy_issues');
  });

  it('Shopify status reports an unconfigured store without failing', async () => {
    const token = await makeAdmin('support', 'sp2@yaqin-brand.com');
    const res = await app.inject({ method: 'GET', url: '/admin/rewards/shopify/status', headers: auth(token) });
    expect(res.json()).toMatchObject({ configured: false, connected: false });
  });

  it('splash verse goes live only after a second-person religious review', async () => {
    const editor = await makeAdmin('content_editor', 'ed@yaqin-brand.com');
    const reviewer = await makeAdmin('religious_reviewer', 'rv@yaqin-brand.com');
    const root = await makeAdmin('super_admin', 'root2@yaqin-brand.com');
    const verse = { textAr: 'أَلَا بِذِكْرِ ٱللَّهِ تَطْمَئِنُّ ٱلْقُلُوبُ', reference: 'الرعد: 28' };

    const direct = await app.inject({ method: 'PATCH', url: '/admin/settings/config', headers: auth(root), payload: { splashVerse: verse } });
    expect(direct.json().error.code).toBe('use_splash_verse_endpoint');

    const proposed = (await app.inject({ method: 'PUT', url: '/admin/settings/splash-verse', headers: auth(editor), payload: verse })).json();
    expect(proposed.status).toBe('pending_review');
    expect((await app.inject({ method: 'GET', url: '/v1/config' })).json().splashVerse.reference).toBe('الحجر: 99');

    const own = await app.inject({ method: 'POST', url: `/admin/content/${proposed.id}/review`, headers: auth(editor), payload: { decision: 'approve' } });
    expect(own.statusCode).toBe(403);
    const ok = await app.inject({ method: 'POST', url: `/admin/content/${proposed.id}/review`, headers: auth(reviewer), payload: { decision: 'approve' } });
    expect(ok.json().status).toBe('published');
    expect((await app.inject({ method: 'GET', url: '/v1/config' })).json().splashVerse).toEqual(verse);
    // Never synced as dua/zikr content.
    const content = (await app.inject({ method: 'GET', url: '/v1/content' })).json();
    expect(content.map((c: { type: string }) => c.type)).not.toContain('splash_verse');
  });

  it('erasure: sessions end now, the account is anonymised after 30 days, the ledger stays', async () => {
    const u = await makeUser('Leaving');
    await db.insert(s.pointsLedger).values({ userId: u.id, delta: 40, reason: 'task', refKey: 'seed:leaving' });
    const session = (await app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'google', idToken: 'sub-Leaving' } })).json();
    const del = await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(u.token) });
    expect(del.json()).toEqual({ status: 'deletion_requested', graceDays: 30 });
    expect((await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: session.refreshToken } })).statusCode).toBe(401);

    expect(await purgeDeleted(db, new Date(NOW.getTime() + 10 * 86_400_000))).toBe(0);
    expect(await purgeDeleted(db, new Date(NOW.getTime() + 31 * 86_400_000))).toBe(1);
    const [after] = await db.select().from(s.users).where(eq(s.users.id, u.id));
    expect(after).toMatchObject({ status: 'deleted', displayName: null, email: null });
    expect(await db.select().from(s.authIdentities).where(eq(s.authIdentities.userId, u.id))).toHaveLength(0);
    expect(await db.select().from(s.pointsLedger).where(eq(s.pointsLedger.userId, u.id))).toHaveLength(1);
    const signIn = await app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'google', idToken: 'sub-Leaving' } });
    expect(signIn.json().user.id).not.toBe(u.id); // a fresh account; the old one is gone
  });

  it('a monthly cap reports reward_out_of_stock', async () => {
    const u = await makeUser('Shopper');
    await db.insert(s.pointsLedger).values({ userId: u.id, delta: 5000, reason: 'grant', refKey: 'seed:shopper' });
    const [r] = await db.insert(s.rewards).values({ titleAr: 'محدود', titleEn: 'Limited', kind: 'free_shipping', value: 0, costPoints: 100, monthlyCap: 1 }).returning();
    await db.insert(s.redemptions).values({ userId: u.id, rewardId: r!.id, code: 'YQ-TEST-0001', costPoints: 100, expiresAt: NOW });
    const res = await app.inject({ method: 'POST', url: `/v1/rewards/${r!.id}/redeem`, headers: auth(u.token) });
    expect(res.json().error.code).toBe('reward_out_of_stock');
  });
});
