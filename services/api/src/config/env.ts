import { z } from 'zod';

const csv = z
  .string()
  .default('')
  .transform((s) =>
    s
      .split(',')
      .map((x) => x.trim())
      .filter(Boolean),
  );

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().default(4000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  DATABASE_URL: z.string().url().default('postgres://yaqeen:yaqeen@localhost:5432/yaqeen'),
  REDIS_URL: z.string().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(32).default('dev-only-secret-change-me-dev-only-secret'),
  ADMIN_JWT_SECRET: z.string().min(32).default('dev-only-admin-secret-change-me-dev-only'),
  CORS_ORIGINS: csv,
  GOOGLE_CLIENT_IDS: csv,
  APPLE_CLIENT_IDS: csv,
  SHOPIFY_SHOP_DOMAIN: z.string().default(''),
  SHOPIFY_ADMIN_TOKEN: z.string().default(''),
  SHOPIFY_API_VERSION: z.string().default('2025-10'),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().default(''),
  ALADHAN_BASE_URL: z.string().url().default('https://api.aladhan.com/v1'),
  HIJRI_REGION: z.string().default('EG'),
  // Public profile cards (NFC/QR): the host that serves /u/<handle> (point a vanity domain here),
  // the store and the app-store links its CTA opens.
  PUBLIC_PROFILE_BASE_URL: z.string().url().default('https://api.yaqin-brand.com'),
  STORE_URL: z.string().url().default('https://www.yaqin-brand.com'),
  PLAY_STORE_URL: z.string().url().default('https://play.google.com/store/apps/details?id=com.yaqinbrand.yaqeen'),
  /** Empty until the App Store listing exists; iPhone visitors then go to the store site. */
  APP_STORE_URL: z.string().default(''),
  // Capacity / resilience (tune per environment; see docs/OPERATIONS.md)
  PG_POOL_MAX: z.coerce.number().int().min(1).max(200).default(20),
  PG_STATEMENT_TIMEOUT_MS: z.coerce.number().int().min(1000).default(10_000),
  RATE_LIMIT_PER_MIN: z.coerce.number().int().min(10).default(300),
  MAX_EVENT_LOOP_DELAY_MS: z.coerce.number().int().min(50).default(1000),
  SHUTDOWN_GRACE_MS: z.coerce.number().int().min(0).default(10_000),
});

export type Env = z.infer<typeof EnvSchema>;

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = EnvSchema.safeParse(source);
  if (!parsed.success) {
    throw new Error(`Invalid environment:\n${z.prettifyError(parsed.error)}`);
  }
  const env = parsed.data;
  if (env.NODE_ENV === 'production' && env.JWT_SECRET.startsWith('dev-only')) {
    throw new Error('JWT_SECRET must be set in production');
  }
  if (env.NODE_ENV === 'production' && env.ADMIN_JWT_SECRET.startsWith('dev-only')) {
    throw new Error('ADMIN_JWT_SECRET must be set in production');
  }
  return env;
}
