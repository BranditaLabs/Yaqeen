import * as Sentry from '@sentry/nextjs';

export async function register() {
  const { sentryBase } = await import('./sentry.shared');
  if (!sentryBase.dsn) return;
  Sentry.init(sentryBase);
}

// Server component / route handler / server action errors.
export const onRequestError = Sentry.captureRequestError;
