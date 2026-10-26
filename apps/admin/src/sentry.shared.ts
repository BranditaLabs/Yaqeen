import type { BrowserOptions, ErrorEvent } from '@sentry/nextjs';

/**
 * Admin error events carry no personal data: no user, cookies, bodies or query strings, and only
 * harmless headers. Admin pages show aggregates only (CLAUDE.md rule 2), and nothing else leaves.
 */
export function scrub(event: ErrorEvent): ErrorEvent {
  delete event.user;
  if (event.request) {
    delete event.request.data;
    delete event.request.cookies;
    delete event.request.query_string;
    delete event.request.headers;
    if (event.request.url) event.request.url = event.request.url.split('?')[0];
  }
  return event;
}

/** Shared by server and browser init. Off (no DSN) in local dev and tests. */
export const sentryBase: Pick<BrowserOptions, 'dsn' | 'environment' | 'release' | 'tracesSampleRate' | 'dataCollection' | 'beforeSend'> = {
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN || process.env.SENTRY_DSN,
  environment: process.env.NEXT_PUBLIC_SENTRY_ENVIRONMENT || process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV,
  release: `yaqeen-admin@${process.env.NEXT_PUBLIC_GIT_SHA || process.env.GIT_SHA || 'dev'}`,
  tracesSampleRate: 0,
  dataCollection: { userInfo: false, cookies: false, httpBodies: [], urlQueryParams: false },
  beforeSend: scrub,
};
