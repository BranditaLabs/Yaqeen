import * as Sentry from '@sentry/nextjs';
import { sentryBase } from './sentry.shared';

if (sentryBase.dsn) {
  // No session replay, no tracing: errors only.
  Sentry.init(sentryBase);
}

export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
