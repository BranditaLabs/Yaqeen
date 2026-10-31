/**
 * Observability must not leak personal or worship data: Sentry events are scrubbed and metrics
 * are labelled with route templates only.
 */
import { describe, expect, it } from 'vitest';
import type { ErrorEvent } from '@sentry/node';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb } from '../src/db/client.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { ShopifyClient } from '../src/integrations/shopify.js';
import { registry } from '../src/lib/metrics.js';
import { scrubEvent } from '../src/lib/observability.js';

describe('sentry scrubbing', () => {
  it('drops user, body, cookies, query and private headers; reduces the URL to the route', () => {
    const event = {
      type: undefined,
      user: { id: 'u1', email: 'a@b.c', ip_address: '1.2.3.4' },
      tags: { route: '/u/:handle' },
      request: {
        url: 'https://api.test/u/ahmed?ref=x',
        data: { idToken: 'secret', task: 'five_prayers' },
        cookies: { yq_admin: 'tok' },
        query_string: 'ref=x',
        headers: { authorization: 'Bearer t', 'user-agent': 'UA', 'x-request-id': 'r1', cookie: 'c' },
      },
      breadcrumbs: [{ category: 'console', message: 'secret' }, { category: 'http', data: { url: '/v1/me?x=1' } }],
    } as unknown as ErrorEvent;
    const out = scrubEvent(event);
    expect(out.user).toBeUndefined();
    expect(out.request?.data).toBeUndefined();
    expect(out.request?.cookies).toBeUndefined();
    expect(out.request?.query_string).toBeUndefined();
    expect(out.request?.headers).toEqual({ 'user-agent': 'UA', 'x-request-id': 'r1' });
    expect(out.request?.url).toBe('https://api.test/u/:handle');
    expect(out.breadcrumbs).toEqual([{ category: 'http', data: undefined }]);
  });
});

describe('metrics', () => {
  it('label requests by route template, never the raw path', async () => {
    const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: 'postgres://skip@localhost:5432/skip' });
    const { db, pool } = createDb(env.DATABASE_URL);
    const app = await buildApp({
      env,
      db,
      redis: null,
      aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
      fcm: new FcmSender(''),
      now: () => new Date(),
    });
    await app.inject({ method: 'GET', url: '/health' });
    await app.inject({ method: 'GET', url: '/go/store?src=card&ref=ahmed.secret' });
    const text = await registry.metrics();
    expect(text).toMatch(/yaqeen_http_request_duration_seconds_count\{[^}]*route="\/health"[^}]*status="200"/);
    expect(text).toContain('route="/go/store"');
    expect(text).not.toContain('ahmed.secret');
    await app.close();
    await pool.end();
  });
});
