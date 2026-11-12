import { withSentryConfig } from '@sentry/nextjs/config';
import type { NextConfig } from 'next';

const config: NextConfig = {
  output: 'standalone',
  poweredByHeader: false,
  reactStrictMode: true,
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'same-origin' },
        ],
      },
    ];
  },
};

// Error tracking: source maps are uploaded (then not served) only when CI provides SENTRY_AUTH_TOKEN.
export default withSentryConfig(config, {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT_ADMIN ?? 'yaqeen-admin',
  authToken: process.env.SENTRY_AUTH_TOKEN,
  release: { name: `yaqeen-admin@${process.env.GIT_SHA ?? 'dev'}` },
  sourcemaps: { disable: !process.env.SENTRY_AUTH_TOKEN, deleteSourcemapsAfterUpload: true },
  silent: !process.env.CI,
  telemetry: false,
});
