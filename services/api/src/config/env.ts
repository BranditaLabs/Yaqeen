import { z } from 'zod';

/** Comma-separated list, with an optional default (zod 4 skips transforms on `.default`, so it goes before). */
const csvOf = (fallback = '') =>
  z
    .string()
    .default(fallback)
    .transform((s) =>
      s
        .split(',')
        .map((x) => x.trim())
        .filter(Boolean),
    );
const csv = csvOf();

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().default(4000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  DATABASE_URL: z.string().url().default('postgres://yaqeen:yaqeen@localhost:5432/yaqeen'),
  REDIS_URL: z.string().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(32).default('dev-only-secret-change-me-dev-only-secret'),
  ADMIN_JWT_SECRET: z.string().min(32).default('dev-only-admin-secret-change-me-dev-only'),
  /** 32 random bytes, base64 — seals admin TOTP secrets at rest (AES-256-GCM). Keep it in the secret manager. */
  ADMIN_SECRETS_KEY: z.string().default(''),
  /** 32 random bytes, base64 — seals the users' opt-in cloud backups at rest (AES-256-GCM). A separate key from ADMIN_SECRETS_KEY. */
  BACKUP_SECRETS_KEY: z.string().default(''),
  CORS_ORIGINS: csv,
  /**
   * Google audiences: the Web client (the app's server client id — Android tokens) and the iOS client
   * of Firebase project `yaqeen-eg`. Client ids are public (they ship in every app build), not secrets.
   */
  GOOGLE_CLIENT_IDS: csvOf(
    '215304787392-2papc2vde7pj9j6uh7u6pgdsokff8gen.apps.googleusercontent.com,' +
      '215304787392-25qvm0s481ebaeoa7213qkk9b1l2bqm5.apps.googleusercontent.com',
  ),
  /** Apple audiences: the iOS bundle id and the Services ID used by the Android web flow. */
  APPLE_CLIENT_IDS: csvOf('com.yaqinbrand.yaqeen,com.yaqinbrand.yaqeen.signin'),
  /** Android package that Sign in with Apple's web callback returns to. */
  ANDROID_APP_ID: z.string().regex(/^[a-zA-Z][\w.]+$/).default('com.yaqinbrand.yaqeen'),
  SHOPIFY_SHOP_DOMAIN: z.string().default(''),
  SHOPIFY_ADMIN_TOKEN: z.string().default(''),
  SHOPIFY_API_VERSION: z.string().default('2025-10'),
  /** Signing secret of the shop's orders/paid webhook (Settings → Notifications → Webhooks). Empty = webhook off. */
  SHOPIFY_WEBHOOK_SECRET: z.string().default(''),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().default(''),
  ALADHAN_BASE_URL: z.string().url().default('https://api.aladhan.com/v1'),
  HIJRI_REGION: z.string().default('EG'),
  // Quran.com / Quran Foundation Content API (reciters' audio + timings, tafsir — spec §10). Server
  // only: OAuth2 client_credentials from the QF Developer Console. Without credentials the API uses
  // the legacy unauthenticated base below (empty = off → content routes answer 503 content_unavailable).
  QF_CLIENT_ID: z.string().default(''),
  QF_CLIENT_SECRET: z.string().default(''),
  QF_ENV: z.enum(['production', 'prelive']).default('production'),
  QF_PUBLIC_BASE_URL: z.union([z.literal(''), z.string().url()]).default('https://api.quran.com/api/v4'),
  // Public profile cards (NFC/QR): the host that serves /u/<handle> (point a vanity domain here),
  // the store and the app-store links its CTA opens.
  PUBLIC_PROFILE_BASE_URL: z.string().url().default('https://api.yaqin-brand.com'),
  STORE_URL: z.string().url().default('https://www.yaqin-brand.com'),
  PLAY_STORE_URL: z.string().url().default('https://play.google.com/store/apps/details?id=com.yaqinbrand.yaqeen'),
  /** Empty until the App Store listing exists; iPhone visitors then go to the store site. */
  APP_STORE_URL: z.string().default(''),
  /** Shown on the website's help, privacy and deletion pages ('' = a visible placeholder). */
  SUPPORT_EMAIL: z.string().default(''),

  /* Observability — all optional; empty = off. */
  /** Sentry project DSN (errors; traces only when SENTRY_TRACES_SAMPLE_RATE > 0). */
  SENTRY_DSN: z.string().default(''),
  SENTRY_ENVIRONMENT: z.string().default(''),
  SENTRY_TRACES_SAMPLE_RATE: z.coerce.number().min(0).max(1).default(0),
  /** The commit this build came from (set by CI in the image); the Sentry release. */
  GIT_SHA: z.string().default('dev'),
  /** Prometheus metrics on a separate, cluster-internal port (0 = off). */
  METRICS_PORT: z.coerce.number().int().min(0).max(65535).default(0),
  /** PostHog project key (EU cloud) — consented product events are forwarded server-side when set. */
  POSTHOG_KEY: z.string().default(''),
  POSTHOG_HOST: z.string().url().default('https://eu.i.posthog.com'),

  /*
   * Server-side `purchase` conversions (orders/paid with a Yaqeen code, `ads_measurement` consent,
   * flag `serverConversions`). Each platform is on only when its credentials are set; nothing is
   * sent without CONVERSIONS_ID_SALT. See docs/ANALYTICS_EVENTS.md › Server-side purchase.
   */
  /** Secret salt for the pseudonymous external id (openssl rand -base64 32). Never rotate casually: ids change. */
  CONVERSIONS_ID_SALT: z.string().default(''),
  META_PIXEL_ID: z.string().default(''),
  /** Conversions API access token (Events Manager → the pixel → Settings → Generate access token). */
  META_CAPI_TOKEN: z.string().default(''),
  /** Optional: route events to Events Manager → Test events while verifying the setup. */
  META_TEST_EVENT_CODE: z.string().default(''),
  GA4_MEASUREMENT_ID: z.string().default(''),
  /** Measurement Protocol API secret (GA4 → Admin → Data streams → the stream → Measurement Protocol API secrets). */
  GA4_API_SECRET: z.string().default(''),
  TIKTOK_PIXEL_ID: z.string().default(''),
  /** Events API access token (TikTok Events Manager → the pixel → Settings → Generate access token). */
  TIKTOK_ACCESS_TOKEN: z.string().default(''),
  /** Optional: TikTok Events Manager → Test events code while verifying the setup. */
  TIKTOK_TEST_EVENT_CODE: z.string().default(''),

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
  if (env.NODE_ENV === 'production' && !env.ADMIN_SECRETS_KEY) {
    throw new Error('ADMIN_SECRETS_KEY must be set in production (openssl rand -base64 32)');
  }
  if (env.NODE_ENV === 'production' && !env.BACKUP_SECRETS_KEY) {
    throw new Error('BACKUP_SECRETS_KEY must be set in production (openssl rand -base64 32)');
  }
  return env;
}
