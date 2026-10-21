/**
 * Public app endpoints: remote config, Hijri calendar, challenge, rewards, content.
 */
import { and, asc, eq, gt } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { BonusKind, CompleteTaskRequest, ContentType, type RemoteConfig, TaskKey } from '@yaqeen/contracts';
import { appConfig, contentItems, dailyTasks, rewards, users } from '../../db/schema.js';
import { addDays, localToday } from '../../domain/points.js';
import { badRequest } from '../../lib/errors.js';
import { userId } from '../../plugins/auth.js';
import { adjustmentsFor, hijriRange } from '../../services/calendar.service.js';
import * as challenge from '../../services/challenge.service.js';
import { POINTS_CONFIG_KEY, getPointsSettings } from '../../services/program.service.js';
import { redeem } from '../../services/rewards.service.js';

const IsoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

export const DEFAULT_CONFIG: RemoteConfig = {
  features: { challenge: true, rewards: true, hifz: true, listen: true, bonuses: false },
  minVersion: { ios: '1.0.0', android: '1.0.0' },
  maintenance: { enabled: false, messageAr: '', messageEn: '' },
  splashVerse: { textAr: 'وَٱعْبُدْ رَبَّكَ حَتَّىٰ يَأْتِيَكَ ٱلْيَقِينُ', reference: 'الحجر: 99' },
  hijri: { region: 'EG', offsetDays: 0, effectiveFrom: null },
  points: { qadaDayPoints: 80, qadaWindowDays: 7, challengeLengthDays: 365 },
};

export async function readConfig(app: Parameters<FastifyPluginAsync>[0]): Promise<RemoteConfig> {
  const rows = await app.ctx.db.select().from(appConfig);
  const merged: Record<string, unknown> = { ...DEFAULT_CONFIG };
  for (const r of rows) if (r.key !== POINTS_CONFIG_KEY) merged[r.key] = r.value;
  const ps = await getPointsSettings(app.ctx);
  merged.points = { qadaDayPoints: ps.qadaDayPoints, qadaWindowDays: ps.qadaWindowDays, challengeLengthDays: ps.challengeLengthDays };
  const adj = (await adjustmentsFor(app.ctx, app.ctx.env.HIJRI_REGION))[0];
  merged.hijri = adj
    ? { region: app.ctx.env.HIJRI_REGION, offsetDays: adj.offsetDays, effectiveFrom: `${adj.effectiveHijriYear}-${adj.effectiveHijriMonth}` }
    : DEFAULT_CONFIG.hijri;
  return merged as RemoteConfig;
}

export const appRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;

  /* -------------------------------------------------------------- config */
  app.get('/config', async (_req, reply) => {
    const cfg = await readConfig(app);
    reply.header('Cache-Control', 'public, max-age=300');
    return cfg;
  });

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
    const days = await hijriRange(app.ctx, from, to, { personalOffset: q.offset });
    reply.header('Cache-Control', 'public, max-age=3600');
    return { method: 'UAQ', offsetDays: q.offset, days };
  });

  /* ------------------------------------------------------------- content */
  app.get('/content', async (req, reply) => {
    const q = z.object({ type: ContentType.optional(), since: z.iso.datetime().optional() }).parse(req.query);
    const conds = [eq(contentItems.status, 'published')];
    if (q.type) conds.push(eq(contentItems.type, q.type));
    if (q.since) conds.push(gt(contentItems.updatedAt, new Date(q.since)));
    const rows = await db
      .select({
        id: contentItems.id,
        type: contentItems.type,
        category: contentItems.category,
        title: contentItems.title,
        textAr: contentItems.textAr,
        translationEn: contentItems.translationEn,
        source: contentItems.source,
        repeatCount: contentItems.repeatCount,
        version: contentItems.version,
        updatedAt: contentItems.updatedAt,
      })
      .from(contentItems)
      .where(and(...conds))
      .orderBy(asc(contentItems.category), asc(contentItems.title));
    reply.header('Cache-Control', 'public, max-age=600');
    return rows;
  });

  app.get('/daily-task', async (req) => {
    const date = IsoDate.default(localToday(app.ctx.now())).parse((req.query as { date?: string }).date);
    const [t] = await db.select().from(dailyTasks).where(eq(dailyTasks.date, date));
    return t ? { date: t.date, taskAr: t.taskAr, taskEn: t.taskEn } : null;
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
        return redeem(app.ctx, userId(req), id);
      },
    );
  });
};
