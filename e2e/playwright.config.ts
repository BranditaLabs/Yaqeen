import { defineConfig, devices } from '@playwright/test';

// Real API (Postgres, no Redis) and the production admin build, on their own ports so a dev stack
// can keep running. Run `pnpm --filter @yaqeen/admin build` first; `pnpm --filter @yaqeen/e2e e2e`
// resets the e2e database and runs everything.
// Ports can move (E2E_API_PORT / E2E_ADMIN_PORT) so two checkouts can run the suite side by side.
const API_PORT = process.env.E2E_API_PORT ?? '4100';
const ADMIN_PORT = process.env.E2E_ADMIN_PORT ?? '3100';
const API = `http://localhost:${API_PORT}`;
const ADMIN = `http://localhost:${ADMIN_PORT}`; // the session cookie is set for this host
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
    {
      // «التلاوات» moderation queue (after the admin specs: it changes queue state).
      name: 'recitations',
      testMatch: /recitations\.spec\.ts/,
      dependencies: ['admin'],
      use: { ...devices['Desktop Chrome'], baseURL: ADMIN, storageState: '.auth/admin.json', launchOptions: { executablePath } },
    },
    {
      // Public card pages after the admin's moderation (a hidden photo must stop being served).
      name: 'cards',
      testMatch: /cards\.spec\.ts/,
      dependencies: ['admin'],
      use: { ...devices['Pixel 7'], baseURL: API, launchOptions: { executablePath } },
    },
  ],
  webServer: [
    {
      command: 'pnpm --filter @yaqeen/api exec tsx src/main.ts',
      url: `${API}/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      env: { DATABASE_URL, REDIS_URL: '', PORT: API_PORT, NODE_ENV: 'development', PUBLIC_PROFILE_BASE_URL: API, LOG_LEVEL: 'warn' },
    },
    {
      // The admin builds as Next standalone (like its Docker image): copy the static assets in, then run it.
      command: 'node scripts/start-admin.mjs',
      url: `${ADMIN}/login`,
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
      env: { API_URL: API, PORT: ADMIN_PORT, HOSTNAME: 'localhost', NEXT_TELEMETRY_DISABLED: '1' },
    },
  ],
});
