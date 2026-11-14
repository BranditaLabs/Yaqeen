/**
 * Community HTTP guards that need no database: photo upload codes decided before any query
 * (415 photo_type, 413 photo_too_large, guests), the derived consent, sign-in requirements, admin
 * role guards on /admin/competitions and the embedded preset art.
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
const UID = '11111111-1111-4111-8111-111111111111';
let user: string;
let guest: string;

beforeAll(async () => {
  const { db } = createDb(env.DATABASE_URL);
  app = await buildApp({
    env,
    db,
    redis: null,
    aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
    shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
    fcm: new FcmSender(''),
    now: () => new Date('2026-11-11T08:00:00Z'),
  });
  user = await signUserToken({ sub: UID, guest: false }, env.JWT_SECRET);
  guest = await signUserToken({ sub: UID, guest: true }, env.JWT_SECRET);
});
afterAll(async () => app.close());

const auth = (t: string) => ({ authorization: `Bearer ${t}` });

describe('photo upload guards', () => {
  it('415 photo_type for other content types', async () => {
    const res = await app.inject({ method: 'PUT', url: '/v1/me/avatar/photo', headers: { ...auth(user), 'content-type': 'image/gif' }, payload: Buffer.from('GIF89a') });
    expect(res.statusCode).toBe(415);
    expect(res.json().error.code).toBe('photo_type');
  });

  it('413 photo_too_large over 3 MiB', async () => {
    const res = await app.inject({
      method: 'PUT',
      url: '/v1/me/avatar/photo',
      headers: { ...auth(user), 'content-type': 'image/jpeg' },
      payload: Buffer.alloc(3 * 1024 * 1024 + 10, 0xff),
    });
    expect(res.statusCode).toBe(413);
    expect(res.json().error.code).toBe('photo_too_large');
  });

  it('guests get account_required; no token → 401', async () => {
    const res = await app.inject({ method: 'PUT', url: '/v1/me/avatar/photo', headers: { ...auth(guest), 'content-type': 'image/jpeg' }, payload: Buffer.from([0xff, 0xd8, 0xff, 0]) });
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('account_required');
    expect((await app.inject({ method: 'PUT', url: '/v1/me/avatar/photo', headers: { 'content-type': 'image/jpeg' }, payload: Buffer.from([1]) })).statusCode).toBe(401);
  });

  it('the JSON body limit elsewhere is unchanged (raw parsers are encapsulated)', async () => {
    const res = await app.inject({ method: 'PATCH', url: '/v1/me/profile', headers: { ...auth(user), 'content-type': 'image/jpeg' }, payload: Buffer.from([0xff, 0xd8, 0xff]) });
    expect(res.statusCode).toBe(415);
  });
});

describe('community guards', () => {
  it('the community consent is never granted directly', async () => {
    const res = await app.inject({ method: 'PUT', url: '/v1/me/consents', headers: auth(user), payload: { kind: 'community', granted: true, source: 'settings' } });
    expect(res.statusCode).toBe(403);
    expect(res.json().error.code).toBe('use_community_settings');
  });

  it('guests cannot opt in, attest or edit their profile on the server', async () => {
    for (const [method, url, payload] of [
      ['PUT', '/v1/me/community', { leagues: true, attestAdult: true }],
      ['POST', '/v1/me/attestation', { attestAdult: true }],
      ['PATCH', '/v1/me/profile', { avatar: { kind: 'preset', id: 'm03' } }],
    ] as const) {
      const res = await app.inject({ method, url, headers: auth(guest), payload });
      expect(res.statusCode, url).toBe(403);
      expect(res.json().error.code, url).toBe('account_required');
    }
  });

  it('competition endpoints need a session', async () => {
    for (const url of ['/v1/leagues/current', '/v1/tournaments', '/v1/leaderboard', '/v1/community/blocks', '/v1/me/profile', '/v1/me/badges']) {
      expect((await app.inject({ method: 'GET', url })).statusCode, url).toBe(401);
    }
  });

  it('rejects an invalid display name before touching the database', async () => {
    const res = await app.inject({ method: 'PATCH', url: '/v1/me/profile', headers: auth(user), payload: { displayName: 'Omar‮Ali' } });
    expect(res.statusCode).toBe(400);
  });
});

describe('admin competitions guards', () => {
  it('content editors and reviewers get 403; marketing cannot moderate; support cannot create tournaments', async () => {
    const editor = await signAdminToken({ sub: UID, role: 'content_editor' }, env.ADMIN_JWT_SECRET);
    const reviewer = await signAdminToken({ sub: UID, role: 'religious_reviewer' }, env.ADMIN_JWT_SECRET);
    const marketing = await signAdminToken({ sub: UID, role: 'marketing' }, env.ADMIN_JWT_SECRET);
    const support = await signAdminToken({ sub: UID, role: 'support' }, env.ADMIN_JWT_SECRET);
    for (const t of [editor, reviewer]) {
      for (const url of ['/admin/competitions/tournaments', '/admin/competitions/competitors', '/admin/competitions/leagues/stats', '/admin/competitions/badges']) {
        const res = await app.inject({ method: 'GET', url, headers: auth(t) });
        expect(res.statusCode, url).toBe(403);
      }
    }
    const hide = await app.inject({ method: 'POST', url: `/admin/competitions/competitors/${UID}/hide-photo`, headers: auth(marketing), payload: { reason: 'abusive photo' } });
    expect(hide.statusCode).toBe(403);
    const photo = await app.inject({ method: 'GET', url: `/admin/competitions/competitors/${UID}/photos/${UID}/256`, headers: auth(marketing) });
    expect(photo.statusCode).toBe(403);
    const create = await app.inject({ method: 'POST', url: '/admin/competitions/tournaments', headers: auth(support), payload: {} });
    expect(create.statusCode).toBe(403);
    const rollover = await app.inject({ method: 'POST', url: '/admin/competitions/leagues/rollover', headers: auth(marketing), payload: { reason: 'now please' } });
    expect(rollover.statusCode).toBe(403);
    const settings = await app.inject({ method: 'PUT', url: '/admin/competitions/leagues/settings', headers: auth(support), payload: { groupSize: 30, promote: 5, demote: 5 } });
    expect(settings.statusCode).toBe(403);
    expect((await app.inject({ method: 'GET', url: '/admin/competitions/tournaments' })).statusCode).toBe(401);
  });
});

describe('preset art and public photo route', () => {
  it('serves a preset as immutable WebP; unknown ids 404', async () => {
    const res = await app.inject({ method: 'GET', url: '/u/assets/avatars/m03.webp' });
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toBe('image/webp');
    expect(res.headers['cache-control']).toContain('immutable');
    expect(res.rawPayload.subarray(8, 12).toString('latin1')).toBe('WEBP');
    expect((await app.inject({ method: 'GET', url: '/u/assets/avatars/x99.webp' })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: '/u/assets/avatars/m03.png' })).statusCode).toBe(404);
  });

  it('a malformed public photo URL is a 404 without a query', async () => {
    expect((await app.inject({ method: 'GET', url: '/v1/public/avatars/not-a-uuid/256.webp' })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: `/v1/public/avatars/${UID}/512.webp` })).statusCode).toBe(404);
  });
});
