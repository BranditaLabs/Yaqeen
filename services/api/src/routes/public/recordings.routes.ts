/**
 * «تلاواتي» — users' own recorded recitations (contracts `recordings.ts`, docs/API.md › Recordings).
 *
 * Owner (signed in):
 *   POST   /v1/me/recordings                  multipart: `meta` (JSON RecordingMeta) + `audio` (.m4a) → 202 Recording
 *   GET    /v1/me/recordings                  MyRecordings
 *   GET    /v1/me/recordings/:id/audio        the owner's audio (any status), byte ranges
 *   PATCH  /v1/me/recordings/:id              visibility, commentsOn, position → Recording
 *   DELETE /v1/me/recordings/:id              hard delete (audio, reactions, comments) → 204
 * Members (signed in; reacting/commenting/reporting also need the community opt-in):
 *   GET    /v1/community/members/:handle/recordings
 *   GET    /v1/recordings/:id/audio
 *   PUT    /v1/recordings/:id/reaction        {kind} → ReactionState   · DELETE → ReactionState
 *   GET    /v1/recordings/:id/comments?cursor= · POST {text} → 201 RecordingComment
 *   DELETE /v1/recordings/:id/comments/:cid   author or recording owner → 204
 *   POST   /v1/recordings/:id/report          {reason} → 204 · POST /v1/recordings/:id/comments/:cid/report → 204
 * Web (no auth; only public + approved recordings of a live card):
 *   GET    /u/:handle/r/:id.m4a               the audio, byte ranges
 *   GET    /u/assets/recitations.js           the card's tiny player script (CSP script-src 'self')
 */
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  PostComment,
  RECORDING_DURATION_TOLERANCE_MS,
  RECORDING_FORMAT,
  RECORDING_MAX_MS,
  RecordingMeta,
  RecordingPatch,
  RecordingReportRequest,
  SetReaction,
} from '@yaqeen/contracts';
import { sendAudio } from '../../lib/audio.js';
import { badRequest, notFound } from '../../lib/errors.js';
import { boundaryOf, parseMultipart } from '../../lib/multipart.js';
import { userId } from '../../plugins/auth.js';
import * as rec from '../../services/recordings.service.js';
import { RECITATIONS_JS } from '../../web/recitations-player.js';

const Id = z.object({ id: z.string().uuid() });
const IdCid = z.object({ id: z.string().uuid(), cid: z.string().uuid() });
const Handle = z.object({ handle: z.string().min(1).max(40) });

/** Parse the upload's multipart body into meta + audio with stable error codes. */
function parseUpload(req: FastifyRequest): { meta: RecordingMeta; audio: Buffer } {
  const boundary = boundaryOf(req.headers['content-type']);
  if (!boundary || !Buffer.isBuffer(req.body)) throw badRequest('recording_bad_format', 'multipart/form-data with meta + audio expected');
  const parts = parseMultipart(req.body, boundary);
  const metaPart = parts?.find((p) => p.name === 'meta');
  const audioPart = parts?.find((p) => p.name === 'audio');
  if (!metaPart || !audioPart) throw badRequest('recording_bad_format', 'parts meta and audio are required');
  if (audioPart.contentType && !(RECORDING_FORMAT.mimes as readonly string[]).includes(audioPart.contentType.split(';')[0]!.trim())) {
    throw badRequest('recording_bad_format', 'audio must be AAC-LC in .m4a');
  }
  let json: unknown;
  try {
    json = JSON.parse(metaPart.data.toString('utf8'));
  } catch {
    throw badRequest('validation_failed', 'meta is not JSON');
  }
  const parsed = RecordingMeta.safeParse(json);
  if (!parsed.success) {
    const issues = parsed.error.issues;
    if (issues.some((i) => i.message === 'recording_invalid_range')) throw badRequest('recording_invalid_range');
    if (issues.some((i) => i.path[0] === 'durationMs' && i.code === 'too_big')) throw badRequest('recording_too_long');
    throw parsed.error;
  }
  if (parsed.data.durationMs > RECORDING_MAX_MS + RECORDING_DURATION_TOLERANCE_MS) throw badRequest('recording_too_long');
  return { meta: parsed.data, audio: Buffer.from(audioPart.data) };
}

export const recordingsRoutes: FastifyPluginAsync = async (app) => {
  const { ctx } = app;

  // The upload body (≤ 256 KB) arrives as a Buffer; parsed by lib/multipart in the handler.
  app.addContentTypeParser('multipart/form-data', { parseAs: 'buffer', bodyLimit: 256 * 1024 }, (_req, body, done) => done(null, body));

  /* ----------------------------------------------------------- owner */

  app.post(
    '/v1/me/recordings',
    { preHandler: app.requireUser, bodyLimit: 256 * 1024, config: { rateLimit: { max: 20, timeWindow: '1 hour' } } },
    async (req, reply) => {
      const { meta, audio } = parseUpload(req);
      return reply.code(202).send(await rec.upload(ctx, userId(req), meta, audio));
    },
  );

  app.get('/v1/me/recordings', { preHandler: app.requireUser }, async (req) => rec.listMine(ctx, userId(req)));

  app.get('/v1/me/recordings/:id/audio', { preHandler: app.requireUser }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    return sendAudio(req, reply, await rec.ownAudio(ctx, userId(req), id), 'private, no-store');
  });

  app.patch('/v1/me/recordings/:id', { preHandler: app.requireUser }, async (req) => {
    const { id } = Id.parse(req.params);
    return rec.patch(ctx, userId(req), id, RecordingPatch.parse(req.body));
  });

  app.delete('/v1/me/recordings/:id', { preHandler: app.requireUser }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    await rec.remove(ctx, userId(req), id);
    return reply.code(204).send();
  });

  /* --------------------------------------------------------- members */

  app.get('/v1/community/members/:handle/recordings', { preHandler: app.requireUser }, async (req) => {
    const { handle } = Handle.parse(req.params);
    return rec.memberRecordings(ctx, userId(req), handle);
  });

  app.get('/v1/recordings/:id/audio', { preHandler: app.requireUser }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    return sendAudio(req, reply, await rec.memberAudio(ctx, userId(req), id), 'private, max-age=300');
  });

  app.put('/v1/recordings/:id/reaction', { preHandler: app.requireUser, config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req) => {
    const { id } = Id.parse(req.params);
    return rec.setReaction(ctx, userId(req), id, SetReaction.parse(req.body).kind);
  });

  app.delete('/v1/recordings/:id/reaction', { preHandler: app.requireUser }, async (req) => {
    const { id } = Id.parse(req.params);
    return rec.clearReaction(ctx, userId(req), id);
  });

  app.get('/v1/recordings/:id/comments', { preHandler: app.requireUser }, async (req) => {
    const { id } = Id.parse(req.params);
    const { cursor } = z.object({ cursor: z.string().max(200).optional() }).parse(req.query);
    return rec.listComments(ctx, userId(req), id, cursor);
  });

  app.post('/v1/recordings/:id/comments', { preHandler: app.requireUser }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    const body = PostComment.safeParse(req.body);
    if (!body.success) throw badRequest('comment_rejected', 'too_long', { problem: 'too_long' });
    return reply.code(201).send(await rec.postComment(ctx, userId(req), id, body.data.text));
  });

  app.delete('/v1/recordings/:id/comments/:cid', { preHandler: app.requireUser }, async (req, reply) => {
    const { id, cid } = IdCid.parse(req.params);
    await rec.deleteComment(ctx, userId(req), id, cid);
    return reply.code(204).send();
  });

  app.post('/v1/recordings/:id/report', { preHandler: app.requireUser }, async (req, reply) => {
    const { id } = Id.parse(req.params);
    await rec.report(ctx, userId(req), 'recording', id, null, RecordingReportRequest.parse(req.body).reason);
    return reply.code(204).send();
  });

  app.post('/v1/recordings/:id/comments/:cid/report', { preHandler: app.requireUser }, async (req, reply) => {
    const { id, cid } = IdCid.parse(req.params);
    await rec.report(ctx, userId(req), 'comment', id, cid, RecordingReportRequest.parse(req.body).reason);
    return reply.code(204).send();
  });

  /* ------------------------------------------------------------- web */

  app.get('/u/:handle/r/:file', async (req: FastifyRequest, reply: FastifyReply) => {
    const p = z.object({ handle: z.string().min(1).max(40), file: z.string().regex(/^[0-9a-f-]{36}\.m4a$/i) }).safeParse(req.params);
    if (!p.success) throw notFound('recording');
    const audio = await rec.cardAudio(ctx, p.data.handle, p.data.file.slice(0, 36).toLowerCase());
    if (!audio) throw notFound('recording');
    // Short cache: switching to private or a moderator's removal applies within minutes behind a CDN.
    return sendAudio(req, reply, audio, 'public, max-age=300');
  });

  app.get('/u/assets/recitations.js', async (_req, reply) => {
    reply.header('Cache-Control', 'public, max-age=3600');
    reply.type('text/javascript; charset=utf-8');
    return reply.send(RECITATIONS_JS);
  });
};

