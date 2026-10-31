import type { Redis } from 'ioredis';
import type { Env } from './config/env.js';
import type { Db } from './db/client.js';
import type { AlAdhanClient } from './integrations/aladhan.js';
import type { FcmSender } from './integrations/fcm.js';
import type { QuranFoundationClient } from './integrations/quran-foundation.js';
import type { ShopifyClient } from './integrations/shopify.js';
import type { ResponseCache } from './lib/cache.js';

/** Everything a route needs, injected once (makes tests and jobs easy to wire). */
export interface AppContext {
  env: Env;
  db: Db;
  redis: Redis | null;
  aladhan: AlAdhanClient;
  shopify: ShopifyClient;
  fcm: FcmSender;
  /** Quran.com / Quran Foundation content (audio, timings, tafsir). Created from env by buildApp when not given. */
  qf: QuranFoundationClient;
  /** Hot public responses (L1 memory + L2 Redis). Created by buildApp when not given. */
  cache: ResponseCache;
  /** Injectable clock for tests. */
  now: () => Date;
  /** True while shutting down: readiness fails so the load balancer stops routing here. */
  draining?: () => boolean;
}

declare module 'fastify' {
  interface FastifyInstance {
    ctx: AppContext;
  }
}
