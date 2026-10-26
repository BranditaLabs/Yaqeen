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

  it('medal tags: minted in batches, activated once, follow the handle, switch off when lost', async () => {
    const [m] = await db.insert(s.adminUsers).values({ name: 'Mkt', email: 'mkt@example.com', role: 'marketing', passwordHash: 'x', totpSecret: 'x' }).returning();
    const [sp] = await db.insert(s.adminUsers).values({ name: 'Sup2', email: 'sup2@example.com', role: 'support', passwordHash: 'x', totpSecret: 'x' }).returning();
    const mkt = await signAdminToken({ sub: m!.id, role: 'marketing' }, env.ADMIN_JWT_SECRET);
    const sup = await signAdminToken({ sub: sp!.id, role: 'support' }, env.ADMIN_JWT_SECRET);

    // Mint: marketing only, unique batch names, a CSV for the manufacturer.
    expect((await app.inject({ method: 'POST', url: '/admin/tags/batches', headers: auth(sup), payload: { batch: 'b1', kind: 'medal', count: 3 } })).statusCode).toBe(403);
    const mint = await app.inject({ method: 'POST', url: '/admin/tags/batches', headers: auth(mkt), payload: { batch: 'b1', kind: 'medal', count: 3 } });
    expect(mint.statusCode).toBe(201);
    expect(mint.json()).toMatchObject({ batch: 'b1', count: 3 });
    expect((await app.inject({ method: 'POST', url: '/admin/tags/batches', headers: auth(mkt), payload: { batch: 'b1', kind: 'medal', count: 1 } })).statusCode).toBe(400);
    const csv = await app.inject({ method: 'GET', url: '/admin/tags/batches/b1.csv', headers: auth(sup) });
    expect(csv.headers['content-type']).toContain('text/csv');
    const lines = csv.body.trim().split('\n');
    expect(lines).toHaveLength(4);
    const [code, printed, url] = lines[1]!.split(',');
    expect(code).toMatch(/^[2-9A-HJ-NP-Z]{8}$/);
    expect(url).toBe(`https://id.test/t/${code}`);
    const other = lines[2]!.split(',')[0]!;

    // A blank tag explains how to activate it; an unknown code is the friendly 404.
    const blank = await app.inject({ method: 'GET', url: `/t/${code}` });
    expect(blank.statusCode).toBe(200);
    expect(blank.body).toContain(printed);
    expect(blank.body).toContain(`yaqeen://tag/${code}`);
    expect(blank.body).toContain('ميدالية يقين جديدة');
    expect((await app.inject({ method: 'GET', url: '/t/ZZZZZZZZ' })).statusCode).toBe(404);

    // Activation: not for guests; typed with a dash in lower case; idempotent; nobody else can take it.
    const guest = await makeUser('Guest', true);
    expect((await app.inject({ method: 'POST', url: '/v1/me/tags', headers: auth(guest.token), payload: { code } })).statusCode).toBe(403);
    const owner = await makeUser('Owner');
    const claim = await app.inject({ method: 'POST', url: '/v1/me/tags', headers: auth(owner.token), payload: { code: printed!.toLowerCase() } });
    expect(claim.statusCode).toBe(200);
    expect(claim.json()).toMatchObject({ code, kind: 'medal', url: `https://id.test/t/${code}`, scans: 0 });
    expect((await app.inject({ method: 'POST', url: '/v1/me/tags', headers: auth(owner.token), payload: { code } })).statusCode).toBe(200);
    const thief = await makeUser('Thief');
    expect((await app.inject({ method: 'POST', url: '/v1/me/tags', headers: auth(thief.token), payload: { code } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: '/v1/me/tags', headers: auth(owner.token), payload: { code: 'nope' } })).statusCode).toBe(400);

    // Linked but the card is unpublished → nothing public. Published → follows the handle, counts scans.
    expect((await app.inject({ method: 'GET', url: `/t/${code}` })).statusCode).toBe(404);
    await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(owner.token), payload: card({ handle: 'owner' }) });
    const hop = await app.inject({ method: 'GET', url: `/t/${code}`, headers: { 'user-agent': 'Mozilla/5.0 (iPhone)' } });
    expect(hop.statusCode).toBe(302);
    expect(hop.headers.location).toBe('https://id.test/u/owner');
    expect(hop.headers['cache-control']).toBe('no-store');
    await app.inject({ method: 'PUT', url: '/v1/me/public-profile', headers: auth(owner.token), payload: card({ handle: 'owner2' }) });
    expect((await app.inject({ method: 'GET', url: `/t/${code}` })).headers.location).toBe('https://id.test/u/owner2');
    const mine = (await app.inject({ method: 'GET', url: '/v1/me/tags', headers: auth(owner.token) })).json();
    expect(mine).toHaveLength(1);
    expect(mine[0].scans).toBe(2); // both opens above were people (no bot user-agent)

    // Admin list shows the handle, never worship.
    const list = (await app.inject({ method: 'GET', url: '/admin/tags?batch=b1&status=active', headers: auth(sup) })).json();
    expect(list.items).toEqual([expect.objectContaining({ code, status: 'active', handle: 'owner2' })]);
    const batches = (await app.inject({ method: 'GET', url: '/admin/tags/batches', headers: auth(mkt) })).json();
    expect(batches[0]).toMatchObject({ batch: 'b1', total: 3, active: 1, disabled: 0 });

    // Lost: the owner switches it off; it never resolves again or passes to a finder.
    expect((await app.inject({ method: 'DELETE', url: `/v1/me/tags/${code}`, headers: auth(owner.token) })).statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: `/t/${code}` })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: '/v1/me/tags', headers: auth(thief.token), payload: { code } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: '/v1/me/tags', headers: auth(owner.token) })).json()).toEqual([]);

    // Support re-issues a returned tag (audited); erasure switches off every tag of the user.
    expect((await app.inject({ method: 'POST', url: `/admin/tags/${code}/release`, headers: auth(sup), payload: { reason: 'returned to store' } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: `/t/${code}` })).statusCode).toBe(200);
    await app.inject({ method: 'POST', url: '/v1/me/tags', headers: auth(owner.token), payload: { code: other } });
    await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(owner.token) });
    expect((await app.inject({ method: 'GET', url: `/t/${other}` })).statusCode).toBe(404);
    const log = await db.select().from(s.auditLog).where(eq(s.auditLog.targetType, 'tag'));
    expect(log.map((l) => l.action)).toEqual(['tags.release']);
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
