/**
 * Quran Foundation integration without a database: OAuth token flow, refresh on 401, retries,
 * response mapping (timings, tafsir HTML → text) and the tafsir routes (cache headers, 503, 404).
 * Reciter routes need the `reciters` table — see quran-content.db.test.ts.
 * A live smoke test against the real public API runs only with QF_LIVE=1.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb } from '../src/db/client.js';
import { AYAH_COUNTS, parseAyahKey, tafsirPlainText, timingsFromQf } from '../src/domain/quran-content.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { QF_HOSTS, QfNotFound, QfUnavailable, QuranFoundationClient } from '../src/integrations/quran-foundation.js';
import { ShopifyClient } from '../src/integrations/shopify.js';

type Call = { url: string; init: RequestInit };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

/** fetch double: answers from `handler`, records every call. */
function fakeFetch(handler: (url: string, init: RequestInit, n: number) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const impl = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const url = String(input);
    calls.push({ url, init });
    return handler(url, init, calls.length);
  }) as typeof fetch;
  return { impl, calls };
}

const header = (c: Call, k: string) => (c.init.headers as Record<string, string> | undefined)?.[k];

describe('QuranFoundationClient', () => {
  it('public mode: legacy base, no auth headers', async () => {
    const f = fakeFetch(() => json({ ok: 1 }));
    const qf = new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: 'https://legacy.test/api/v4/', fetchImpl: f.impl });
    expect(qf.mode).toBe('public');
    expect(await qf.get('/chapter_recitations/7/1', { segments: true })).toEqual({ ok: 1 });
    expect(f.calls[0]!.url).toBe('https://legacy.test/api/v4/chapter_recitations/7/1?segments=true');
    expect(header(f.calls[0]!, 'x-auth-token')).toBeUndefined();
  });

  it('off mode (no credentials, no fallback) fails cleanly without a request', async () => {
    const f = fakeFetch(() => json({}));
    const qf = new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: '', fetchImpl: f.impl });
    expect(qf.mode).toBe('off');
    await expect(qf.get('/x')).rejects.toBeInstanceOf(QfUnavailable);
    expect(f.calls).toHaveLength(0);
  });

  it('oauth: client_credentials token (basic auth, scope=content), cached, sent as x-auth-token + x-client-id', async () => {
    let t = 1_000_000;
    const f = fakeFetch((url) => (url.endsWith('/oauth2/token') ? json({ access_token: 'tok-1', expires_in: 3600, token_type: 'bearer' }) : json({ ok: 1 })));
    const qf = new QuranFoundationClient({ clientId: 'cid', clientSecret: 'sec', env: 'prelive', publicBaseUrl: 'https://legacy.test', fetchImpl: f.impl, now: () => t });
    expect(qf.mode).toBe('oauth');
    await qf.get('/chapters');
    await qf.get('/chapters');
    const token = f.calls.filter((c) => c.url.endsWith('/oauth2/token'));
    expect(token).toHaveLength(1);
    expect(token[0]!.url).toBe(`${QF_HOSTS.prelive.auth}/oauth2/token`);
    expect(header(token[0]!, 'authorization')).toBe(`Basic ${Buffer.from('cid:sec').toString('base64')}`);
    expect(token[0]!.init.body).toBe('grant_type=client_credentials&scope=content');
    const api = f.calls.filter((c) => !c.url.endsWith('/oauth2/token'));
    expect(api[0]!.url).toBe(`${QF_HOSTS.prelive.api}/chapters`);
    expect(header(api[0]!, 'x-auth-token')).toBe('tok-1');
    expect(header(api[0]!, 'x-client-id')).toBe('cid');
    // Near expiry → a new token.
    t += 3600_000;
    await qf.get('/chapters');
    expect(f.calls.filter((c) => c.url.endsWith('/oauth2/token'))).toHaveLength(2);
  });

  it('oauth: a 401 drops the token, re-requests it once and retries once', async () => {
    let tokens = 0;
    let apiCalls = 0;
    const f = fakeFetch((url) => {
      if (url.endsWith('/oauth2/token')) return json({ access_token: `tok-${++tokens}`, expires_in: 3600 });
      apiCalls++;
      return apiCalls === 1 ? json({ message: 'expired' }, 401) : json({ ok: 2 });
    });
    const qf = new QuranFoundationClient({ clientId: 'cid', clientSecret: 'sec', env: 'production', publicBaseUrl: '', fetchImpl: f.impl });
    expect(await qf.get('/chapters')).toEqual({ ok: 2 });
    expect(tokens).toBe(2);
    expect(header(f.calls.at(-1)!, 'x-auth-token')).toBe('tok-2');
  });

  it('oauth: a second 401 is not looped', async () => {
    const f = fakeFetch((url) => (url.endsWith('/oauth2/token') ? json({ access_token: 't', expires_in: 3600 }) : json({}, 401)));
    const qf = new QuranFoundationClient({ clientId: 'cid', clientSecret: 'sec', env: 'production', publicBaseUrl: '', fetchImpl: f.impl });
    await expect(qf.get('/chapters')).rejects.toBeInstanceOf(QfUnavailable);
    expect(f.calls.filter((c) => !c.url.endsWith('/oauth2/token')).length).toBeLessThanOrEqual(2);
  });

  it('retries once on 5xx / network, then gives up; 404 → QfNotFound; 4xx not retried', async () => {
    const flaky = fakeFetch((_u, _i, n) => (n === 1 ? json({}, 502) : json({ ok: 3 })));
    const a = new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: 'https://l.test', fetchImpl: flaky.impl });
    expect(await a.get('/x')).toEqual({ ok: 3 });

    const down = fakeFetch(() => {
      throw new TypeError('fetch failed');
    });
    const b = new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: 'https://l.test', fetchImpl: down.impl });
    await expect(b.get('/x')).rejects.toBeInstanceOf(QfUnavailable);
    expect(down.calls).toHaveLength(2);

    const missing = fakeFetch(() => json({}, 404));
    const c = new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: 'https://l.test', fetchImpl: missing.impl });
    await expect(c.get('/x')).rejects.toBeInstanceOf(QfNotFound);

    const bad = fakeFetch(() => json({}, 422));
    const d = new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: 'https://l.test', fetchImpl: bad.impl });
    await expect(d.get('/x')).rejects.toBeInstanceOf(QfUnavailable);
    expect(bad.calls).toHaveLength(1);
  });

  it('a failed token request is unavailable, and the secret never appears in the error', async () => {
    const f = fakeFetch(() => json({ error: 'invalid_client' }, 401));
    const qf = new QuranFoundationClient({ clientId: 'cid', clientSecret: 'super-secret', env: 'production', publicBaseUrl: '', fetchImpl: f.impl });
    const err: Error = await qf.get('/chapters').then(
      () => new Error('resolved'),
      (e: unknown) => e as Error,
    );
    expect(err).toBeInstanceOf(QfUnavailable);
    expect(err.message).not.toContain('super-secret');
  });
});

describe('Quran content mapping', () => {
  it('ayah counts cover the whole mushaf', () => {
    expect(AYAH_COUNTS).toHaveLength(114);
    expect(AYAH_COUNTS.reduce((a, b) => a + b, 0)).toBe(6236);
    expect(parseAyahKey('2:286')).toEqual([2, 286]);
    expect(parseAyahKey('2:287')).toBeNull();
    expect(parseAyahKey('115:1')).toBeNull();
    expect(parseAyahKey('1:1;drop')).toBeNull();
  });

  it('timings: ordered by ayah, deduplicated, negative legacy spans clamped', () => {
    expect(
      timingsFromQf([
        { verse_key: '1:2', timestamp_from: 6090, timestamp_to: 11680 },
        { verse_key: '1:1', timestamp_from: 0, timestamp_to: 6090 },
        { verse_key: '1:2', timestamp_from: 1, timestamp_to: 2 },
        { verse_key: '1:3', timestamp_from: 11680, timestamp_to: 11000 },
      ]),
    ).toEqual([
      [0, 6090],
      [6090, 11680],
      [11680, 11680],
    ]);
    expect(timingsFromQf(undefined)).toBeNull();
    expect(timingsFromQf([])).toBeNull();
  });

  it('tafsir HTML → plain text: tags and footnotes gone, entities decoded, words unchanged', () => {
    const html =
      '<h2>Meaning</h2><p lang="ar" class="ar ">قال ابن عباس : <span class="arabic qpc-hafs">( الم )</span> أي<sup foot_note="12">1</sup> &quot;x&quot; &amp; y&#39;s&nbsp;z</p><p>second<br/>line</p><script>alert(1)</script>';
    expect(tafsirPlainText(html)).toBe('Meaning\n\nقال ابن عباس : ( الم ) أي "x" & y\'s z\n\nsecond\nline');
    expect(tafsirPlainText('')).toBe('');
    expect(tafsirPlainText('a &lt;b&gt; &#x41;')).toBe('a <b> A');
  });
});

describe('tafsir routes', () => {
  let app: FastifyInstance;
  let mode: 'ok' | 'down' = 'ok';
  const upstream = fakeFetch((url) => {
    if (mode === 'down') return json({}, 503);
    if (url.includes('/tafsirs/16/by_chapter/1')) {
      return json({
        tafsirs: [
          { verse_key: '1:1', text: 'أبتدئ <span class="green">(اللهِ)</span> نص<sup foot_note="1">1</sup>' },
          { verse_key: '1:2', text: '<p>الثناء</p>' },
          { verse_key: '1:3', text: '' },
          { verse_key: '2:1', text: 'wrong surah' },
        ],
        pagination: { total_records: 7 },
      });
    }
    return json({}, 404);
  });
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: 'postgres://nobody:nothing@127.0.0.1:1/none' });

  beforeAll(async () => {
    const { db } = createDb(env.DATABASE_URL);
    app = await buildApp({
      env,
      db,
      redis: null,
      aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
      fcm: new FcmSender(''),
      qf: new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: 'https://legacy.test/api/v4', fetchImpl: upstream.impl }),
      now: () => new Date('2026-10-31T08:00:00Z'),
    });
  });
  afterAll(async () => app.close());

  it('lists the curated tafsirs, Muyassar first, with attribution', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/content/tafsirs' });
    expect(res.statusCode).toBe(200);
    const list = res.json() as { id: string; language: string; attribution: string; qfId?: number }[];
    expect(list[0]!.id).toBe('muyassar');
    expect(list.map((t) => t.id)).toEqual(['muyassar', 'ibn-kathir', 'saadi', 'ibn-kathir-en']);
    expect(list.every((t) => t.attribution.includes('Quran Foundation') && t.qfId === undefined)).toBe(true);
  });

  it('a surah: plain text by "s:a", empty and foreign rows dropped, cached with ETag (≤ 1 day)', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/content/tafsirs/muyassar/surahs/1' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ tafsirId: 'muyassar', surah: 1, attribution: 'Quran.com · Quran Foundation', ayat: { '1:1': 'أبتدئ (اللهِ) نص', '1:2': 'الثناء' } });
    expect(res.headers['cache-control']).toBe('public, max-age=86400, stale-while-revalidate=172800');
    const before = upstream.calls.length;
    const again = await app.inject({ method: 'GET', url: '/v1/content/tafsirs/muyassar/surahs/1', headers: { 'if-none-match': String(res.headers.etag) } });
    expect(again.statusCode).toBe(304);
    expect(upstream.calls.length).toBe(before); // served from the cache
  });

  it('by ayah: a grouped commentary covers the following ayat', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/content/tafsirs/muyassar/by-ayah/1:3' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ayahKey: '1:3', text: 'الثناء' });
  });

  it('unknown tafsir, bad surah or ayah → 404', async () => {
    for (const url of ['/v1/content/tafsirs/nope/surahs/1', '/v1/content/tafsirs/muyassar/surahs/115', '/v1/content/tafsirs/muyassar/surahs/x', '/v1/content/tafsirs/muyassar/by-ayah/1:8']) {
      const res = await app.inject({ method: 'GET', url });
      expect(res.statusCode, url).toBe(404);
    }
  });

  it('upstream down → 503 content_unavailable (not cached)', async () => {
    mode = 'down';
    const res = await app.inject({ method: 'GET', url: '/v1/content/tafsirs/saadi/surahs/2' });
    expect(res.statusCode).toBe(503);
    expect(res.json().error.code).toBe('content_unavailable');
    mode = 'ok';
  });
});

describe.skipIf(process.env.QF_LIVE !== '1')('live Quran.com public API (QF_LIVE=1)', () => {
  const qf = new QuranFoundationClient({
    clientId: process.env.QF_CLIENT_ID ?? '',
    clientSecret: process.env.QF_CLIENT_SECRET ?? '',
    env: (process.env.QF_ENV as 'production' | 'prelive') ?? 'production',
    publicBaseUrl: 'https://api.quran.com/api/v4',
  });

  it('Alafasy Al-Fatiha has an mp3 and 7 ayah timings', async () => {
    const { audio_file: f } = await qf.chapterAudio(7, 1);
    expect(f.audio_url).toMatch(/^https:\/\/.+\.mp3$/);
    expect(timingsFromQf(f.timestamps)).toHaveLength(7);
  });

  it('Muyassar Al-Fatiha has 7 ayat', async () => {
    expect(await qf.tafsirSurah(16, 1)).toHaveLength(7);
  });
});
