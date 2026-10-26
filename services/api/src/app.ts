import { randomUUID } from 'node:crypto';
import compress from '@fastify/compress';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import underPressure from '@fastify/under-pressure';
import Fastify, { type FastifyInstance } from 'fastify';
import { sql } from 'drizzle-orm';
import type { AppContext } from './context.js';
import { type CacheNamespace, ResponseCache } from './lib/cache.js';
import { errorHandler } from './lib/errors.js';
import { authPlugin } from './plugins/auth.js';
import { adminAuthRoutes } from './routes/admin/auth.routes.js';
import { adminCampaignRoutes } from './routes/admin/campaigns.routes.js';
import { adminContentRoutes } from './routes/admin/content.routes.js';
import { adminOverviewRoutes } from './routes/admin/overview.routes.js';
import { adminRewardsRoutes } from './routes/admin/rewards.routes.js';
import { adminSettingsRoutes } from './routes/admin/settings.routes.js';
import { adminTagsRoutes } from './routes/admin/tags.routes.js';
import { adminUsersRoutes } from './routes/admin/users.routes.js';
import { appRoutes } from './routes/public/app.routes.js';
import { authRoutes } from './routes/public/auth.routes.js';
import { meRoutes } from './routes/public/me.routes.js';
import { profileRoutes } from './routes/public/profile.routes.js';

/** Which public caches an admin write under each prefix can change. */
const INVALIDATES: [string, CacheNamespace[]][] = [
  ['/admin/content', ['content', 'config']], // splash verse is published through content review
  ['/admin/settings', ['config', 'calendar']], // flags, maintenance, Hijri offset
  ['/admin/rewards', ['config', 'catalogue']], // points program, cheapest reward
];

export async function buildApp(input: Omit<AppContext, 'cache'> & { cache?: ResponseCache }): Promise<FastifyInstance> {
  const ctx: AppContext = { ...input, cache: input.cache ?? new ResponseCache(input.redis) };
  const app = Fastify({
    // Correlate logs across the load balancer, API and jobs.
    requestIdHeader: 'x-request-id',
    genReqId: () => randomUUID(),
    // Longer than the load balancer's idle timeout so it never reuses a socket we just closed.
    keepAliveTimeout: 65_000,
    connectionTimeout: 30_000,
    requestTimeout: 30_000,
    logger:
      ctx.env.NODE_ENV === 'test'
        ? false
        : {
            level: ctx.env.LOG_LEVEL,
            // Never log tokens or personal data.
            redact: ['req.headers.authorization', 'req.headers["x-admin-session"]', 'req.body.idToken', 'req.body.password', 'req.body.totp'],
          },
    trustProxy: true,
    bodyLimit: 256 * 1024,
  });

  app.decorate('ctx', ctx);
  app.setErrorHandler(errorHandler);
  app.addHook('onSend', async (req, reply) => {
    reply.header('x-request-id', req.id);
  });
  app.addHook('onResponse', async (req, reply) => {
    if (req.method === 'GET' || reply.statusCode >= 400) return;
    for (const [prefix, namespaces] of INVALIDATES) {
      if (req.url.startsWith(prefix)) for (const ns of namespaces) await ctx.cache.bumpNamespace(ns);
    }
  });

  // Shed load instead of falling over when a spike saturates the event loop (503 + Retry-After;
  // the app's outbox retries later). Health/readiness are reported separately.
  if (ctx.env.NODE_ENV !== 'test') {
    await app.register(underPressure, {
      maxEventLoopDelay: ctx.env.MAX_EVENT_LOOP_DELAY_MS,
      maxEventLoopUtilization: 0.98,
      retryAfter: 10,
      exposeStatusRoute: false,
    });
  }
  await app.register(compress, { global: true, threshold: 1024, encodings: ['br', 'gzip'] });

  await app.register(helmet);
  await app.register(cors, { origin: ctx.env.CORS_ORIGINS.length ? ctx.env.CORS_ORIGINS : false, credentials: true });
  await app.register(rateLimit, {
    global: true,
    max: ctx.env.RATE_LIMIT_PER_MIN,
    timeWindow: '1 minute',
    // Many users share one carrier-grade NAT IP in Egypt: key signed-in traffic by token, not IP.
    keyGenerator: (req) => {
      const auth = req.headers.authorization;
      return auth?.startsWith('Bearer ') ? `t:${auth.slice(-24)}` : `ip:${req.ip}`;
    },
    ...(ctx.redis ? { redis: ctx.redis, skipOnError: true } : {}),
  });
  await app.register(authPlugin, { jwtSecret: ctx.env.JWT_SECRET, adminJwtSecret: ctx.env.ADMIN_JWT_SECRET });

  app.get('/health', async () => ({ ok: true }));
  app.get('/ready', async (_req, reply) => {
    if (ctx.draining?.()) return reply.status(503).send({ ok: false, draining: true });
    try {
      await ctx.db.execute(sql`select 1`);
      if (ctx.redis) await ctx.redis.ping();
      return { ok: true };
    } catch {
      return reply.status(503).send({ ok: false });
    }
  });

  // Public app API
  await app.register(authRoutes, { prefix: '/v1/auth' });
  await app.register(meRoutes, { prefix: '/v1/me' });
  await app.register(appRoutes, { prefix: '/v1' });
  await app.register(profileRoutes);

  // Admin API (separate token audience + RBAC on every route)
  await app.register(adminAuthRoutes, { prefix: '/admin/auth' });
  await app.register(adminOverviewRoutes, { prefix: '/admin/overview' });
  await app.register(adminUsersRoutes, { prefix: '/admin/users' });
  await app.register(adminContentRoutes, { prefix: '/admin/content' });
  await app.register(adminCampaignRoutes, { prefix: '/admin/campaigns' });
  await app.register(adminRewardsRoutes, { prefix: '/admin/rewards' });
  await app.register(adminSettingsRoutes, { prefix: '/admin/settings' });
  await app.register(adminTagsRoutes, { prefix: '/admin/tags' });

  return app;
}
