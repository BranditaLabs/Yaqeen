/**
 * GET /admin/analytics?days=30 — product analytics as aggregates only (any count < 20 withheld):
 * active installs per day, events, onboarding funnel, weekly retention, platforms and versions.
 * No user, install id or worship data ever leaves this route.
 */
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import * as analytics from '../../services/product-analytics.service.js';

export const adminAnalyticsRoutes: FastifyPluginAsync = async (app) => {
  const read = app.requireAdmin(['marketing', 'support']);
  app.get('/', { preHandler: read }, async (req) => {
    const { days } = z.object({ days: z.coerce.number().int().min(7).max(180).default(30) }).parse(req.query);
    return analytics.report(app.ctx, days);
  });
};
