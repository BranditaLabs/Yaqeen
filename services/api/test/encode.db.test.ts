/**
 * Staff NFC encoding against Postgres: marketing opens a short-lived session for a batch (audited,
 * token hashed at rest); the phone reads the batch's working codes and reports each chip written.
 * Skipped without TEST_DATABASE_URL — see integration.db.test.ts.
 */
import { fileURLToPath } from 'node:url';
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
import { signAdminToken } from '../src/lib/tokens.js';
import { hashEncodeToken } from '../src/services/tag-encoding.service.js';

const url = process.env.TEST_DATABASE_URL;
let now = new Date('2026-11-01T08:00:00Z');

describe.skipIf(!url)('staff NFC encoding (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip', PUBLIC_PROFILE_BASE_URL: 'https://id.test/' });
  const auth = (t: string) => ({ authorization: `Bearer ${t}` });
  let mkt = '';
  let sup = '';

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
      now: () => now,
    });
    const [m] = await db.insert(s.adminUsers).values({ name: 'Mkt', email: 'mkt@example.com', role: 'marketing', passwordHash: 'x', totpSecret: 'x' }).returning();
    const [sp] = await db.insert(s.adminUsers).values({ name: 'Sup', email: 'sup@example.com', role: 'support', passwordHash: 'x', totpSecret: 'x' }).returning();
    mkt = await signAdminToken({ sub: m!.id, role: 'marketing' }, env.ADMIN_JWT_SECRET);
    sup = await signAdminToken({ sub: sp!.id, role: 'support' }, env.ADMIN_JWT_SECRET);
    for (const batch of ['e1', 'e2']) {
      expect((await app.inject({ method: 'POST', url: '/admin/tags/batches', headers: auth(mkt), payload: { batch, kind: 'medal', count: 3 } })).statusCode).toBe(201);
    }
  });

  afterAll(async () => {
    await app?.close();
    await pool?.end();
  });

  const codesOf = async (batch: string) =>
    (await db.select({ code: s.profileTags.code }).from(s.profileTags).where(eq(s.profileTags.batch, batch)).orderBy(s.profileTags.code)).map((r) => r.code);
  const open = (batch: string, token = mkt) => app.inject({ method: 'POST', url: `/admin/tags/batches/${batch}/encode-sessions`, headers: auth(token) });

  it('marketing opens a session (audited, token hashed at rest); support cannot', async () => {
    expect((await open('e1', sup)).statusCode).toBe(403);
    expect((await open('nope')).statusCode).toBe(404);
    const res = await open('e1');
    expect(res.statusCode).toBe(201);
    expect(res.headers['cache-control']).toBe('no-store');
    const body = res.json();
    expect(body.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(body.url).toBe(`yaqeen://encode/${body.token}`);
    expect(new Date(body.expiresAt).getTime() - now.getTime()).toBe(2 * 3600 * 1000);
    expect(body.active).toBe(true);

    const [row] = await db.select().from(s.tagEncodeSessions).where(eq(s.tagEncodeSessions.id, body.id));
    expect(row!.tokenHash).toBe(hashEncodeToken(body.token));
    expect(row!.tokenHash).not.toContain(body.token);
    const log = await db.select().from(s.auditLog).where(eq(s.auditLog.action, 'tags.encode_session.create'));
    expect(log).toHaveLength(1);
    expect(log[0]!.targetId).toBe('e1');
    expect(JSON.stringify(log[0])).not.toContain(body.token);
    expect(JSON.stringify(log[0])).not.toContain(row!.tokenHash);

    const list = (await app.inject({ method: 'GET', url: '/admin/tags/batches/e1/encode-sessions', headers: auth(mkt) })).json();
    expect(list).toHaveLength(1);
    expect(list[0]).not.toHaveProperty('token');
  });

  it('the phone sees only its batch, without switched-off codes, and records writes idempotently', async () => {
    const { token } = (await open('e1')).json();
    const e1 = await codesOf('e1');
    const e2 = await codesOf('e2');
    await db.update(s.profileTags).set({ disabledAt: now }).where(eq(s.profileTags.code, e1[2]!));

    const view = await app.inject({ method: 'GET', url: `/v1/encode/${token}` });
    expect(view.statusCode).toBe(200);
    expect(view.headers['cache-control']).toBe('no-store');
    expect(view.json()).toMatchObject({ batch: 'e1', kind: 'medal', baseUrl: 'https://id.test' });
    expect(view.json().codes).toEqual([
      { code: e1[0], encodedAt: null },
      { code: e1[1], encodedAt: null },
    ]);

    const write = (payload: Record<string, unknown>) => app.inject({ method: 'POST', url: `/v1/encode/${token}/written`, payload });
    const first = await write({ code: e1[0], uid: '04a1b2c3d4e5f6', locked: false });
    expect(first.statusCode).toBe(200);
    expect(first.json()).toMatchObject({ code: e1[0], encoded: 1, total: 2 });
    const again = await write({ code: e1[0], uid: '04a1b2c3d4e5f6', locked: false });
    expect(again.json()).toMatchObject({ code: e1[0], encoded: 1, total: 2 });
    const [tag] = await db.select().from(s.profileTags).where(eq(s.profileTags.code, e1[0]!));
    expect(tag).toMatchObject({ encodedUid: '04A1B2C3D4E5F6', encodedLocked: false });
    expect(tag!.encodedAt).toEqual(now);
    expect((await write({ code: e1[1], locked: true })).json()).toMatchObject({ encoded: 2, total: 2 });

    // Another batch's code, a switched-off one, and nonsense are all refused.
    expect((await write({ code: e2[0], locked: false })).json().error.code).toBe('code_not_in_batch');
    expect((await write({ code: e1[2], locked: false })).json().error.code).toBe('code_not_in_batch');
    expect((await write({ code: 'nope', locked: false })).statusCode).toBe(400);
    expect((await write({ code: e1[0], uid: 'zz', locked: false })).statusCode).toBe(400);
    expect((await db.select().from(s.profileTags).where(eq(s.profileTags.code, e2[0]!)))[0]!.encodedAt).toBeNull();

    const after = (await app.inject({ method: 'GET', url: `/v1/encode/${token}` })).json();
    expect(after.codes.every((c: { encodedAt: string | null }) => c.encodedAt)).toBe(true);
  });

  it('unknown, malformed, revoked, expired and voided-batch sessions all answer the same 404', async () => {
    const shape = async (token: string) => {
      const get = await app.inject({ method: 'GET', url: `/v1/encode/${token}` });
      const post = await app.inject({ method: 'POST', url: `/v1/encode/${token}/written`, payload: { junk: true } });
      return [get.statusCode, get.body, post.statusCode, post.body];
    };
    const unknown = await shape('A'.repeat(43));
    expect(unknown[0]).toBe(404);
    expect(unknown[2]).toBe(404);
    expect(await shape('short')).toEqual(unknown);

    const revoked = (await open('e2')).json();
    expect((await app.inject({ method: 'DELETE', url: `/admin/tags/batches/e2/encode-sessions/${revoked.id}`, headers: auth(sup) })).statusCode).toBe(403);
    expect((await app.inject({ method: 'DELETE', url: `/admin/tags/batches/e2/encode-sessions/${revoked.id}`, headers: auth(mkt) })).statusCode).toBe(204);
    expect((await app.inject({ method: 'DELETE', url: `/admin/tags/batches/e2/encode-sessions/${revoked.id}`, headers: auth(mkt) })).statusCode).toBe(404);
    expect(await shape(revoked.token)).toEqual(unknown);
    expect((await db.select().from(s.auditLog).where(eq(s.auditLog.action, 'tags.encode_session.revoke')))).toHaveLength(1);

    const expiring = (await open('e2')).json();
    expect((await app.inject({ method: 'GET', url: `/v1/encode/${expiring.token}` })).statusCode).toBe(200);
    const saved = now;
    now = new Date(saved.getTime() + 2 * 3600 * 1000 + 1);
    expect(await shape(expiring.token)).toEqual(unknown);
    const sessions = (await app.inject({ method: 'GET', url: '/admin/tags/batches/e2/encode-sessions', headers: auth(mkt) })).json();
    expect(sessions.every((x: { active: boolean }) => !x.active)).toBe(true);
    now = saved;

    const live = (await open('e2')).json();
    expect((await app.inject({ method: 'POST', url: '/admin/tags/batches/e2/void', headers: auth(mkt), payload: { reason: 'chips fail' } })).statusCode).toBe(200);
    expect(await shape(live.token)).toEqual(unknown);
    expect((await open('e2')).json().error.code).toBe('batch_void');
  });

  it('admin shows encoded counts per batch and the state per tag', async () => {
    const batches = (await app.inject({ method: 'GET', url: '/admin/tags/batches', headers: auth(sup) })).json();
    expect(batches.find((b: { batch: string }) => b.batch === 'e1')).toMatchObject({ total: 3, encoded: 2, disabled: 1 });
    expect(batches.find((b: { batch: string }) => b.batch === 'e2')).toMatchObject({ encoded: 0 });
    const rows = (await app.inject({ method: 'GET', url: '/admin/tags?batch=e1', headers: auth(sup) })).json().items;
    expect(rows.filter((r: { encodedAt: string | null }) => r.encodedAt)).toHaveLength(2);
    expect(rows.filter((r: { encodedLocked: boolean }) => r.encodedLocked)).toHaveLength(1);
  });
});
