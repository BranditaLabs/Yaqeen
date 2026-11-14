/**
 * Shared setup for the community DB tests: a fresh schema (all migrations, incl. 0017), the app with
 * a movable clock, users/admins/ledger helpers and the job steps. Not a test file itself.
 */
import { fileURLToPath } from 'node:url';
import type { FastifyInstance, LightMyRequestResponse } from 'fastify';
import { sql } from 'drizzle-orm';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { vi } from 'vitest';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import type { ResponseCache } from '../src/lib/cache.js';
import { signAdminToken, signUserToken } from '../src/lib/tokens.js';
import { resetActivityCache } from '../src/services/activity.service.js';
import type { CommunityCtx } from '../src/services/community-settings.service.js';

export const TEST_DB_URL = process.env.TEST_DATABASE_URL;

// These files walk whole flows through the API against Postgres (a fresh schema per file); give
// them room on a slow CI runner instead of the 5 s unit-test default.
vi.setConfig({ testTimeout: 60_000, hookTimeout: 120_000 });

export interface Harness {
  app: FastifyInstance;
  db: Db;
  pool: pg.Pool;
  env: ReturnType<typeof loadEnv>;
  /** Set the clock (every service reads ctx.now()). */
  setNow: (d: Date | string) => void;
  now: () => Date;
  ctx: CommunityCtx;
  close: () => Promise<void>;
}

export async function setup(start: string): Promise<Harness> {
  const url = TEST_DB_URL!;
  const reset = new pg.Client({ connectionString: url });
  await reset.connect();
  await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
  await reset.end();
  const { db, pool } = createDb(url, { max: 20 });
  await migrate(db, { migrationsFolder: fileURLToPath(new URL('../drizzle', import.meta.url)) });
  resetActivityCache();
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url, PUBLIC_PROFILE_BASE_URL: 'https://id.test' });
  let clock = new Date(start);
  const now = () => clock;
  const app = await buildApp({
    env,
    db,
    redis: null,
    aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
    shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
    fcm: new FcmSender(''),
    now,
  });
  const ctx: CommunityCtx = { env, db, now, cache: app.ctx.cache as ResponseCache };
  return {
    app,
    db,
    pool,
    env,
    now,
    setNow: (d) => {
      clock = new Date(d);
    },
    ctx,
    close: async () => {
      await app.close();
      await pool.end();
    },
  };
}

export const auth = (t: string) => ({ authorization: `Bearer ${t}` });

let seq = 0;

export async function makeUser(h: Harness, name: string | null, opts: { guest?: boolean; country?: string; attested?: boolean } = {}) {
  const [u] = await h.db
    .insert(s.users)
    .values({ displayName: name, isGuest: opts.guest ?? false, country: opts.country ?? null, adultAttestedAt: opts.attested ? new Date('2026-01-01T00:00:00Z') : null })
    .returning();
  return { id: u!.id, token: await signUserToken({ sub: u!.id, guest: opts.guest ?? false }, h.env.JWT_SECRET) };
}

export async function makeAdmin(h: Harness, role: 'super_admin' | 'marketing' | 'support' | 'content_editor' | 'religious_reviewer') {
  const [a] = await h.db
    .insert(s.adminUsers)
    .values({ name: role, email: `${role}-${++seq}@example.com`, role, passwordHash: 'x', totpSecret: 'x' })
    .returning();
  return { id: a!.id, token: await signAdminToken({ sub: a!.id, role }, h.env.ADMIN_JWT_SECRET) };
}

/** A ledger row (the trigger keeps the rollups). */
export async function earn(h: Harness, userId: string, delta: number, at: string, reason: 'task' | 'qada' | 'bonus' | 'milestone' | 'grant' | 'admin_adjustment' | 'reversal' | 'redemption' = 'task') {
  await h.db.insert(s.pointsLedger).values({ userId, delta, reason, refKey: `t:${++seq}:${userId}`, createdAt: new Date(at) });
}

export async function setFlags(h: Harness, flags: Record<string, boolean>) {
  await h.db
    .insert(s.appConfig)
    .values({ key: 'features', value: flags })
    .onConflictDoUpdate({ target: s.appConfig.key, set: { value: flags } });
  await h.ctx.cache.bumpNamespace('config');
}

export async function ledgerCount(h: Harness): Promise<number> {
  const r = await h.db.execute<{ n: number }>(sql`select count(*)::int as n from points_ledger`);
  return Number(r.rows[0]!.n);
}

export async function consentEventsFor(h: Harness, userId: string) {
  const r = await h.db.execute<{ granted: boolean; source: string; attested_adult: boolean | null; policy_version: string }>(sql`
    select granted, source, attested_adult, policy_version from consent_events where user_id = ${userId} and kind = 'community' order by created_at, id`);
  return r.rows;
}

/** Opt a user into competitions through the API (attesting now). */
export async function optIn(h: Harness, token: string, body: Record<string, unknown>): Promise<LightMyRequestResponse> {
  return h.app.inject({ method: 'PUT', url: '/v1/me/community', headers: auth(token), payload: { attestAdult: true, ...body } });
}
