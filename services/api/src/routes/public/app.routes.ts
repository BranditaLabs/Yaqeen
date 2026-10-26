/**
 * Public app endpoints: remote config, Hijri calendar, challenge, rewards, content.
 */
import { and, asc, eq, gt, inArray } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { BonusKind, type ChallengeCalendar, CompleteTaskRequest, ContentType, type RemoteConfig, TaskKey } from '@yaqeen/contracts';
import { appConfig, contentItems, contentPacks, dailyTasks, reciters, rewards, users } from '../../db/schema.js';
import { specialDays } from '../../domain/hijri.js';
import { addDays, localToday } from '../../domain/points.js';
import { sendCachedJson } from '../../lib/cache.js';
import { badRequest } from '../../lib/errors.js';
import { userId } from '../../plugins/auth.js';
import { adjustmentsFor, hijriRange } from '../../services/calendar.service.js';
import * as challenge from '../../services/challenge.service.js';
import { POINTS_CONFIG_KEY, getPointsSettings } from '../../services/program.service.js';
import { redeem } from '../../services/rewards.service.js';
import { CARDS_CONFIG_KEY, readCardsSettings } from '../../services/cards-settings.service.js';

const IsoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

export const DEFAULT_CONFIG: RemoteConfig = {
  features: { challenge: true, rewards: true, hifz: true, listen: true, bonuses: false, recite: false, ramadan: false, tafsirFull: false, publicCards: true, medalActivation: true },
  featureRollout: {},
  // 0.0.0 = no forced update; only an admin-set minimum may block clients.
  minVersion: { ios: '0.0.0', android: '0.0.0' },
  maintenance: { enabled: false, messageAr: '', messageEn: '' },
  splashVerse: { textAr: 'وَٱعْبُدْ رَبَّكَ حَتَّىٰ يَأْتِيَكَ ٱلْيَقِينُ', reference: 'الحجر: 99' },
  hijri: { region: 'EG', offsetDays: 0, effectiveFrom: null },
  cards: { medalProductUrl: '' },
  points: { dailyTotal: 100, qadaDayPoints: 80, qadaWindowDays: 7, challengeLengthDays: 365, cheapestRewardPoints: null },
};

/** Content types the app syncs from /v1/content (the splash verse ships in /v1/config). */
const SYNCED_TYPES = ['dua', 'zikr'] as const;

export async function readConfig(app: Parameters<FastifyPluginAsync>[0]): Promise<RemoteConfig> {
  const rows = await app.ctx.db.select().from(appConfig);
  const merged: Record<string, unknown> = { ...DEFAULT_CONFIG };
  for (const r of rows) {
    if (r.key === POINTS_CONFIG_KEY || r.key === CARDS_CONFIG_KEY) continue;
    // Stored flags are merged over the defaults so new flags appear without a migration.
    merged[r.key] = r.key === 'features' ? { ...DEFAULT_CONFIG.features, ...(r.value as object) } : r.value;
  }
  const ps = await getPointsSettings(app.ctx);
  const [cheapest] = await app.ctx.db
    .select({ cost: rewards.costPoints })
    .from(rewards)
    .where(eq(rewards.active, true))
    .orderBy(asc(rewards.costPoints))
    .limit(1);
  // Only the public part of the card settings reaches apps (reserved handles and copy stay server-side).
  const cards = await readCardsSettings(app.ctx);
  merged.cards = { medalProductUrl: cards.medalProductUrl || app.ctx.env.STORE_URL };
  merged.points = {
    dailyTotal: ps.dailyTotal,
    qadaDayPoints: ps.qadaDayPoints,
    qadaWindowDays: ps.qadaWindowDays,
    challengeLengthDays: ps.challengeLengthDays,
    cheapestRewardPoints: cheapest?.cost ?? null,
  };
  const adj = (await adjustmentsFor(app.ctx, app.ctx.env.HIJRI_REGION))[0];
  merged.hijri = adj
    ? { region: app.ctx.env.HIJRI_REGION, offsetDays: adj.offsetDays, effectiveFrom: `${adj.effectiveHijriYear}-${adj.effectiveHijriMonth}` }
    : DEFAULT_CONFIG.hijri;
  return merged as RemoteConfig;
}

export const appRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;

  /* -------------------------------------------------------------- config */
  app.get('/config', async (req, reply) =>
    sendCachedJson(req, reply, await app.ctx.cache.getJson('config', 'v1', 60, () => readConfig(app)), 300),
  );

  /* ------------------------------------------------------------ calendar */
  // Gregorian month → Hijri days (UAQ + Egypt adjustments). Public so it works before sign-in.
  app.get('/calendar/hijri', async (req, reply) => {
    const q = z
      .object({
        year: z.coerce.number().int().min(2024).max(2100),
        month: z.coerce.number().int().min(1).max(12),
        offset: z.coerce.number().int().min(-2).max(2).default(0),
      })
      .parse(req.query);
    const from = `${q.year}-${String(q.month).padStart(2, '0')}-01`;
    const to = addDays(q.month === 12 ? `${q.year + 1}-01-01` : `${q.year}-${String(q.month + 1).padStart(2, '0')}-01`, -1);
    const json = await app.ctx.cache.getJson('calendar', `${from}:${q.offset}`, 3600, async () => ({
      method: 'UAQ',
      offsetDays: q.offset,
      days: await hijriRange(app.ctx, from, to, { personalOffset: q.offset }),
    }));
    return sendCachedJson(req, reply, json, 3600);
  });

  /* ------------------------------------------------------------- content */
  app.get('/content', async (req, reply) => {
    const q = z
      .object({ type: ContentType.exclude(['splash_verse']).optional(), since: z.iso.datetime().optional() })
      .parse(req.query);
    const conds = [eq(contentItems.status, 'published'), inArray(contentItems.type, [...SYNCED_TYPES])];
    if (q.type) conds.push(eq(contentItems.type, q.type));
    if (q.since) conds.push(gt(contentItems.updatedAt, new Date(q.since)));
    const load = () => db
      .select({
        id: contentItems.id,
        type: contentItems.type,
        category: contentItems.category,
        title: contentItems.title,
        textAr: contentItems.textAr,
        translationEn: contentItems.translationEn,
        source: contentItems.source,
        virtue: contentItems.virtue,
        repeatCount: contentItems.repeatCount,
        sortOrder: contentItems.sortOrder,
        featured: contentItems.featured,
        version: contentItems.version,
        updatedAt: contentItems.updatedAt,
      })
      .from(contentItems)
      .where(and(...conds))
      .orderBy(asc(contentItems.category), asc(contentItems.sortOrder), asc(contentItems.title));
    const json = await app.ctx.cache.getJson('content', `list:${q.type ?? '*'}:${q.since ?? ''}`, 300, load);
    return sendCachedJson(req, reply, json, 600);
  });

  /** Licensed recitations (catalogue changes rarely; the app caches it). */
  app.get('/content/reciters', async (req, reply) => {
    const load = () => db
      .select({
        id: reciters.id,
        nameAr: reciters.nameAr,
        nameEn: reciters.nameEn,
        style: reciters.style,
        riwaya: reciters.riwaya,
        baseUrl: reciters.baseUrl,
        timingUrl: reciters.timingUrl,
        sampleUrl: reciters.sampleUrl,
        sizeBytes: reciters.sizeBytes,
      })
      .from(reciters)
      .where(eq(reciters.active, true))
      .orderBy(asc(reciters.sortOrder), asc(reciters.nameAr));
    return sendCachedJson(req, reply, await app.ctx.cache.getJson('catalogue', 'reciters', 600, load), 3600);
  });

  /** Downloadable packs; the app verifies `sha256` before installing a pack. */
  app.get('/content/packs', async (req, reply) => {
    const load = () => db
      .select({
        id: contentPacks.id,
        kind: contentPacks.kind,
        titleAr: contentPacks.titleAr,
        titleEn: contentPacks.titleEn,
        version: contentPacks.version,
        url: contentPacks.url,
        sha256: contentPacks.sha256,
        sizeBytes: contentPacks.sizeBytes,
      })
      .from(contentPacks)
      .where(eq(contentPacks.active, true))
      .orderBy(asc(contentPacks.kind), asc(contentPacks.id));
    return sendCachedJson(req, reply, await app.ctx.cache.getJson('catalogue', 'packs', 600, load), 3600);
  });

  app.get('/daily-task', async (req, reply) => {
    const date = IsoDate.default(localToday(app.ctx.now())).parse((req.query as { date?: string }).date);
    const json = await app.ctx.cache.getJson('content', `daily:${date}`, 300, async () => {
      const [t] = await db.select().from(dailyTasks).where(eq(dailyTasks.date, date));
      return t ? { date: t.date, taskAr: t.taskAr, taskEn: t.taskEn } : null;
    });
    return sendCachedJson(req, reply, json, 300);
  });

  /* ----------------------------------------------------------- challenge */
  app.register(async (r) => {
    r.addHook('preHandler', app.requireUser);

    r.post('/challenge/enroll', async (req) => {
      const [u] = await db.select({ isGuest: users.isGuest }).from(users).where(eq(users.id, userId(req)));
      // Guests can track locally, but points (= money in the store) require a real account.
      if (u?.isGuest) throw badRequest('account_required');
      return challenge.enroll(app.ctx, userId(req));
    });

    r.get('/challenge/summary', async (req) => challenge.summary(app.ctx, userId(req)));

    r.get('/challenge/days', async (req) => {
      const q = z.object({ from: IsoDate, to: IsoDate }).parse(req.query);
      if (q.to < q.from || addDays(q.from, 92) < q.to) throw badRequest('range_too_large', 'Max 92 days per request');
      return challenge.days(app.ctx, userId(req), q.from, q.to);
    });

    /** One Gregorian month of the merged calendar: Hijri dates + challenge statuses + special days. */
    r.get('/challenge/calendar', async (req): Promise<ChallengeCalendar> => {
      const { month } = z.object({ month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/) }).parse(req.query);
      const uid = userId(req);
      const from = `${month}-01`;
      const to = addDays(addDays(from, 32).slice(0, 8) + '01', -1);
      const [u] = await db.select({ off: users.hijriOffsetDays }).from(users).where(eq(users.id, uid));
      const [hijri, statuses, summary, settings] = await Promise.all([
        hijriRange(app.ctx, from, to, { personalOffset: u?.off ?? 0 }),
        challenge.days(app.ctx, uid, from, to),
        challenge.summary(app.ctx, uid),
        getPointsSettings(app.ctx),
      ]);
      const byDate = new Map(statuses.map((d) => [d.date, d]));
      return {
        month,
        enrolled: summary.enrolled,
        startedOn: summary.startedOn,
        endsOn: summary.startedOn ? addDays(summary.startedOn, settings.challengeLengthDays - 1) : null,
        today: await challenge.todayFor(app.ctx, uid),
        dayNumber: summary.dayNumber,
        streak: summary.streak,
        balance: summary.balance,
        qadaWindowDays: settings.qadaWindowDays,
        qadaDayPoints: settings.qadaDayPoints,
        dailyTotal: settings.dailyTotal,
        days: hijri.map((h) => ({ ...h, challenge: byDate.get(h.gregorian) ?? null, special: specialDays(h) })),
      };
    });

    r.post('/challenge/tasks/:task/complete', async (req) => {
      const { task } = z.object({ task: TaskKey }).parse(req.params);
      const body = CompleteTaskRequest.parse(req.body);
      return challenge.completeTask(app.ctx, userId(req), task, body.date, body.clientEventId);
    });

    r.post('/challenge/bonuses/:kind/claim', async (req) => {
      const { kind } = z.object({ kind: BonusKind }).parse(req.params);
      return { awarded: await challenge.claimBonus(app.ctx, userId(req), kind) };
    });

    /* ------------------------------------------------------------ rewards */
    r.get('/rewards', async (req) => {
      const balance = await challenge.balance(app.ctx, userId(req));
      const rows = await db.select().from(rewards).where(eq(rewards.active, true)).orderBy(asc(rewards.costPoints));
      return rows.map((x) => ({
        id: x.id,
        titleAr: x.titleAr,
        titleEn: x.titleEn,
        kind: x.kind,
        value: x.value,
        costPoints: x.costPoints,
        available: balance >= x.costPoints,
      }));
    });

    r.post(
      '/rewards/:id/redeem',
      { config: { rateLimit: { max: 5, timeWindow: '1 minute' } } },
      async (req) => {
        const { id } = z.object({ id: z.uuid() }).parse(req.params);
        const key = z.string().min(8).max(80).optional().parse(req.headers['idempotency-key']);
        return redeem(app.ctx, userId(req), id, key);
      },
    );
  });
};
