/**
 * Admin «التلاوات» — the recordings moderation queue (never a per-user list of recordings):
 *   GET  /admin/recordings/queue                    AdminRecordingQueue (needs_review, held/reported, removed ≤ 7 days; reported/hidden comments)
 *   GET  /admin/recordings/:id/audio                the audio, only while the recording is in the queue
 *   POST /admin/recordings/:id/decision             approve | reject (religious_reviewer) · dismiss | remove | restore (support)
 *   POST /admin/recordings/comments/:id/decision    remove | restore | dismiss (support)
 * Every decision is audited in the same transaction (lib/audit). super_admin may do everything.
 */
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { AdminCommentDecision, AdminRecordingDecision } from '@yaqeen/contracts';
import { sendAudio } from '../../lib/audio.js';
import { forbidden } from '../../lib/errors.js';
import { adminOf } from '../../plugins/auth.js';
import * as rec from '../../services/recordings.service.js';

const Id = z.object({ id: z.string().uuid() });

export const adminRecordingsRoutes: FastifyPluginAsync = async (app) => {
  const { ctx } = app;
  const read = app.requireAdmin(['religious_reviewer', 'support']);
  const support = app.requireAdmin(['support']);

  app.get('/queue', { preHandler: read }, async () => rec.adminQueue(ctx));

  app.get('/:id/audio', { preHandler: read }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    return sendAudio(req, reply, await rec.adminAudio(ctx, id), 'private, no-store');
  });

  app.post('/:id/decision', { preHandler: read }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    const d = AdminRecordingDecision.parse(req.body);
    const admin = adminOf(req);
    if (admin.role !== 'super_admin' && admin.role !== rec.DECISION_ROLES[d.action]) throw forbidden('role_not_allowed');
    await rec.decideRecording(ctx, req, admin.sub, id, d);
    return reply.code(204).send();
  });

  app.post('/comments/:id/decision', { preHandler: support }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    await rec.decideComment(ctx, req, adminOf(req).sub, id, AdminCommentDecision.parse(req.body));
    return reply.code(204).send();
  });
};
