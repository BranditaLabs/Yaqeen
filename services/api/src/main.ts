import { Redis } from 'ioredis';
import { buildApp } from './app.js';
import { loadEnv } from './config/env.js';
import { createDb } from './db/client.js';
import { AlAdhanClient } from './integrations/aladhan.js';
import { FcmSender } from './integrations/fcm.js';
import { ShopifyClient } from './integrations/shopify.js';

const env = loadEnv();
const { db, pool } = createDb(env.DATABASE_URL, { max: env.PG_POOL_MAX, statementTimeoutMs: env.PG_STATEMENT_TIMEOUT_MS });
// Redis is optional in local dev (REDIS_URL=""): caching and shared rate limits are then in-memory/off.
const redis = env.REDIS_URL ? new Redis(env.REDIS_URL, { maxRetriesPerRequest: 2, enableOfflineQueue: false }) : null;
redis?.on('error', () => {}); // degraded mode is handled per call; avoid crash on reconnects

let draining = false;
const app = await buildApp({
  env,
  db,
  redis,
  aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, redis),
  shopify: new ShopifyClient({
    shopDomain: env.SHOPIFY_SHOP_DOMAIN,
    adminToken: env.SHOPIFY_ADMIN_TOKEN,
    apiVersion: env.SHOPIFY_API_VERSION,
  }),
  fcm: new FcmSender(env.FIREBASE_SERVICE_ACCOUNT_JSON),
  now: () => new Date(),
  draining: () => draining,
});

/**
 * Zero-downtime shutdown: fail readiness first so the load balancer stops sending new requests,
 * wait for it to notice, then let in-flight requests finish and close connections.
 */
const shutdown = async (signal: string) => {
  if (draining) return;
  draining = true;
  app.log.info({ signal, graceMs: env.SHUTDOWN_GRACE_MS }, 'draining');
  await new Promise((r) => setTimeout(r, env.SHUTDOWN_GRACE_MS));
  await app.close();
  await pool.end();
  redis?.disconnect();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('unhandledRejection', (err) => app.log.error({ err }, 'unhandled rejection'));

await app.listen({ host: '0.0.0.0', port: env.PORT });
