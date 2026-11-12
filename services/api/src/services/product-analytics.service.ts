/**
 * Product analytics («تحسين التطبيق»): consented, closed-list events from the app, stored without
 * any account link and shown to admins as aggregates. Optionally forwarded to PostHog (EU) server-side
 * — the app talks only to our API, so turning PostHog off is a config change, not an app release.
 *
 * Guarantees (tested):
 *  - nothing is stored or forwarded unless the signed-in user granted `product_analytics`;
 *  - only `PRODUCT_EVENTS` with allowed property values pass — worship activity can't be expressed;
 *  - rows carry a random per-install id, never the user id; kept RETENTION_DAYS;
 *  - reports withhold any count under K_MIN.
 */
import { and, eq, lt, sql } from 'drizzle-orm';
import { isProductEvent, type ProductAnalyticsReport, type ProductEventsBatch, validProductProps } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import type { Db } from '../db/client.js';
import { consents, productEvents } from '../db/schema.js';
import { addDays, localToday } from '../domain/points.js';
import { externalCalls, productEventsIngested } from '../lib/metrics.js';

export const RETENTION_DAYS = 180;
export const K_MIN = 20;

const ONBOARDING_ORDER = ['welcome', 'language', 'prayer', 'consent', 'goal', 'routine', 'download'];

export async function hasConsent(ctx: AppContext, uid: string): Promise<boolean> {
  const [row] = await ctx.db
    .select({ granted: consents.granted })
    .from(consents)
    .where(and(eq(consents.userId, uid), eq(consents.kind, 'product_analytics')));
  return row?.granted === true;
}

/** Stores the valid events of a batch; returns how many were accepted. */
export async function ingest(ctx: AppContext, uid: string, batch: ProductEventsBatch): Promise<number> {
  if (!(await hasConsent(ctx, uid))) return 0;
  const now = ctx.now().getTime();
  const rows = batch.events
    .filter((e) => isProductEvent(e.name) && validProductProps(e.name, e.props))
    .map((e) => {
      // Phones' clocks drift and queues replay: keep the event time only when plausible.
      const t = Date.parse(e.at);
      const at = Number.isFinite(t) && t > now - 7 * 86_400_000 && t < now + 3_600_000 ? new Date(t) : new Date(now);
      return {
        anonId: batch.anonId,
        name: e.name,
        props: e.props,
        platform: batch.platform,
        appVersion: batch.appVersion,
        locale: batch.locale,
        occurredAt: at,
      };
    });
  if (!rows.length) return 0;
  await ctx.db.insert(productEvents).values(rows);
  for (const r of rows) productEventsIngested.inc({ event: r.name });
  if (ctx.env.POSTHOG_KEY) void forwardToPostHog(ctx, rows);
  return rows.length;
}

/** Server-side capture to PostHog: no IP, no GeoIP, no person profiles — the anon id is the only key. */
async function forwardToPostHog(ctx: AppContext, rows: { anonId: string; name: string; props: Record<string, string>; platform: string; appVersion: string; locale: string; occurredAt: Date }[]) {
  try {
    const res = await fetch(`${ctx.env.POSTHOG_HOST.replace(/\/$/, '')}/batch/`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        api_key: ctx.env.POSTHOG_KEY,
        batch: rows.map((r) => ({
          event: r.name,
          distinct_id: r.anonId,
          timestamp: r.occurredAt.toISOString(),
          properties: {
            ...r.props,
            platform: r.platform,
            app_version: r.appVersion,
            locale: r.locale,
            $lib: 'yaqeen-api',
            $ip: null,
            $geoip_disable: true,
            $process_person_profile: false,
          },
        })),
      }),
      signal: AbortSignal.timeout(5_000),
    });
    externalCalls.inc({ service: 'posthog', outcome: res.ok ? 'ok' : 'error' });
  } catch {
    externalCalls.inc({ service: 'posthog', outcome: 'error' });
  }
}

/** Retention: delete events older than RETENTION_DAYS. */
export async function purgeOld(db: Db, now: Date): Promise<number> {
  const cutoff = new Date(now.getTime() - RETENTION_DAYS * 86_400_000);
  const rows = await db.delete(productEvents).where(lt(productEvents.occurredAt, cutoff)).returning({ id: productEvents.id });
  return rows.length;
}

const k = (n: number | string | null | undefined) => {
  const v = Number(n ?? 0);
  return v < K_MIN ? null : v;
};

export async function report(ctx: AppContext, days: number): Promise<ProductAnalyticsReport> {
  const to = localToday(ctx.now());
  const from = addDays(to, -(days - 1));
  const day = sql`(${productEvents.occurredAt} at time zone 'Africa/Cairo')::date`;
  const inRange = sql`${day} between ${from}::date and ${to}::date`;
  const db = ctx.db;

  const active = await db
    .select({ date: sql<string>`${day}::text`, value: sql<number>`count(distinct ${productEvents.anonId})::int` })
    .from(productEvents)
    .where(inRange)
    .groupBy(day)
    .orderBy(day);
  const byDate = new Map(active.map((r) => [r.date, r.value]));
  const activeInstalls = Array.from({ length: days }, (_, i) => {
    const d = addDays(from, i);
    return { date: d, value: k(byDate.get(d) ?? 0) };
  });

  const events = await db
    .select({ name: productEvents.name, total: sql<number>`count(*)::int`, installs: sql<number>`count(distinct ${productEvents.anonId})::int` })
    .from(productEvents)
    .where(inRange)
    .groupBy(productEvents.name)
    .orderBy(sql`count(*) desc`);

  const steps = await db
    .select({ step: sql<string>`${productEvents.props}->>'step'`, installs: sql<number>`count(distinct ${productEvents.anonId})::int` })
    .from(productEvents)
    .where(and(inRange, eq(productEvents.name, 'onboarding_step')))
    .groupBy(sql`${productEvents.props}->>'step'`);
  const [done] = await db
    .select({ installs: sql<number>`count(distinct ${productEvents.anonId})::int` })
    .from(productEvents)
    .where(and(inRange, eq(productEvents.name, 'onboarding_complete')));
  const stepMap = new Map(steps.map((s) => [s.step, s.installs]));
  const onboardingFunnel = [
    ...ONBOARDING_ORDER.filter((s) => stepMap.has(s)).map((s) => ({ step: s, installs: k(stepMap.get(s)) })),
    { step: 'complete', installs: k(done?.installs) },
  ];

  // Weekly cohorts by first-seen week; share of the cohort active in weeks 1..4 after it.
  const cohortRows = await db.execute<{ cohort: string; size: number; w1: number; w2: number; w3: number; w4: number }>(sql`
    with firsts as (
      select anon_id, date_trunc('week', min(occurred_at at time zone 'Africa/Cairo')) as cohort
      from ${productEvents} group by anon_id
    ), activity as (
      select distinct anon_id, date_trunc('week', occurred_at at time zone 'Africa/Cairo') as week from ${productEvents}
    )
    select to_char(f.cohort, 'YYYY-MM-DD') as cohort, count(distinct f.anon_id)::int as size,
      count(distinct a.anon_id) filter (where a.week = f.cohort + interval '1 week')::int as w1,
      count(distinct a.anon_id) filter (where a.week = f.cohort + interval '2 weeks')::int as w2,
      count(distinct a.anon_id) filter (where a.week = f.cohort + interval '3 weeks')::int as w3,
      count(distinct a.anon_id) filter (where a.week = f.cohort + interval '4 weeks')::int as w4
    from firsts f left join activity a on a.anon_id = f.anon_id
    where f.cohort >= ${from}::date - interval '28 days'
    group by f.cohort order by f.cohort`);
  const retention = cohortRows.rows.map((r) => {
    const size = Number(r.size);
    const ok = size >= K_MIN;
    return { cohort: r.cohort, size: ok ? size : null, weeks: [r.w1, r.w2, r.w3, r.w4].map((w) => (ok ? Math.round((Number(w) / size) * 1000) / 10 : null)) };
  });

  const split = async (col: typeof productEvents.platform | typeof productEvents.appVersion) =>
    db
      .select({ key: col, installs: sql<number>`count(distinct ${productEvents.anonId})::int` })
      .from(productEvents)
      .where(inRange)
      .groupBy(col)
      .orderBy(sql`count(distinct ${productEvents.anonId}) desc`)
      .limit(10);
  const platforms = (await split(productEvents.platform)).map((r) => ({ platform: r.key, installs: k(r.installs) }));
  const versions = (await split(productEvents.appVersion)).map((r) => ({ version: r.key, installs: k(r.installs) }));

  return {
    days,
    to,
    activeInstalls,
    events: events.map((e) => ({ name: e.name, total: k(e.total), installs: k(e.installs) })),
    onboardingFunnel,
    retention,
    platforms,
    versions,
  };
}
