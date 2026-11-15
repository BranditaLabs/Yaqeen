/**
 * Reciters, surah audio + ayah timings, and tafsir (spec §5.13–5.14, §6.6, §10). Audio and tafsir
 * come from Quran.com / Quran Foundation through `ctx.qf` (server-side credentials); our `reciters`
 * table is the curated allowlist (order, Arabic names, active flag).
 *
 * Content is static, so responses go through the ResponseCache (namespace `quran`) with an ETag.
 * QF's Developer Terms allow caching QF content for at most one week, so server copies live 24 h
 * (QF_TTL_SEC) and clients are told the same. Upstream down → 503 `content_unavailable`.
 */
import { asc, eq } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { QF_ATTRIBUTION, type Reciter, type ReciterTimings, type SurahAudio, type TafsirAyah, type TafsirSurah } from '@yaqeen/contracts';
import { reciters } from '../../db/schema.js';
import { parseAyahKey, publicTafsir, TAFSIRS, tafsirById, tafsirPlainText, timingsFromQf } from '../../domain/quran-content.js';
import { QfNotFound, QfUnavailable } from '../../integrations/quran-foundation.js';
import { sendCachedJson } from '../../lib/cache.js';
import { AppError, notFound } from '../../lib/errors.js';

/** Server + client cache lifetime for QF-derived content (QF terms: ≤ 7 days). */
export const QF_TTL_SEC = 24 * 3600;
const TIMINGS_CONCURRENCY = 6;

const ReciterParams = z.object({ id: z.string().regex(/^[a-z0-9_-]{1,40}$/) });
const SurahParams = ReciterParams.extend({ n: z.coerce.number().int().min(1).max(114) });
const TafsirParams = z.object({ id: z.string().regex(/^[a-z0-9-]{1,40}$/), n: z.coerce.number().int().min(1).max(114) });
const TafsirAyahParams = z.object({ id: z.string().regex(/^[a-z0-9-]{1,40}$/), key: z.string() });

const unavailable = () => new AppError(503, 'content_unavailable', 'Quran content is unavailable right now');

/** Upstream errors → our stable codes. */
async function upstream<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    if (e instanceof QfNotFound) throw notFound('content');
    if (e instanceof QfUnavailable) throw unavailable();
    throw e;
  }
}

async function mapLimit<T, R>(items: readonly T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const out = new Array<R>(items.length);
  let next = 0;
  const worker = async () => {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i]!);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

export const quranContentRoutes: FastifyPluginAsync = async (app) => {
  const { db, cache, qf } = app.ctx;

  const loadReciters = async (): Promise<Reciter[]> => {
    const rows = await db.select().from(reciters).where(eq(reciters.active, true)).orderBy(asc(reciters.sortOrder), asc(reciters.nameAr));
    return rows.map((r) => {
      const isQf = r.source === 'qf' && r.qfId != null;
      return {
        id: r.id,
        nameAr: r.nameAr,
        nameEn: r.nameEn,
        style: (['murattal', 'mujawwad', 'muallim'] as const).find((s) => s === r.style) ?? 'murattal',
        riwaya: r.riwaya,
        source: isQf ? 'qf' : 'own',
        qfId: isQf ? r.qfId : null,
        hasTimings: isQf || r.timingUrl != null,
        baseUrl: isQf ? null : r.baseUrl,
        timingUrl: isQf ? null : r.timingUrl,
        sampleUrl: r.sampleUrl,
        sizeBytes: r.sizeBytes,
      };
    });
  };
  const reciterList = () => cache.getJson('catalogue', 'reciters:v2', 600, loadReciters);
  const findReciter = async (id: string): Promise<Reciter> => {
    const r = (JSON.parse(await reciterList()) as Reciter[]).find((x) => x.id === id);
    if (!r) throw notFound('reciter');
    return r;
  };

  /** One surah's audio + timings (cached per reciter mapping + surah). */
  const surahAudio = async (r: Reciter, surah: number): Promise<string> => {
    if (r.source === 'own' || r.qfId == null) {
      if (!r.baseUrl) throw notFound('audio');
      const own: SurahAudio = {
        reciterId: r.id,
        surah,
        url: `${r.baseUrl.replace(/\/+$/, '')}/${String(surah).padStart(3, '0')}.mp3`,
        sizeBytes: null,
        durationMs: null,
        timings: null,
      };
      return JSON.stringify(own);
    }
    const qfId = r.qfId;
    return cache.getJson('quran', `audio:${r.id}:${qfId}:${surah}`, QF_TTL_SEC, async (): Promise<SurahAudio> => {
      const { audio_file: f } = await upstream(() => qf.chapterAudio(qfId, surah));
      if (!f?.audio_url) throw unavailable();
      const timings = timingsFromQf(f.timestamps);
      return {
        reciterId: r.id,
        surah,
        url: f.audio_url,
        sizeBytes: typeof f.file_size === 'number' && f.file_size >= 1024 ? Math.round(f.file_size) : null,
        durationMs: timings ? timings[timings.length - 1]![1] : null,
        timings,
      };
    });
  };

  const parse = <T>(schema: z.ZodType<T>, v: unknown, what: string): T => {
    const p = schema.safeParse(v);
    if (!p.success) throw notFound(what);
    return p.data;
  };

  /** Curated reciters (the app caches the list for offline). */
  app.get('/reciters', async (req, reply) => sendCachedJson(req, reply, await reciterList(), 3600));

  /** Audio URL + per-ayah `[startMs, endMs]` for one surah. */
  app.get('/reciters/:id/surahs/:n', async (req, reply) => {
    const p = parse(SurahParams, req.params, 'surah');
    const r = await findReciter(p.id);
    return sendCachedJson(req, reply, await surahAudio(r, p.n), QF_TTL_SEC);
  });

  /** Every surah's timings — the app's offline `timings.json` for a full download. */
  app.get('/reciters/:id/timings', async (req, reply) => {
    const { id } = parse(ReciterParams, req.params, 'reciter');
    const r = await findReciter(id);
    if (r.source === 'own') {
      if (!r.timingUrl) throw notFound('timings');
      return reply.redirect(r.timingUrl, 302);
    }
    const json = await cache.getJson('quran', `timings:${r.id}:${r.qfId}`, QF_TTL_SEC, async (): Promise<ReciterTimings> => {
      const surahs = Array.from({ length: 114 }, (_, i) => i + 1);
      const docs = await mapLimit(surahs, TIMINGS_CONCURRENCY, async (s) => JSON.parse(await surahAudio(r, s)) as SurahAudio);
      const out: ReciterTimings = {};
      for (const d of docs) if (d.timings) out[String(d.surah)] = d.timings;
      return out;
    });
    return sendCachedJson(req, reply, json, QF_TTL_SEC);
  });

  /** Curated tafsirs (Arabic Muyassar first). */
  app.get('/tafsirs', async (req, reply) => sendCachedJson(req, reply, JSON.stringify(TAFSIRS.map(publicTafsir)), QF_TTL_SEC));

  const tafsirSurah = (tafsirId: string, surah: number) => {
    const t = tafsirById(tafsirId);
    if (!t) throw notFound('tafsir');
    return cache.getJson('quran', `tafsir:${t.id}:${t.qfId}:${surah}`, QF_TTL_SEC, async (): Promise<TafsirSurah> => {
      const rows = await upstream(() => qf.tafsirSurah(t.qfId, surah));
      const ayat: Record<string, string> = {};
      for (const row of rows) {
        const key = parseAyahKey(row.verse_key);
        if (!key || key[0] !== surah) continue;
        const text = tafsirPlainText(row.text ?? '');
        if (text) ayat[row.verse_key] = text;
      }
      if (!Object.keys(ayat).length) throw unavailable(); // never cache an empty surah
      return { tafsirId: t.id, surah, attribution: QF_ATTRIBUTION, ayat };
    });
  };

  /** Plain-text tafsir for a whole surah: `ayat["s:a"]`. */
  app.get('/tafsirs/:id/surahs/:n', async (req, reply) => {
    const p = parse(TafsirParams, req.params, 'tafsir');
    return sendCachedJson(req, reply, await tafsirSurah(p.id, p.n), QF_TTL_SEC);
  });

  /** One ayah; a grouped commentary is returned for every ayah it covers. */
  app.get('/tafsirs/:id/by-ayah/:key', async (req, reply) => {
    const p = parse(TafsirAyahParams, req.params, 'ayah');
    const key = parseAyahKey(p.key);
    if (!key) throw notFound('ayah');
    const doc = JSON.parse(await tafsirSurah(p.id, key[0])) as TafsirSurah;
    let text = '';
    for (let a = key[1]; a >= 1 && !text; a--) text = doc.ayat[`${key[0]}:${a}`] ?? '';
    const body: TafsirAyah = { tafsirId: doc.tafsirId, ayahKey: `${key[0]}:${key[1]}`, text, attribution: QF_ATTRIBUTION };
    return sendCachedJson(req, reply, JSON.stringify(body), QF_TTL_SEC);
  });
};
