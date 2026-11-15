/**
 * Staff encoder (spec §5.26 › in-house encoding), keyed by the session token — no user auth, the
 * token is the capability for one batch:
 *   GET  /v1/encode/:token          batch, kind, base URL and the working codes (+ encodedAt)
 *   POST /v1/encode/:token/written  { code, uid?, locked } — a chip was written and verified
 * Unknown, expired, revoked and voided-batch sessions answer the same 404. Rate-limited per IP;
 * the token is redacted from request logs (app.ts).
 */
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { EncodeWrittenRequest } from '@yaqeen/contracts';
import * as encoding from '../../services/tag-encoding.service.js';

const Params = z.object({ token: z.string().max(100) });

export const encodeRoutes: FastifyPluginAsync = async (app) => {
  app.get('/:token', { config: { rateLimit: { max: 30, timeWindow: '1 minute' } } }, async (req, reply) => {
    const parsed = Params.safeParse(req.params);
    if (!parsed.success) throw encoding.sessionGone();
    reply.header('Cache-Control', 'no-store');
    return encoding.view(app.ctx, parsed.data.token);
  });

  // A chip every few seconds at most: 120/min leaves room for retries.
  app.post('/:token/written', { config: { rateLimit: { max: 120, timeWindow: '1 minute' } } }, async (req, reply) => {
    const parsed = Params.safeParse(req.params);
    if (!parsed.success) throw encoding.sessionGone();
    reply.header('Cache-Control', 'no-store');
    // The session is checked before the body, so a dead token never answers anything but 404.
    return encoding.written(app.ctx, parsed.data.token, () => EncodeWrittenRequest.parse(req.body));
  });
};
