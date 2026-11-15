/**
 * Reciters against Postgres: the curated `reciters` table (active + order honoured, qf mapping),
 * surah audio resolved through a mocked Quran Foundation, the full timings document, own-CDN rows,
 * and the 0015 migration that remapped the placeholder rows.
 * Skipped without TEST_DATABASE_URL — see integration.db.test.ts.
 */
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { migrate } from 'drizzle-orm/node-postgres/migrator';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { loadEnv } from '../src/config/env.js';
import { createDb, type Db } from '../src/db/client.js';
import * as s from '../src/db/schema.js';
import { AYAH_COUNTS } from '../src/domain/quran-content.js';
import { AlAdhanClient } from '../src/integrations/aladhan.js';
import { FcmSender } from '../src/integrations/fcm.js';
import { QuranFoundationClient } from '../src/integrations/quran-foundation.js';
import { ShopifyClient } from '../src/integrations/shopify.js';

const url = process.env.TEST_DATABASE_URL;

describe.skipIf(!url)('reciters + surah audio (Postgres)', () => {
  let app: FastifyInstance;
  let db: Db;
  let pool: pg.Pool;
  let down = false;
  const upstreamCalls: string[] = [];
  const env = loadEnv({ NODE_ENV: 'test', DATABASE_URL: url ?? 'postgres://skip@localhost:5432/skip' });

  const fetchImpl = (async (input: string | URL | Request) => {
    const u = String(input);
    upstreamCalls.push(u);
    if (down) return new Response('{}', { status: 503 });
    const m = /\/chapter_recitations\/(\d+)\/(\d+)\?segments=true$/.exec(u);
    if (!m) return new Response('{}', { status: 404 });
    const surah = Number(m[2]);
    const n = AYAH_COUNTS[surah - 1]!;
    const timestamps = Array.from({ length: n }, (_, i) => ({ verse_key: `${surah}:${i + 1}`, timestamp_from: i * 1000, timestamp_to: (i + 1) * 1000, duration: 1000 }));
    return new Response(
      JSON.stringify({ audio_file: { id: 1, chapter_id: surah, file_size: 839808, format: 'mp3', audio_url: `https://download.quranicaudio.test/qdc/r${m[1]}/${surah}.mp3`, timestamps } }),
      { status: 200, headers: { 'content-type': 'application/json' } },
    );
  }) as typeof fetch;

  beforeAll(async () => {
    const reset = new pg.Client({ connectionString: url });
    await reset.connect();
    await reset.query('drop schema if exists public cascade; drop schema if exists drizzle cascade; create schema public;');
    await reset.end();
    ({ db, pool } = createDb(url!));
    const folder = fileURLToPath(new URL('../drizzle', import.meta.url));
    await migrate(db, { migrationsFolder: folder });
    app = await buildApp({
      env,
      db,
      redis: null,
      aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, null),
      shopify: new ShopifyClient({ shopDomain: '', adminToken: '', apiVersion: '2025-10' }),
      fcm: new FcmSender(''),
      qf: new QuranFoundationClient({ clientId: '', clientSecret: '', env: 'production', publicBaseUrl: 'https://legacy.test/api/v4', fetchImpl }),
      now: () => new Date('2026-10-31T08:00:00Z'),
    });
    await db.insert(s.reciters).values([
      { id: 'alafasy', nameAr: 'مشاري راشد العفاسي', nameEn: 'Mishary Rashid Alafasy', source: 'qf', qfId: 7, sortOrder: 1, sizeBytes: 1_722_899_470 },
      { id: 'husary', nameAr: 'محمود خليل الحصري', nameEn: 'Mahmoud Khalil Al-Husary', source: 'qf', qfId: 6, sortOrder: 0 },
      { id: 'hidden', nameAr: 'مخفي', nameEn: 'Hidden', source: 'qf', qfId: 3, sortOrder: 2, active: false },
      { id: 'ours', nameAr: 'قارئ', nameEn: 'Ours', style: 'mujawwad', source: 'own', baseUrl: 'https://cdn.test/ours/', timingUrl: 'https://cdn.test/ours/timings.json', sortOrder: 3 },
    ]);
  });

  afterAll(async () => {
    await app?.close();
    await pool?.end();
  });

  it('lists active reciters in sort order with their source', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/content/reciters' });
    expect(res.statusCode).toBe(200);
    expect(res.headers.etag).toBeTruthy();
    const list = res.json() as Record<string, unknown>[];
    expect(list.map((r) => r.id)).toEqual(['husary', 'alafasy', 'ours']);
    expect(list[1]).toEqual({
      id: 'alafasy',
      nameAr: 'مشاري راشد العفاسي',
      nameEn: 'Mishary Rashid Alafasy',
      style: 'murattal',
      riwaya: 'hafs',
      source: 'qf',
      qfId: 7,
      hasTimings: true,
      baseUrl: null,
      timingUrl: null,
      sampleUrl: null,
      sizeBytes: 1_722_899_470,
    });
    expect(list[2]).toMatchObject({ source: 'own', qfId: null, baseUrl: 'https://cdn.test/ours/', hasTimings: true });
  });

  it('a surah: QF audio URL + per-ayah [start, end], cached for a day', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/content/reciters/alafasy/surahs/1' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      reciterId: 'alafasy',
      surah: 1,
      url: 'https://download.quranicaudio.test/qdc/r7/1.mp3',
      sizeBytes: 839808,
      durationMs: 7000,
      timings: [[0, 1000], [1000, 2000], [2000, 3000], [3000, 4000], [4000, 5000], [5000, 6000], [6000, 7000]],
    });
    expect(res.headers['cache-control']).toContain('max-age=86400');
    const before = upstreamCalls.length;
    await app.inject({ method: 'GET', url: '/v1/content/reciters/alafasy/surahs/1' });
    expect(upstreamCalls.length).toBe(before);
  });

  it('own-CDN reciter: zero-padded file, no timings; unknown / hidden / bad surah → 404', async () => {
    const own = await app.inject({ method: 'GET', url: '/v1/content/reciters/ours/surahs/2' });
    expect(own.json()).toMatchObject({ url: 'https://cdn.test/ours/002.mp3', timings: null });
    for (const u of ['/v1/content/reciters/nobody/surahs/1', '/v1/content/reciters/hidden/surahs/1', '/v1/content/reciters/alafasy/surahs/0', '/v1/content/reciters/alafasy/surahs/115', '/v1/content/reciters/ALAFASY/surahs/1']) {
      expect((await app.inject({ method: 'GET', url: u })).statusCode, u).toBe(404);
    }
  });

  it('timings document: every surah, the app\'s timings.json shape', async () => {
    const res = await app.inject({ method: 'GET', url: '/v1/content/reciters/husary/timings' });
    expect(res.statusCode).toBe(200);
    const doc = res.json() as Record<string, [number, number][]>;
    expect(Object.keys(doc)).toHaveLength(114);
    expect(doc['2']).toHaveLength(286);
    expect(doc['114']![5]).toEqual([5000, 6000]);
    const own = await app.inject({ method: 'GET', url: '/v1/content/reciters/ours/timings' });
    expect(own.statusCode).toBe(302);
    expect(own.headers.location).toBe('https://cdn.test/ours/timings.json');
  });

  it('upstream down → 503 content_unavailable', async () => {
    down = true;
    const res = await app.inject({ method: 'GET', url: '/v1/content/reciters/alafasy/surahs/3' });
    expect(res.statusCode).toBe(503);
    expect(res.json().error.code).toBe('content_unavailable');
    down = false;
    expect((await app.inject({ method: 'GET', url: '/v1/content/reciters/alafasy/surahs/3' })).statusCode).toBe(200);
  });

  it('migration 0015 remaps the placeholder launch rows to Quran Foundation', async () => {
    const c = new pg.Client({ connectionString: url });
    await c.connect();
    try {
      await c.query(`insert into reciters (id, name_ar, name_en, style, base_url, timing_url, sample_url) values
        ('minshawi', 'م', 'M', 'mujawwad', 'https://cdn.yaqin-brand.com/audio/minshawi', 'https://cdn.yaqin-brand.com/audio/minshawi/timings.json', 'x'),
        ('muaiqly', 'م', 'M', 'murattal', 'https://cdn.yaqin-brand.com/audio/muaiqly', null, null)`);
      const sql = (await import('node:fs')).readFileSync(fileURLToPath(new URL('../drizzle/0015_quran_foundation.sql', import.meta.url)), 'utf8');
      const updates = sql.split('--> statement-breakpoint').filter((q) => q.includes('UPDATE'));
      for (const q of updates) await c.query(q);
      const { rows } = await c.query(`select id, source, qf_id, style, base_url, active from reciters where id in ('minshawi', 'muaiqly') order by id`);
      expect(rows).toEqual([
        { id: 'minshawi', source: 'qf', qf_id: 9, style: 'murattal', base_url: null, active: true },
        { id: 'muaiqly', source: 'own', qf_id: null, style: 'murattal', base_url: 'https://cdn.yaqin-brand.com/audio/muaiqly', active: false },
      ]);
    } finally {
      await c.end();
    }
  });
});
