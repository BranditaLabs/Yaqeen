import { defineConfig, devices } from '@playwright/test';

// Real API (Postgres, no Redis) and the production admin build, on their own ports so a dev stack
// can keep running. Run `pnpm --filter @yaqeen/admin build` first; `pnpm --filter @yaqeen/e2e e2e`
// resets the e2e database and runs everything.
const API = 'http://localhost:4100';
const ADMIN = 'http://localhost:3100'; // the session cookie is set for this host
const DATABASE_URL = process.env.E2E_DATABASE_URL ?? 'postgres://yq:yq@127.0.0.1:5432/yqe2e';
// In a cloud container the browsers are pre-installed outside the default cache.
const executablePath = process.env.E2E_CHROMIUM_PATH || undefined;

export default defineConfig({
  testDir: 'tests',
  fullyParallel: false, // one admin session, one database
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    locale: 'ar-EG',
    launchOptions: { executablePath },
  },
  projects: [
    { name: 'setup', testMatch: /admin\.setup\.ts/, use: { baseURL: ADMIN, launchOptions: { executablePath } } },
    { name: 'public', testMatch: /public\.spec\.ts/, use: { ...devices['Pixel 7'], baseURL: API, launchOptions: { executablePath } } },
    {
      name: 'admin',
      testMatch: /admin\.spec\.ts/,
      dependencies: ['setup'],
      use: { ...devices['Desktop Chrome'], baseURL: ADMIN, storageState: '.auth/admin.json', launchOptions: { executablePath } },
    },
  ],
  webServer: [
    {
      command: 'pnpm --filter @yaqeen/api exec tsx src/main.ts',
      url: `${API}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      env: { DATABASE_URL, REDIS_URL: '', PORT: '4100', NODE_ENV: 'development', PUBLIC_PROFILE_BASE_URL: API, LOG_LEVEL: 'warn' },
    },
    {
      // The admin builds as Next standalone (like its Docker image): copy the static assets in, then run it.
      command: 'node scripts/start-admin.mjs',
      url: `${ADMIN}/login`,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      env: { API_URL: API, PORT: '3100', HOSTNAME: 'localhost', NEXT_TELEMETRY_DISABLED: '1' },
    },
  ],
});
