/**
 * Error tracking (Sentry) for the API and jobs. Off unless SENTRY_DSN is set.
 *
 * Privacy: events carry no personal data — no user, no request body, no cookies or auth headers,
 * no query strings, and URLs are reduced to the route template (`/u/:handle`, not the handle).
 * Worship detail never appears: bodies are dropped and route templates name no activity.
 */
import * as Sentry from '@sentry/node';
import type { Env } from '../config/env.js';

let enabled = false;

const KEEP_HEADERS = new Set(['user-agent', 'x-request-id', 'content-type']);

export function scrubEvent<T extends Sentry.ErrorEvent>(event: T): T {
  delete event.user;
  if (event.request) {
    delete event.request.data;
    delete event.request.cookies;
    delete event.request.query_string;
    if (event.request.headers) {
      event.request.headers = Object.fromEntries(Object.entries(event.request.headers).filter(([k]) => KEEP_HEADERS.has(k.toLowerCase())));
    }
    const route = event.tags?.route;
    if (typeof route === 'string' && event.request.url) {
      try {
        event.request.url = new URL(route, event.request.url).toString();
      } catch {
        event.request.url = route;
      }
    } else if (event.request.url) {
      event.request.url = event.request.url.split('?')[0];
    }
  }
  if (event.breadcrumbs) {
    event.breadcrumbs = event.breadcrumbs.filter((b) => b.category !== 'console').map((b) => ({ ...b, data: undefined }));
  }
  return event;
}

export function initSentry(env: Env, component: 'api' | 'job'): void {
  if (!env.SENTRY_DSN || enabled) return;
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.SENTRY_ENVIRONMENT || env.NODE_ENV,
    release: `yaqeen-api@${env.GIT_SHA}`,
    // Collect as little as possible; beforeSend scrubs whatever slips through.
    dataCollection: {
      userInfo: false,
      cookies: false,
      httpHeaders: { request: { allow: ['user-agent', 'x-request-id', 'content-type'] }, response: false },
      httpBodies: [],
      urlQueryParams: false,
      databaseQueryData: false,
      stackFrameVariables: false,
    },
    tracesSampleRate: env.SENTRY_TRACES_SAMPLE_RATE,
    initialScope: { tags: { component } },
    beforeSend: (event) => scrubEvent(event),
    beforeSendTransaction: (event) => {
      delete event.user;
      if (event.request) {
        delete event.request.data;
        delete event.request.cookies;
        delete event.request.query_string;
        delete event.request.headers;
      }
      return event;
    },
  });
  enabled = true;
}

/** Report an unexpected error with its route template and request id (never the body). */
export function captureError(err: unknown, context: { route?: string; requestId?: string; job?: string } = {}): void {
  if (!enabled) return;
  Sentry.withScope((scope) => {
    if (context.route) scope.setTag('route', context.route);
    if (context.requestId) scope.setTag('request_id', context.requestId);
    if (context.job) scope.setTag('job', context.job);
    Sentry.captureException(err);
  });
}

/**
 * Run a cron job under a Sentry cron monitor (missed / failed runs alert) and report its error.
 * Without a DSN it just runs.
 */
export async function runJob<T>(env: Env, slug: string, schedule: string, fn: () => Promise<T>): Promise<T> {
  initSentry(env, 'job');
  if (!enabled) return fn();
  try {
    return await Sentry.withMonitor(slug, fn, { schedule: { type: 'crontab', value: schedule }, checkinMargin: 5, maxRuntime: 15, timezone: 'Etc/UTC' });
  } catch (err) {
    captureError(err, { job: slug });
    throw err;
  } finally {
    await Sentry.flush(5000);
  }
}

export const flushErrors = (ms = 5000) => (enabled ? Sentry.flush(ms) : Promise.resolve(true));
