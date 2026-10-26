/**
 * Card programme counters per Cairo day. Only a number per (day, metric) — never who opened,
 * scanned or clicked. Bumps are fire-and-forget so a page never waits on them.
 */
import { and, desc, gte, isNotNull, isNull, sql } from 'drizzle-orm';
import { CARD_METRICS, type CardMetric, type CardsStats } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { cardDailyStats, profileTags, publicProfiles } from '../db/schema.js';
import { addDays, localToday } from '../domain/points.js';

export async function bump(ctx: AppContext, metric: CardMetric): Promise<void> {
  await ctx.db
    .insert(cardDailyStats)
    .values({ date: localToday(ctx.now()), metric, value: 1 })
    .onConflictDoUpdate({ target: [cardDailyStats.date, cardDailyStats.metric], set: { value: sql`${cardDailyStats.value} + 1` } });
}

/** Never let a counter break a request. */
export function bumpLater(ctx: AppContext, metric: CardMetric, log?: { warn: (o: object, m: string) => void }) {
  bump(ctx, metric).catch((err) => log?.warn({ err }, `card stat ${metric} failed`));
}

export async function stats(ctx: AppContext, days: number): Promise<CardsStats> {
  const today = localToday(ctx.now());
  const from = addDays(today, -(days - 1));
  const rows = await ctx.db
    .select({ date: cardDailyStats.date, metric: cardDailyStats.metric, value: cardDailyStats.value })
    .from(cardDailyStats)
    .where(gte(cardDailyStats.date, from))
    .orderBy(cardDailyStats.date);
  const totals = Object.fromEntries(CARD_METRICS.map((m) => [m, 0])) as Record<CardMetric, number>;
  const series = rows
    .filter((r): r is typeof r & { metric: CardMetric } => (CARD_METRICS as readonly string[]).includes(r.metric))
    .map((r) => {
      totals[r.metric] += r.value;
      return { date: r.date, metric: r.metric, value: r.value };
    });
  const [cards] = await ctx.db
    .select({ n: sql<number>`count(*)::int` })
    .from(publicProfiles)
    .where(and(sql`${publicProfiles.published} = true`, isNull(publicProfiles.moderatedAt)));
  const [active] = await ctx.db
    .select({ n: sql<number>`count(*)::int` })
    .from(profileTags)
    .where(and(isNotNull(profileTags.userId), isNull(profileTags.disabledAt)));
  const byBatch = await ctx.db
    .select({
      batch: profileTags.batch,
      total: sql<number>`count(*)::int`,
      active: sql<number>`count(*) filter (where ${profileTags.userId} is not null and ${profileTags.disabledAt} is null)::int`,
    })
    .from(profileTags)
    .groupBy(profileTags.batch)
    .orderBy(desc(sql`min(${profileTags.createdAt})`));
  return { days, to: today, totals, publishedCards: cards?.n ?? 0, activeTags: active?.n ?? 0, series, activationsByBatch: byBatch };
}
