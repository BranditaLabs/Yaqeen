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
