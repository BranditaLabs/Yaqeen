import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import { sql } from 'drizzle-orm';
import type { AppContext } from './context.js';
import { errorHandler } from './lib/errors.js';
import { authPlugin } from './plugins/auth.js';
import { adminAuthRoutes } from './routes/admin/auth.routes.js';
import { adminCampaignRoutes } from './routes/admin/campaigns.routes.js';
import { adminContentRoutes } from './routes/admin/content.routes.js';
import { adminOverviewRoutes } from './routes/admin/overview.routes.js';
import { adminRewardsRoutes } from './routes/admin/rewards.routes.js';
import { adminSettingsRoutes } from './routes/admin/settings.routes.js';
import { adminUsersRoutes } from './routes/admin/users.routes.js';
import { appRoutes } from './routes/public/app.routes.js';
import { authRoutes } from './routes/public/auth.routes.js';
import { meRoutes } from './routes/public/me.routes.js';

export async function buildApp(ctx: AppContext): Promise<FastifyInstance> {
  const app = Fastify({
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

  await app.register(helmet);
  await app.register(cors, { origin: ctx.env.CORS_ORIGINS.length ? ctx.env.CORS_ORIGINS : false, credentials: true });
  await app.register(rateLimit, {
    global: true,
    max: 300,
    timeWindow: '1 minute',
    ...(ctx.redis ? { redis: ctx.redis } : {}),
  });
  await app.register(authPlugin, { jwtSecret: ctx.env.JWT_SECRET, adminJwtSecret: ctx.env.ADMIN_JWT_SECRET });

  app.get('/health', async () => ({ ok: true }));
  app.get('/ready', async (_req, reply) => {
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

  // Admin API (separate token audience + RBAC on every route)
  await app.register(adminAuthRoutes, { prefix: '/admin/auth' });
  await app.register(adminOverviewRoutes, { prefix: '/admin/overview' });
  await app.register(adminUsersRoutes, { prefix: '/admin/users' });
  await app.register(adminContentRoutes, { prefix: '/admin/content' });
  await app.register(adminCampaignRoutes, { prefix: '/admin/campaigns' });
  await app.register(adminRewardsRoutes, { prefix: '/admin/rewards' });
  await app.register(adminSettingsRoutes, { prefix: '/admin/settings' });

  return app;
}
