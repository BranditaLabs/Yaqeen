import { and, eq, gte, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import type { AdminOverview } from '@yaqeen/contracts';
import { challengeEnrollments, contentItems, pointsLedger, taskCompletions, users } from '../../db/schema.js';
import { localToday } from '../../domain/points.js';

/**
 * Overview KPIs. Worship data is only ever returned as percentages across all users —
 * never per user (see docs/SECURITY_PRIVACY.md §Admin access).
 */
export const adminOverviewRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;

  app.get('/', { preHandler: app.requireAdmin(['marketing', 'support', 'content_editor', 'religious_reviewer']) }, async (): Promise<AdminOverview> => {
    const now = app.ctx.now();
    const day = new Date(now.getTime() - 86_400_000);
    const month = new Date(now.getTime() - 30 * 86_400_000);
    const today = localToday(now);

    const count = async (q: Promise<{ n: string }[]>) => Number((await q)[0]?.n ?? 0);
    const n = sql<string>`count(*)`;

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

    const habit = async (task: 'wird' | 'morning_azkar' | 'five_prayers') =>
      participants === 0
        ? 0
        : Math.round(
            (1000 *
              (await count(
                db.select({ n }).from(taskCompletions).where(and(eq(taskCompletions.date, today), eq(taskCompletions.task, task))),
              ))) /
              participants,
          ) / 10;

    return {
      dau,
      mau,
      challengeParticipants: participants,
      pointsIssued30d: Number(ledger?.issued ?? 0),
      pointsRedeemed30d: Number(ledger?.redeemed ?? 0),
      habitsToday: {
        wirdPct: await habit('wird'),
        morningAzkarPct: await habit('morning_azkar'),
        prayersPct: await habit('five_prayers'),
      },
      pendingReviews,
    };
  });
};
