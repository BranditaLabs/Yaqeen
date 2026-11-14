/**
 * Prometheus metrics for operations: request rate/latency/errors by route template, cache
 * behaviour, Postgres pool, load shedding, plus Node defaults. Served on METRICS_PORT (cluster
 * internal, never through the ingress). Labels are route templates and status codes only — no
 * user, handle or worship data.
 */
import { createServer, type Server } from 'node:http';
import type pg from 'pg';
import { Counter, collectDefaultMetrics, Gauge, Histogram, Registry } from 'prom-client';

export const registry = new Registry();
registry.setDefaultLabels({ service: 'yaqeen-api' });
let defaults = false;

export const httpDuration = new Histogram({
  name: 'yaqeen_http_request_duration_seconds',
  help: 'HTTP request duration by route template and status',
  labelNames: ['method', 'route', 'status'] as const,
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [registry],
});

export const cacheLookups = new Counter({
  name: 'yaqeen_cache_lookups_total',
  help: 'Response cache lookups by namespace and result (l1, l2, miss)',
  labelNames: ['namespace', 'result'] as const,
  registers: [registry],
});

export const externalCalls = new Counter({
  name: 'yaqeen_external_calls_total',
  help: 'Calls to external services by service and outcome',
  labelNames: ['service', 'outcome'] as const,
  registers: [registry],
});

export const productEventsIngested = new Counter({
  name: 'yaqeen_product_events_total',
  help: 'Consented product analytics events accepted, by event name',
  labelNames: ['event'] as const,
  registers: [registry],
});

export const conversionSendsTotal = new Counter({
  name: 'yaqeen_conversions_total',
  help: 'Server-side purchase conversions by ad platform and outcome (sent, failed, duplicate)',
  labelNames: ['platform', 'outcome'] as const,
  registers: [registry],
});

export function startDefaultMetrics() {
  if (defaults) return;
  defaults = true;
  collectDefaultMetrics({ register: registry, prefix: 'yaqeen_' });
}

export function registerPoolMetrics(pool: pg.Pool) {
  const g = (name: string, help: string, read: () => number) =>
    new Gauge({ name, help, registers: [registry], collect() { this.set(read()); } });
  g('yaqeen_pg_pool_total', 'Postgres pool connections', () => pool.totalCount);
  g('yaqeen_pg_pool_idle', 'Idle Postgres pool connections', () => pool.idleCount);
  g('yaqeen_pg_pool_waiting', 'Requests waiting for a Postgres connection', () => pool.waitingCount);
}

/**
 * Community job health, computed from the database at scrape time and cached 60 s:
 *   yaqeen_league_weeks_overdue           open weeks more than 2 h past their end
 *   yaqeen_tournaments_overdue            published tournaments more than 2 h past their end, not closed
 *   yaqeen_community_snapshot_age_hours   hours since the last nightly snapshot (-1 before the first)
 * Idempotent: buildApp may run many times (tests); the gauges read the latest pool.
 */
type Queryable = { query: <R extends Record<string, unknown>>(text: string) => Promise<{ rows: R[] }> };
let communitySource: Queryable | null = null;
let communityCache: { at: number; weeks: number; tournaments: number; age: number } | null = null;

async function communityHealth() {
  if (!communitySource) return null;
  if (communityCache && Date.now() - communityCache.at < 60_000) return communityCache;
  try {
    const { rows } = await communitySource.query<{ weeks: number; tournaments: number; age: number | null }>(`
      select
        (select count(*) from league_weeks where status = 'open' and ends_at < now() - interval '2 hours')::int as weeks,
        (select count(*) from tournaments where status = 'published' and closed_at is null and ends_at < now() - interval '2 hours')::int as tournaments,
        (select extract(epoch from now() - max(taken_at)) / 3600 from community_snapshot_days)::float8 as age`);
    const r = rows[0];
    communityCache = { at: Date.now(), weeks: Number(r?.weeks ?? 0), tournaments: Number(r?.tournaments ?? 0), age: r?.age === null || r?.age === undefined ? -1 : Number(r.age) };
  } catch {
    // keep the last values; a scrape must never fail on the database
  }
  return communityCache;
}

let communityGauges = false;
export function registerCommunityMetrics(pool: Queryable) {
  communitySource = pool;
  if (communityGauges) return;
  communityGauges = true;
  const g = (name: string, help: string, pick: (h: NonNullable<typeof communityCache>) => number) =>
    new Gauge({
      name,
      help,
      registers: [registry],
      async collect() {
        const h = await communityHealth();
        if (h) this.set(pick(h));
      },
    });
  g('yaqeen_league_weeks_overdue', 'League weeks still open more than 2 h after they ended', (h) => h.weeks);
  g('yaqeen_tournaments_overdue', 'Published tournaments not closed more than 2 h after they ended', (h) => h.tournaments);
  g('yaqeen_community_snapshot_age_hours', 'Hours since the last nightly community snapshot (-1 = none yet)', (h) => h.age);
}

/** A tiny HTTP server for Prometheus scrapes (`GET /metrics`). */
export function serveMetrics(port: number): Server {
  const server = createServer(async (req, res) => {
    if (req.url !== '/metrics') {
      res.writeHead(404).end();
      return;
    }
    res.writeHead(200, { 'content-type': registry.contentType });
    res.end(await registry.metrics());
  });
  server.listen(port, '0.0.0.0');
  return server;
}
