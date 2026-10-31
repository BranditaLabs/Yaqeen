/**
 * Shopify webhooks. Register `orders/paid` in the shop (JSON) pointing at
 * `<api>/webhooks/shopify/orders-paid` and put its signing secret in SHOPIFY_WEBHOOK_SECRET.
 *
 * Only our reward codes are read from the order — nothing about the customer is stored.
 * With consent and the `serverConversions` flag, the order's total is also reported to the
 * configured ad platforms as a `purchase` (services/conversions.service.ts) in the background,
 * so Shopify gets its 200 at once.
 */
import type { FastifyPluginAsync } from 'fastify';
import { verifyWebhookHmac, yaqeenCodesIn } from '../../domain/shopify.js';
import { unauthorized } from '../../lib/errors.js';
import { sendPurchaseConversions } from '../../services/conversions.service.js';
import { markUsed } from '../../services/rewards.service.js';

export const shopifyWebhookRoutes: FastifyPluginAsync = async (app) => {
  // The signature covers the exact bytes, so this scope keeps the raw body.
  app.addContentTypeParser('application/json', { parseAs: 'buffer' }, (_req, body, done) => done(null, body));

  app.post('/orders-paid', { config: { rateLimit: { max: 600, timeWindow: '1 minute' } } }, async (req, reply) => {
    const raw = req.body as Buffer;
    const hmac = req.headers['x-shopify-hmac-sha256'];
    if (!verifyWebhookHmac(raw, typeof hmac === 'string' ? hmac : undefined, app.ctx.env.SHOPIFY_WEBHOOK_SECRET)) {
      throw unauthorized('invalid_signature');
    }
    let order: unknown;
    try {
      order = JSON.parse(raw.toString('utf8'));
    } catch {
      return reply.status(200).send({ ok: true, used: 0 }); // signed but unreadable: ack so Shopify stops retrying
    }
    const id = (order as { admin_graphql_api_id?: unknown; id?: unknown } | null) ?? {};
    const orderId = String(id.admin_graphql_api_id ?? id.id ?? '');
    const codes = yaqeenCodesIn(order);
    const used = await markUsed(app.ctx, codes, orderId);
    if (used) req.log.info({ used }, 'shopify: reward codes used');
    // Also on a replay: a send that failed before may be retried; one already sent is skipped.
    // Not awaited (it never throws), so Shopify isn't kept waiting on ad platforms.
    if (codes.length) void sendPurchaseConversions(app.ctx, order, orderId);
    return { ok: true, used };
  });
};
