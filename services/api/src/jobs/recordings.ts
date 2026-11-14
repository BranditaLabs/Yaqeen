/**
 * «تلاواتي» sweeper — run every 10 minutes:  pnpm --filter @yaqeen/api job:recordings
 *
 * Retries recordings stuck in `processing` for more than 10 minutes (the API process verifies right
 * after upload; this covers restarts and an ASR service that was down) — after 3 failed attempts a
 * recording goes to the review queue. Also deletes recordings a moderator removed more than 7 days
 * ago, wipes the text of support-removed comments past that window, and drops resolved reports after
 * 180 days. (When the community job lands it can call `sweep` from its own run instead.)
 */
import { Redis } from 'ioredis';
import { loadEnv } from '../config/env.js';
import { createDb } from '../db/client.js';
import { AlAdhanClient } from '../integrations/aladhan.js';
import { asrFromEnv } from '../integrations/asr.js';
import { FcmSender } from '../integrations/fcm.js';
import { quranFoundationFromEnv } from '../integrations/quran-foundation.js';
import { ShopifyClient } from '../integrations/shopify.js';
import { ResponseCache } from '../lib/cache.js';
import { runJob } from '../lib/observability.js';
import { sweep } from '../services/recordings.service.js';
import { withJobLock } from './lock.js';

if (import.meta.url === `file://${process.argv[1]}`) {
  const env = loadEnv();
  const { db, pool } = createDb(env.DATABASE_URL);
  const redis = env.REDIS_URL ? new Redis(env.REDIS_URL) : null;
  const res = await runJob(env, 'yaqeen-recordings', '*/10 * * * *', () =>
    withJobLock(pool, 'recordings-sweep', () =>
      sweep({
        env,
        db,
        redis,
        cache: new ResponseCache(redis),
        aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, redis),
        shopify: new ShopifyClient({ shopDomain: env.SHOPIFY_SHOP_DOMAIN, adminToken: env.SHOPIFY_ADMIN_TOKEN, apiVersion: env.SHOPIFY_API_VERSION }),
        fcm: new FcmSender(env.FIREBASE_SERVICE_ACCOUNT_JSON),
        qf: quranFoundationFromEnv(env),
        asr: asrFromEnv(env),
        now: () => new Date(),
      }),
    ),
  );
  console.log(res.ran ? `[recordings] ${JSON.stringify(res.result)}` : '[recordings] another sweep is running — skipped');
  await pool.end();
  redis?.disconnect();
}
