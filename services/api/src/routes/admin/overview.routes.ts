import { and, eq, gte, lte, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { type AdminOverview, type OverviewAdherence, type OverviewAlert, type OverviewFunnel, OverviewRange, type OverviewSeries } from '@yaqeen/contracts';
import { challengeEnrollments, contentItems, dailyTasks, pointsLedger, redemptions, rewards, taskCompletions, userActivityDays, users } from '../../db/schema.js';
import { HIJRI_MONTHS_AR } from '../../domain/hijri.js';
import { FUNNEL_DAYS, RANGE_DAYS, fillSeries, pct, suppress } from '../../domain/aggregates.js';
import { addDays, localToday } from '../../domain/points.js';
import { hijriRange } from '../../services/calendar.service.js';

/**
 * Overview KPIs. Worship data is only ever returned as aggregates across all users,
 * with k-anonymity (K_ANONYMITY = 20) — never per user (see docs/SECURITY_PRIVACY.md §Admin access).
 */
export const adminOverviewRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const anyAdmin = app.requireAdmin(['marketing', 'support', 'content_editor', 'religious_reviewer']);
  const n = sql<string>`count(*)`;
  const count = async (q: Promise<{ n: string }[]>) => Number((await q)[0]?.n ?? 0);

  async function adherence(date: string): Promise<OverviewAdherence> {
    const participants = await count(db.select({ n }).from(challengeEnrollments).where(lte(challengeEnrollments.startedOn, date)));
    const rows = await db
      .select({ task: taskCompletions.task, n })
      .from(taskCompletions)
      .where(eq(taskCompletions.date, date))
      .groupBy(taskCompletions.task);
    const of = (t: string) => Number(rows.find((r) => r.task === t)?.n ?? 0);
    return {
      date,
      participants,
      wirdPct: pct(of('wird'), participants),
      morningAzkarPct: pct(of('morning_azkar'), participants),
      prayersPct: pct(of('five_prayers'), participants),
    };
  }

  app.get('/', { preHandler: anyAdmin }, async (): Promise<AdminOverview> => {
    const now = app.ctx.now();
    const day = new Date(now.getTime() - 86_400_000);
    const month = new Date(now.getTime() - 30 * 86_400_000);
    const today = localToday(now);

    const [dau, mau, participants, pendingReviews] = await Promise.all([
      count(db.select({ n }).from(users).where(gte(users.lastSeenAt, day))),
      count(db.select({ n }).from(users).where(gte(users.lastSeenAt, month))),
      count(db.select({ n }).from(challengeEnrollments)),
      count(db.select({ n }).from(contentItems).where(eq(contentItems.status, 'pending_review'))),
    ]);

    const [ledger] = await db
      .select({
        issued: sql<string>`coalesce(sum(${pointsLedger.delta}) filter (where ${pointsLedger.delta} > 0 and ${pointsLedger.reason} in ('task','qada','bonus')), 0)`,
        redeemed: sql<string>`coalesce(-sum(${pointsLedger.delta}) filter (where ${pointsLedger.reason} = 'redemption'), 0)`,
      })
      .from(pointsLedger)
      .where(gte(pointsLedger.createdAt, month));

    const habits = await adherence(today);
    return {
      dau,
      mau,
      challengeParticipants: participants,
      pointsIssued30d: Number(ledger?.issued ?? 0),
      pointsRedeemed30d: Number(ledger?.redeemed ?? 0),
      // Suppressed values are reported as 0 here for backwards compatibility; /adherence returns null.
      habitsToday: { wirdPct: habits.wirdPct ?? 0, morningAzkarPct: habits.morningAzkarPct ?? 0, prayersPct: habits.prayersPct ?? 0 },
      pendingReviews,
    };
  });

  /** Daily active users (any authenticated request that day), one point per day. */
  app.get('/series', { preHandler: anyAdmin }, async (req): Promise<OverviewSeries> => {
    const q = z.object({ metric: z.literal('dau').default('dau'), range: OverviewRange.default('30d') }).parse(req.query);
    const to = localToday(app.ctx.now());
    const from = addDays(to, -(RANGE_DAYS[q.range] - 1));
    const rows = await db
      .select({ date: userActivityDays.date, n })
      .from(userActivityDays)
      .where(and(gte(userActivityDays.date, from), lte(userActivityDays.date, to)))
      .groupBy(userActivityDays.date);
    return { metric: 'dau', range: q.range, points: fillSeries(from, to, rows.map((r) => ({ date: r.date, n: Number(r.n) })), addDays) };
  });

  /** Challenge funnel: joined → still active on day 7 → 30 → 100 (any completion on or after that day). */
  app.get('/funnel', { preHandler: anyAdmin }, async (): Promise<OverviewFunnel> => {
    const steps = await Promise.all(
      FUNNEL_DAYS.map(async (d) => {
        const res = await db.execute(sql`
          select count(*)::int as n from challenge_enrollments ce
          where ${d} = 1 or exists (
            select 1 from task_completions tc
            where tc.user_id = ce.user_id and tc.date >= ce.started_on + ${d - 1}::int)`);
        return { days: d, users: suppress(Number((res.rows[0] as { n: number } | undefined)?.n ?? 0)) };
      }),
    );
    return { steps };
  });

  app.get('/adherence', { preHandler: anyAdmin }, async (req) => {
    const q = z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() }).parse(req.query);
    return adherence(q.date ?? localToday(app.ctx.now()));
  });

  /** Things that need someone today. */
  app.get('/alerts', { preHandler: anyAdmin }, async (): Promise<OverviewAlert[]> => {
    const now = app.ctx.now();
    const today = localToday(now);
    const tomorrow = addDays(today, 1);
    const alerts: OverviewAlert[] = [];

    const pending = await count(db.select({ n }).from(contentItems).where(eq(contentItems.status, 'pending_review')));
    if (pending > 0) alerts.push({ kind: 'pending_reviews', severity: 'warning', messageAr: `${pending} عناصر بانتظار المراجعة الشرعية`, href: '/content?status=pending_review' });

    const [task] = await db.select({ d: dailyTasks.date }).from(dailyTasks).where(eq(dailyTasks.date, tomorrow));
    if (!task) alerts.push({ kind: 'daily_task_missing', severity: 'warning', messageAr: 'مهمة الغد غير محددة بعد', href: '/content?tab=daily' });

    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    const capped = await db
      .select({ id: rewards.id, title: rewards.titleAr, cap: rewards.monthlyCap, used: sql<string>`(select count(*) from ${redemptions} r where r.reward_id = ${rewards.id} and r.created_at >= ${monthStart} and r.status <> 'void')` })
      .from(rewards)
      .where(and(eq(rewards.active, true), sql`${rewards.monthlyCap} is not null`));
    for (const r of capped) {
      const left = (r.cap ?? 0) - Number(r.used);
      if (left <= Math.max(5, Math.ceil((r.cap ?? 0) * 0.1))) {
        alerts.push({ kind: 'reward_low_stock', severity: left <= 0 ? 'warning' : 'info', messageAr: `«${r.title}»: باقي ${Math.max(0, left)} كوداً هذا الشهر`, href: '/rewards?tab=catalogue' });
      }
    }

    if (app.ctx.shopify.lastError && now.getTime() - app.ctx.shopify.lastError.at.getTime() < 24 * 3600_000) {
      alerts.push({ kind: 'shopify_error', severity: 'warning', messageAr: 'تعذّر الاتصال بمتجر Shopify خلال آخر 24 ساعة', href: '/rewards' });
    }

    try {
      const days = await hijriRange(app.ctx, today, addDays(today, 3));
      const eve = days.find((d) => d.hijriDay === 29);
      if (eve) {
        const next = (eve.hijriMonth % 12) + 1;
        alerts.push({ kind: 'moon_sighting', severity: 'info', messageAr: `تحرّي هلال ${HIJRI_MONTHS_AR[next - 1]} مساء ${eve.gregorian} — راجع تعديل التقويم بعد إعلان دار الإفتاء`, href: '/settings?tab=hijri' });
      }
    } catch {
      // AlAdhan unavailable — skip this alert rather than failing the overview.
    }
    return alerts;
  });
};
