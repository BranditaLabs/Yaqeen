/**
 * HTTP-level tests that need no database: health, auth guards, admin RBAC, validation.
 * (DB-backed integration tests run in CI against the Postgres service — see test/README.md.)
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb } from '../src/db/client.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { signAdminToken, signUserToken } from '../src/lib/tokens.js';

let app: FastifyInstance;
const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: 'postgres://nobody:nothing@127.0.0.1:1/none' });

beforeAll(async () => {
  const { db } = createDb(env.DATABASE_URL); // pool connects lazily; these tests never query
  app = await buildApp({
    env,
    db,
    redis: null,
    aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
    shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
    fcm: new FcmSender(''),
    now: () => new Date('2026-10-20T08:00:00Z'),
  });
});
afterAll(async () => app.close());

describe('http', () => {
  it('GET /health', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true });
  });

  it('rejects /v1/me without a token', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/me' });
    expect(res.statusCode).toBe(401);
    expect(res.json().error.code).toBe('unauthorized');
  });

  it('an app token cannot reach the admin API', async () => {
    const token = await signUserToken({ sub: '00000000-0000-4000-8000-000000000001', guest: false }, env.JWT_SECRET);
    const res = await app.inject({ method: 'GET', url: '/admin/overview', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(401);
  });

  it('RBAC: marketing cannot change the points program', async () => {
    const token = await signAdminToken({ sub: '00000000-0000-4000-8000-000000000002', role: 'marketing' }, env.ADMIN_JWT_SECRET);
    const res = await app.inject({
      method: 'PUT',
      url: '/admin/rewards/program',
      headers: { authorization: `Bearer ${token}` },
      payload: {},
    });
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('role_not_allowed');
  });

  it('RBAC: support cannot review content', async () => {
    const token = await signAdminToken({ sub: '00000000-0000-4000-8000-000000000003', role: 'support' }, env.ADMIN_JWT_SECRET);
    const res = await app.inject({
      method: 'POST',
      url: '/admin/content/00000000-0000-4000-8000-000000000009/review',
      headers: { authorization: `Bearer ${token}` },
      payload: { decision: 'approve' },
    });
    expect(res.statusCode).toBe(403);
  });

  it('super_admin passes RBAC and hits validation (active task points must equal the daily total)', async () => {
    const token = await signAdminToken({ sub: '00000000-0000-4000-8000-000000000004', role: 'super_admin' }, env.ADMIN_JWT_SECRET);
    const tasks = ['wird', 'morning_azkar', 'five_prayers', 'evening_azkar', 'listen', 'daily_task'].map((key) => ({
      key,
      labelAr: 'مهمة',
      labelEn: 'Task',
      points: 10,
      active: true,
    }));
    const payload = { settings: { dailyTotal: 100, qadaDayPoints: 80, qadaWindowDays: 7, challengeLengthDays: 365 }, tasks };
    const res = await app.inject({
      method: 'PUT',
      url: '/admin/rewards/program',
      headers: { authorization: `Bearer ${token}` },
      payload,
    });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('invalid_total');
  });

  it('validates sign-in payloads', async () => {
    const res = await app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'facebook' } });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('validation_failed');
  });

  it('google sign-in without an id token is rejected before any network call', async () => {
    const res = await app.inject({ method: 'POST', url: '/v1/auth/sign-in', payload: { provider: 'google' } });
    expect(res.statusCode).toBe(400);
    expect(res.json().error.code).toBe('id_token_required');
  });
});
