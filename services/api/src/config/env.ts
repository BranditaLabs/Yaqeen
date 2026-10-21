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
