/**
 * Public profile cards against Postgres: draft → publish → public page/JSON, privacy of what a
 * scanner sees, handle rules, guests, view counting, and erasure hiding the card at once.
 * Skipped without TEST_DATABASE_URL — see integration.db.test.ts.
 */
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
import { signAdminToken, signUserToken } from '../src/lib/tokens.js';
import { resetActivityCache } from '../src/services/activity.service.js';

const url = process.env.TEST_DATABASE_URL;
const NOW = new Date('2026-10-20T08:00:00Z');

describe.skipIf(!url)('public profile cards (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip', PUBLIC_PROFILE_BASE_URL: 'https://id.test' });
  const auth = (t: string) => ({ authorization: `Bearer ${t}` });

  beforeAll(async () => {
    const reset = new pg.Client({ connectionString: url });
    await reset.connect();
    await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
    await reset.end();
    ({ db, pool } = createDb(url!));
    await migrate(db, { migrationsFolder: new URL('../drizzle', import.meta.url).pathname });
    resetActivityCache();
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

  async function makeUser(name: string, guest = false) {
    const [u] = await db.insert(s.users).values({ displayName: name, isGuest: guest }).returning();
    return { id: u!.id, token: await signUserToken({ sub: u!.id, guest }, env.JWT_SECRET) };
  }

  const card = (over: Record<string, unknown> = {}) => ({
    published: true,
    handle: 'ahmed',
    displayName: 'أحمد',
    bio: 'من القاهرة',
    links: [{ kind: 'instagram', value: '@ahmed' }],
    show: { level: true, streak: true, challengeDay: false, badges: true, memberSince: false },
    theme: 'gold',
    ...over,
  });

  it('a draft is suggested, nothing is public until published', async () => {
    const u = await makeUser('Ahmed Ali');
    const draft = (await app.inject({ method: 'GET', url: '/v1/me/public-profile', headers: auth(u.token) })).json();
    expect(draft).toMatchObject({ published: false, handle: 'ahmed_ali', url: 'https://id.test/u/ahmed_ali', views: 0 });
    expect((await app.inject({ method: 'GET', url: '/u/ahmed_ali' })).statusCode).toBe(404);
  });

  it('publish → page and JSON show only what was switched on', async () => {
    const u = await makeUser('Ahmed');
    // Lifetime points 2,300 (a redemption does not lower the level) + a 7-day milestone.
    await db.insert(s.pointsLedger).values([
      { userId: u.id, delta: 2200, reason: 'task', refKey: 'seed:1' },
      { userId: u.id, delta: 100, reason: 'milestone', refKey: 'milestone:7' },
      { userId: u.id, delta: -1000, reason: 'redemption', refKey: 'seed:r' },
    ]);
    const put = await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(u.token), payload: card() });
    expect(put.statusCode).toBe(200);
    expect(put.json()).toMatchObject({ published: true, handle: 'ahmed', url: 'https://id.test/u/ahmed' });

    const json = (await app.inject({ method: 'GET', url: '/v1/public/profiles/ahmed' })).json();
    expect(json).toMatchObject({ handle: 'ahmed', displayName: 'أحمد', theme: 'gold', streak: 0, badges: [7], challengeDay: null, memberSince: null });
    expect(json.level).toMatchObject({ level: 3, nameAr: 'مواظب' });
    // Never worship detail.
    expect(JSON.stringify(json)).not.toMatch(/five_prayers|wird|azkar|task/);

    const page = await app.inject({ method: 'GET', url: '/u/AHMED', headers: { 'user-agent': 'Mozilla/5.0 (iPhone)' } });
    expect(page.statusCode).toBe(200);
    expect(page.headers['content-type']).toContain('text/html');
    expect(page.body).toContain('أحمد');
    expect(page.body).toContain('https://instagram.com/ahmed');
    expect(page.body).toContain('https://id.test/get-app?ref=ahmed');
  });

  it('journey: private milestones for the owner, shown publicly only when switched on', async () => {
    const u = await makeUser('Journey');
    await db.update(s.users).set({ createdAt: new Date('2026-08-01T10:00:00Z') }).where(eq(s.users.id, u.id));
    await db.insert(s.challengeEnrollments).values({ userId: u.id, startedOn: '2026-08-02' });
    await db.insert(s.pointsLedger).values([
      { userId: u.id, delta: 300, reason: 'task', refKey: 'j:1', createdAt: new Date('2026-08-10T09:00:00Z') },
      { userId: u.id, delta: -200, reason: 'redemption', refKey: 'j:r', createdAt: new Date('2026-08-11T09:00:00Z') },
      { userId: u.id, delta: 100, reason: 'milestone', refKey: 'milestone:7', createdAt: new Date('2026-08-12T09:00:00Z') },
      { userId: u.id, delta: 150, reason: 'task', refKey: 'j:2', createdAt: new Date('2026-09-01T09:00:00Z') },
    ]);

    const mine = (await app.inject({ method: 'GET', url: '/v1/me/journey', headers: auth(u.token) })).json();
    expect(mine).toMatchObject({ lifetimePoints: 550, level: { level: 2, nextAt: 2000 }, challengeOf: 365 });
    // The redemption doesn't delay the level: 300 + 100 + 150 crosses 500 on 1 Sep.
    expect(mine.events).toEqual([
      { kind: 'level', date: '2026-09-01', value: 2 },
      { kind: 'challenge_day', date: '2026-08-31', value: 30 },
      { kind: 'badge', date: '2026-08-12', value: 7 },
      { kind: 'challenge_start', date: '2026-08-02', value: 1 },
      { kind: 'joined', date: '2026-08-01', value: null },
    ]);
    expect(JSON.stringify(mine)).not.toMatch(/five_prayers|wird|azkar|task/);
    expect((await app.inject({ method: 'GET', url: '/v1/me/journey' })).statusCode).toBe(401);

    await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(u.token), payload: card({ handle: 'journey' }) });
    expect((await app.inject({ method: 'GET', url: '/v1/public/profiles/journey' })).json().timeline).toBeNull();
    await app.inject({
      method: 'PUT',
      url: '/v1/me/public-profile',
      headers: auth(u.token),
      payload: card({ handle: 'journey', show: { level: true, streak: false, challengeDay: false, badges: false, memberSince: false, timeline: true } }),
    });
    const pub = (await app.inject({ method: 'GET', url: '/v1/public/profiles/journey' })).json();
    expect(pub.timeline).toHaveLength(5);
    const page = await app.inject({ method: 'GET', url: '/u/journey', headers: { 'accept-language': 'en' } });
    expect(page.body).toContain('Day 30 of the 365-day journey');
  });

  it('counts human opens only', async () => {
    await app.inject({ method: 'GET', url: '/u/ahmed', headers: { 'user-agent': 'WhatsApp/2.0 preview' } });
    await new Promise((r) => setTimeout(r, 50));
    const [row] = await db.select().from(s.publicProfiles).where(eq(s.publicProfiles.handle, 'ahmed'));
    expect(row!.views).toBe(1); // the iPhone visit above
  });

  it('handles are unique, reserved names refused, guests cannot publish', async () => {
    const other = await makeUser('Other');
    const taken = await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(other.token), payload: card() });
    expect(taken.statusCode).toBe(409);
    expect(taken.json().error.code).toBe('handle_taken');
    const reserved = await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(other.token), payload: card({ handle: 'yaqeen' }) });
    expect(reserved.json().error.code).toBe('handle_reserved');
    const avail = (await app.inject({ method: 'GET', url: '/v1/me/public-profile/available?handle=ahmed', headers: auth(other.token) })).json();
    expect(avail.available).toBe(false);

    const guest = await makeUser('Guest', true);
    const g = await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(guest.token), payload: card({ handle: 'guesty' }) });
    expect(g.json().error.code).toBe('account_required');
  });

  it('unpublish and erasure hide the card at once', async () => {
    const u = await makeUser('Sara');
    const token = u.token;
    await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(token), payload: card({ handle: 'sara' }) });
    expect((await app.inject({ method: 'GET', url: '/u/sara' })).statusCode).toBe(200);
    await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(token), payload: card({ handle: 'sara', published: false }) });
    expect((await app.inject({ method: 'GET', url: '/u/sara' })).statusCode).toBe(404);

    await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(token), payload: card({ handle: 'sara' }) });
    expect((await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(token) })).statusCode).toBe(202);
    const gone = await app.inject({ method: 'GET', url: '/u/sara' });
    expect(gone.statusCode).toBe(404);
    expect(gone.body).toContain('حمّل تطبيق يقين'); // still an invitation
  });

  it('support can hide an abusive card; the action is audited', async () => {
    const u = await makeUser('Rude');
    await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(u.token), payload: card({ handle: 'rude' }) });
    const [a] = await db.insert(s.adminUsers).values({ name: 'Sup', email: 'sup@example.com', role: 'support', passwordHash: 'x', totpSecret: 'x' }).returning();
    const admin = await signAdminToken({ sub: a!.id, role: 'support' }, env.ADMIN_JWT_SECRET);
    const detail = (await app.inject({ method: 'GET', url: `/admin/users/${u.id}`, headers: auth(admin) })).json();
    expect(detail.publicProfile).toMatchObject({ handle: 'rude', published: true, url: 'https://id.test/u/rude' });
    const res = await app.inject({ method: 'POST', url: `/admin/users/${u.id}/public-profile/unpublish`, headers: auth(admin), payload: { reason: 'abusive bio' } });
    expect(res.statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/u/rude' })).statusCode).toBe(404);
    const log = await db.select().from(s.auditLog).where(eq(s.auditLog.action, 'user.public_profile.unpublish'));
    expect(log).toHaveLength(1);
  });

  it('get-app sends each phone to its store', async () => {
    const android = await app.inject({ method: 'GET', url: '/get-app?ref=ahmed', headers: { 'user-agent': 'Mozilla/5.0 (Linux; Android 14)' } });
    expect(android.statusCode).toBe(302);
    expect(android.headers.location).toContain('play.google.com');
    const iphone = await app.inject({ method: 'GET', url: '/get-app', headers: { 'user-agent': 'Mozilla/5.0 (iPhone)' } });
    expect(iphone.headers.location).toBe(env.STORE_URL); // no App Store listing configured yet
    const icon = await app.inject({ method: 'GET', url: '/u/assets/icon.png' });
    expect(icon.headers['content-type']).toBe('image/png');
  });
});
