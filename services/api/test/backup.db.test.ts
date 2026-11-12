/**
 * Opt-in cloud backup against Postgres: consent gate, guests refused, closed list of kinds, size
 * cap, optimistic concurrency (409 with the current document), sealed at rest, withdraw deletes,
 * erasure purge deletes, the user's export includes it and the admin export never does.
 */
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { eq } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { BACKUP_MAX_BYTES } from '@yaqeen/contracts';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { purgeDeleted } from '../src/jobs/purge-deleted.js';
import { isSealed } from '../src/lib/crypto.js';
import { signAdminToken, signUserToken } from '../src/lib/tokens.js';

const url = process.env.TEST_DATABASE_URL;
const NOW = new Date('2026-10-20T08:00:00Z');
const SECRET_NOTE = 'my private note on al-Baqarah 255';

describe.skipIf(!url)('cloud backup (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  const env = loadEnv({
    NODE_ENV: 'test',
    DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip',
    BACKUP_SECRETS_KEY: randomBytes(32).toString('base64'),
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

  async function user({ guest = false, consent = true } = {}) {
    const [u] = await db.insert(s.users).values({ displayName: 'A', isGuest: guest }).returning();
    const token = await signUserToken({ sub: u!.id, guest }, env.JWT_SECRET);
    if (consent) {
      const r = await app.inject({
        method: 'PUT',
        url: '/v1/me/consents',
        headers: auth(token),
        payload: { kind: 'cloud_backup', granted: true, source: 'settings' },
      });
      expect(r.statusCode).toBe(200);
    }
    return { id: u!.id, token };
  }
  const put = (token: string, kind: string, baseVersion: number, data: unknown) =>
    app.inject({ method: 'PUT', url: `/v1/me/backup/${kind}`, headers: auth(token), payload: { baseVersion, data } });

  it('refuses without the consent and refuses guests outright', async () => {
    const off = await user({ consent: false });
    const r0 = await app.inject({ method: 'GET', url: '/v1/me/backup', headers: auth(off.token) });
    expect(r0.statusCode).toBe(403);
    expect(r0.json().error.code).toBe('backup_off');
    expect((await put(off.token, 'tasbeeh', 0, { count: 1 })).json().error.code).toBe('backup_off');

    const guest = await user({ guest: true, consent: false });
    const g = await app.inject({
      method: 'PUT',
      url: '/v1/me/consents',
      headers: auth(guest.token),
      payload: { kind: 'cloud_backup', granted: true, source: 'settings' },
    });
    expect(g.statusCode).toBe(403);
    expect(g.json().error.code).toBe('account_required');
    // Even with a consent row forced in, a guest gets nothing.
    await db.insert(s.consents).values({ userId: guest.id, kind: 'cloud_backup', granted: true });
    const r1 = await app.inject({ method: 'GET', url: '/v1/me/backup', headers: auth(guest.token) });
    expect(r1.statusCode).toBe(403);
    expect(r1.json().error.code).toBe('account_required');
  });

  it('writes, versions and reads back; a stale base version is a 409 carrying the current document', async () => {
    const u = await user();
    const empty = await app.inject({ method: 'GET', url: '/v1/me/backup', headers: auth(u.token) });
    expect(empty.json()).toEqual({ kinds: [] });
    expect((await app.inject({ method: 'GET', url: '/v1/me/backup/quran_notes', headers: auth(u.token) })).statusCode).toBe(404);

    const w1 = await put(u.token, 'quran_notes', 0, { notes: [{ s: 2, a: 255, t: SECRET_NOTE }] });
    expect(w1.statusCode).toBe(200);
    expect(w1.json().version).toBe(1);
    const w2 = await put(u.token, 'quran_notes', 1, { notes: [{ s: 2, a: 255, t: SECRET_NOTE }, { s: 1, a: 1, t: 'x' }] });
    expect(w2.json().version).toBe(2);

    // Another phone still on version 1.
    const stale = await put(u.token, 'quran_notes', 1, { notes: [] });
    expect(stale.statusCode).toBe(409);
    expect(stale.json().error.code).toBe('backup_conflict');
    expect(stale.json().error.details.version).toBe(2);
    expect(stale.json().error.details.data.notes).toHaveLength(2);
    // A first write when one already exists conflicts too.
    expect((await put(u.token, 'quran_notes', 0, { notes: [] })).statusCode).toBe(409);

    const m = await app.inject({ method: 'GET', url: '/v1/me/backup', headers: auth(u.token) });
    expect(m.json().kinds).toEqual([{ kind: 'quran_notes', version: 2, updatedAt: NOW.toISOString() }]);
    const doc = await app.inject({ method: 'GET', url: '/v1/me/backup/quran_notes', headers: auth(u.token) });
    expect(doc.json()).toMatchObject({ kind: 'quran_notes', version: 2, data: { notes: [{ t: SECRET_NOTE }, { t: 'x' }] } });
  });

  it('stores the document sealed — the raw column never holds the plaintext', async () => {
    const u = await user();
    await put(u.token, 'quran_notes', 0, { notes: [{ s: 2, a: 255, t: SECRET_NOTE }] });
    const [row] = await db.select().from(s.userBackups).where(eq(s.userBackups.userId, u.id));
    expect(isSealed(row!.blob)).toBe(true);
    expect(row!.blob).not.toContain(SECRET_NOTE);
    expect(row!.blob).not.toContain('notes');
    const raw = await pool.query('select blob from user_backups where user_id = $1', [u.id]);
    expect(String(raw.rows[0].blob)).not.toContain('al-Baqarah');
  });

  it('refuses unknown kinds, bad bodies and documents over the size cap', async () => {
    const u = await user();
    expect((await put(u.token, 'consents', 0, { a: 1 })).statusCode).toBe(400);
    expect((await put(u.token, 'tasbeeh', -1, { count: 1 })).statusCode).toBe(400);
    expect((await put(u.token, 'tasbeeh', 0, [1, 2])).statusCode).toBe(400);
    const big = await put(u.token, 'quran_notes', 0, { notes: 'x'.repeat(BACKUP_MAX_BYTES + 10) });
    expect(big.statusCode).toBe(413);
    expect(big.json().error.code).toBe('backup_too_large');
    expect(await db.select().from(s.userBackups).where(eq(s.userBackups.userId, u.id))).toHaveLength(0);
  });

  it('withdrawing the consent deletes the server copy (and keeps the consent record)', async () => {
    const u = await user();
    await put(u.token, 'tasbeeh', 0, { count: 33 });
    await put(u.token, 'routine', 0, { quranSlot: { k: 'off' } });
    expect(await db.select().from(s.userBackups).where(eq(s.userBackups.userId, u.id))).toHaveLength(2);
    const off = await app.inject({
      method: 'PUT',
      url: '/v1/me/consents',
      headers: auth(u.token),
      payload: { kind: 'cloud_backup', granted: false, source: 'settings' },
    });
    expect(off.statusCode).toBe(200);
    expect(await db.select().from(s.userBackups).where(eq(s.userBackups.userId, u.id))).toHaveLength(0);
    const events = await db.select().from(s.consentEvents).where(eq(s.consentEvents.userId, u.id));
    expect(events.map((e) => e.granted)).toEqual([true, false]);
    expect((await put(u.token, 'tasbeeh', 0, { count: 1 })).json().error.code).toBe('backup_off');
  });

  it('the user export includes the opened backup; the admin export never does', async () => {
    const u = await user();
    await put(u.token, 'quran_notes', 0, { notes: [{ s: 2, a: 255, t: SECRET_NOTE }] });
    const mine = await app.inject({ method: 'GET', url: '/v1/me/export', headers: auth(u.token) });
    expect(mine.json().backups).toEqual([expect.objectContaining({ kind: 'quran_notes', version: 1, data: { notes: [{ s: 2, a: 255, t: SECRET_NOTE }] } })]);

    const [a] = await db.insert(s.adminUsers).values({ name: 'sup', email: 'sup@x.com', role: 'support', passwordHash: 'x', totpSecret: 'x' }).returning();
    const admin = await signAdminToken({ sub: a!.id, role: 'support' }, env.ADMIN_JWT_SECRET);
    for (const path of [`/admin/users/${u.id}/export`, `/admin/users/${u.id}`]) {
      const r = await app.inject({ method: 'GET', url: path, headers: auth(admin) });
      expect(r.statusCode).toBe(200);
      expect(r.body).not.toContain(SECRET_NOTE);
      expect(r.body).not.toContain('quran_notes');
      expect(r.json().backups).toBeUndefined();
    }
  });

  it('erasure purge deletes the backup of a tombstoned account', async () => {
    const u = await user();
    await put(u.token, 'hifz', 0, { plan: { goal: 'juz30' } });
    const del = await app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(u.token) });
    expect(del.statusCode).toBe(202);
    expect(await db.select().from(s.userBackups).where(eq(s.userBackups.userId, u.id))).toHaveLength(1);
    expect(await purgeDeleted(db, new Date(NOW.getTime() + 31 * 86_400_000))).toBeGreaterThanOrEqual(1);
    expect(await db.select().from(s.userBackups).where(eq(s.userBackups.userId, u.id))).toHaveLength(0);
    const [tomb] = await db.select().from(s.users).where(eq(s.users.id, u.id));
    expect(tomb!.status).toBe('deleted');
  });
});
