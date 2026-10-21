import type { Redis } from 'ioredis';
import type { Env } from './config/env.js';
import type { Db } from './db/client.js';
import type { AlAdhanClient } from './integrations/aladhan.js';
import type { FcmSender } from './integrations/fcm.js';
import type { ShopifyClient } from './integrations/shopify.js';

/** Everything a route needs, injected once (makes tests and jobs easy to wire). */
export interface AppContext {
  env: Env;
  db: Db;
  redis: Redis | null;
  aladhan: AlAdhanClient;
  shopify: ShopifyClient;
  fcm: FcmSender;
  /** Injectable clock for tests. */
  now: () => Date;
}

declare module 'fastify' {
  interface FastifyInstance {
    ctx: AppContext;
  }
}
