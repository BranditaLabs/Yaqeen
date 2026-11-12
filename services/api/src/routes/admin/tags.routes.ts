/**
 * Physical card tags (key medals, cards sold in the store):
 *   GET  /admin/tags/batches            batches with totals
 *   POST /admin/tags/batches            mint codes for the manufacturer (audited)
 *   GET  /admin/tags/batches/:batch.csv code, url, kind — what goes in each NFC chip and QR print
 *   GET  /admin/tags                    tags (filter by batch, status, code)
 *   POST /admin/tags/:code/disable      switch a tag off, e.g. reported lost (audited)
 *   POST /admin/tags/:code/release      re-issue a returned tag as blank (audited)
 *   PATCH /admin/tags/batches/:batch    production status (ordered → received → on_sale) + note (audited)
 *   POST /admin/tags/batches/:batch/void a faulty run: every tag in it switched off at once (audited)
 *   POST /admin/tags/:code/assign       link a blank tag to a customer who can't activate it (audited)
 *   GET  /admin/tags/batches/:batch/encode-sessions          staff encoding sessions (never the token)
 *   POST /admin/tags/batches/:batch/encode-sessions          open one: token shown once as QR + link (audited)
 *   DELETE /admin/tags/batches/:batch/encode-sessions/:id    revoke it at once (audited)
 * Rows show the linked card's handle — never worship data.
 */
import { and, desc, eq, isNotNull, isNull, lt, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import {
  AdminAssignTag,
  type AdminEncodeSession,
  type AdminEncodeSessionCreated,
  type AdminTagBatch, AdminTagBatchPatch, AdminTagBatchRequest,
  type AdminTagRow,
  TagCode,
  TagStatus,
  normalizeTagCode,
} from '@yaqeen/contracts';
import { profileTags, publicProfiles, tagBatches, tagEncodeSessions, users } from '../../db/schema.js';
import { adminOf } from '../../plugins/auth.js';
import { audit } from '../../lib/audit.js';
import { badRequest, notFound } from '../../lib/errors.js';
import * as encoding from '../../services/tag-encoding.service.js';
import * as tags from '../../services/tags.service.js';

const Reason = z.object({ reason: z.string().trim().min(3).max(500) });
const BatchParam = z.object({ batch: z.string().regex(/^[A-Za-z0-9_-]{1,40}$/) });

export const adminTagsRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const read = app.requireAdmin(['support', 'marketing']);
  const mint = app.requireAdmin(['marketing']);
  const write = app.requireAdmin(['support']);
  const voider = app.requireAdmin(['marketing', 'support']);

  app.get('/batches', { preHandler: read }, async (): Promise<AdminTagBatch[]> => {
    const rows = await db
      .select({
        batch: tagBatches.batch,
        kind: tagBatches.kind,
        status: tagBatches.status,
        note: tagBatches.note,
        createdAt: tagBatches.createdAt,
        // Correlated subqueries: columns are qualified by hand (drizzle renders them bare here).
        total: sql<number>`(select count(*) from profile_tags t where t.batch = tag_batches.batch)::int`,
        active: sql<number>`(select count(*) from profile_tags t where t.batch = tag_batches.batch and t.user_id is not null and t.disabled_at is null)::int`,
        disabled: sql<number>`(select count(*) from profile_tags t where t.batch = tag_batches.batch and t.disabled_at is not null)::int`,
        encoded: sql<number>`(select count(*) from profile_tags t where t.batch = tag_batches.batch and t.encoded_at is not null and t.disabled_at is null)::int`,
      })
      .from(tagBatches)
      .orderBy(desc(tagBatches.createdAt));
    return rows.map((r) => ({
      ...r,
      kind: r.kind as AdminTagBatch['kind'],
      status: r.status as AdminTagBatch['status'],
      createdAt: r.createdAt.toISOString(),
    }));
  });

  app.patch('/batches/:batch', { preHandler: mint }, async (req) => {
    const { batch } = BatchParam.parse(req.params);
    const body = AdminTagBatchPatch.parse(req.body);
    return db.transaction(async (tx) => {
      const [before] = await tx.select().from(tagBatches).where(eq(tagBatches.batch, batch));
      if (!before) throw notFound('batch');
      if (before.status === 'void') throw badRequest('batch_void', 'A voided batch stays void');
      await tx
        .update(tagBatches)
        .set({ ...(body.status ? { status: body.status } : {}), ...(body.note !== undefined ? { note: body.note } : {}), updatedAt: app.ctx.now() })
        .where(eq(tagBatches.batch, batch));
      await audit(tx, req, { action: 'tags.batch.update', targetType: 'tag_batch', targetId: batch, before: { status: before.status, note: before.note }, after: body });
      return { ok: true };
    });
  });

  app.post('/batches/:batch/void', { preHandler: voider }, async (req) => {
    const { batch } = BatchParam.parse(req.params);
    const { reason } = Reason.parse(req.body);
    const result = await db.transaction(async (tx) => {
      const [before] = await tx.select().from(tagBatches).where(eq(tagBatches.batch, batch));
      if (!before) throw notFound('batch');
      await tx.update(tagBatches).set({ status: 'void', updatedAt: app.ctx.now() }).where(eq(tagBatches.batch, batch));
      const off = await tx
        .update(profileTags)
        .set({ disabledAt: app.ctx.now() })
        .where(and(eq(profileTags.batch, batch), isNull(profileTags.disabledAt)))
        .returning({ userId: profileTags.userId });
      const linked = off.filter((t) => t.userId).length;
      await audit(tx, req, { action: 'tags.batch.void', targetType: 'tag_batch', targetId: batch, reason, before: { status: before.status }, after: { status: 'void', switchedOff: off.length, linked } });
      return { ok: true, switchedOff: off.length, linked };
    });
    await app.ctx.cache.bumpNamespace('profile');
    return result;
  });

  app.post('/batches', { preHandler: mint }, async (req, reply) => {
    const body = AdminTagBatchRequest.parse(req.body);
    const [exists] = await db.select({ b: tagBatches.batch }).from(tagBatches).where(eq(tagBatches.batch, body.batch)).limit(1);
    const [legacy] = await db.select({ code: profileTags.code }).from(profileTags).where(eq(profileTags.batch, body.batch)).limit(1);
    if (exists || legacy) throw badRequest('batch_exists', 'Choose a new batch name');
    const codes = await db.transaction(async (tx) => {
      const minted = await tags.mintBatch(tx, body, adminOf(req).sub);
      await audit(tx, req, { action: 'tags.batch.mint', targetType: 'tag_batch', targetId: body.batch, after: { kind: body.kind, count: minted.length } });
      return minted;
    });
    return reply.status(201).send({ batch: body.batch, kind: body.kind, count: codes.length });
  });

  app.get('/batches/:file', { preHandler: read }, async (req, reply) => {
    const { file } = z.object({ file: z.string().regex(/^[A-Za-z0-9_-]{1,40}\.csv$/) }).parse(req.params);
    const batch = file.slice(0, -4);
    const rows = await db.select({ code: profileTags.code, kind: profileTags.kind }).from(profileTags).where(eq(profileTags.batch, batch)).orderBy(profileTags.code);
    if (!rows.length) throw notFound('batch');
    const csv = ['code,printed_code,url,kind', ...rows.map((r) => `${r.code},${r.code.slice(0, 4)}-${r.code.slice(4)},${tags.tagUrl(app.ctx, r.code)},${r.kind}`)].join('\n');
    reply.header('Content-Disposition', `attachment; filename="yaqeen-tags-${batch}.csv"`);
    reply.header('Cache-Control', 'no-store');
    return reply.type('text/csv; charset=utf-8').send(`${csv}\n`);
  });

  app.get('/', { preHandler: read }, async (req): Promise<{ items: AdminTagRow[]; nextCursor: string | null }> => {
    const q = z
      .object({
        batch: z.string().max(40).optional(),
        status: TagStatus.optional(),
        code: z.string().max(40).optional(),
        cursor: z.iso.datetime().optional(),
        limit: z.coerce.number().int().min(1).max(200).default(50),
      })
      .parse(req.query);
    const conds = [];
    if (q.batch) conds.push(eq(profileTags.batch, q.batch));
    if (q.status === 'unclaimed') conds.push(isNull(profileTags.userId), isNull(profileTags.disabledAt));
    if (q.status === 'active') conds.push(isNotNull(profileTags.userId), isNull(profileTags.disabledAt));
    if (q.status === 'disabled') conds.push(isNotNull(profileTags.disabledAt));
    if (q.code) conds.push(eq(profileTags.code, normalizeTagCode(q.code)));
    if (q.cursor) conds.push(lt(profileTags.createdAt, new Date(q.cursor)));
    const rows = await db
      .select({ t: profileTags, handle: publicProfiles.handle })
      .from(profileTags)
      .leftJoin(publicProfiles, eq(publicProfiles.userId, profileTags.userId))
      .where(conds.length ? and(...conds) : undefined)
      .orderBy(desc(profileTags.createdAt), profileTags.code)
      .limit(q.limit + 1);
    const items = rows.slice(0, q.limit).map(({ t, handle }) => ({
      code: t.code,
      kind: t.kind as AdminTagRow['kind'],
      batch: t.batch,
      status: (t.disabledAt ? 'disabled' : t.userId ? 'active' : 'unclaimed') as AdminTagRow['status'],
      handle: t.userId ? handle : null,
      userId: t.userId,
      scans: t.scans,
      createdAt: t.createdAt.toISOString(),
      linkedAt: t.linkedAt?.toISOString() ?? null,
      encodedAt: t.encodedAt?.toISOString() ?? null,
      encodedLocked: t.encodedLocked,
    }));
    return { items, nextCursor: rows.length > q.limit ? items[items.length - 1]!.createdAt : null };
  });

  /* ------------------------------------------------ staff encoding sessions (NFC) */

  const SessionParam = BatchParam.extend({ id: z.uuid() });

  app.get('/batches/:batch/encode-sessions', { preHandler: mint }, async (req): Promise<AdminEncodeSession[]> => {
    const { batch } = BatchParam.parse(req.params);
    const rows = await db.select().from(tagEncodeSessions).where(eq(tagEncodeSessions.batch, batch)).orderBy(desc(tagEncodeSessions.createdAt)).limit(20);
    const now = app.ctx.now();
    return rows.map((r) => encoding.toAdminSession(r, now));
  });

  app.post('/batches/:batch/encode-sessions', { preHandler: mint }, async (req, reply) => {
    const { batch } = BatchParam.parse(req.params);
    const created = await db.transaction(async (tx): Promise<AdminEncodeSessionCreated> => {
      const [b] = await tx.select({ status: tagBatches.status }).from(tagBatches).where(eq(tagBatches.batch, batch));
      if (!b) throw notFound('batch');
      if (b.status === 'void') throw badRequest('batch_void', 'A voided batch cannot be encoded');
      const { token, row } = await encoding.createSession(tx, app.ctx.now(), batch, adminOf(req).sub);
      // The audit row carries the session id and expiry — never the token or its hash.
      await audit(tx, req, { action: 'tags.encode_session.create', targetType: 'tag_batch', targetId: batch, after: { sessionId: row.id, expiresAt: row.expiresAt.toISOString() } });
      return { ...encoding.toAdminSession(row, app.ctx.now()), token, url: encoding.encodeDeepLink(token) };
    });
    reply.header('Cache-Control', 'no-store');
    return reply.status(201).send(created);
  });

  app.delete('/batches/:batch/encode-sessions/:id', { preHandler: mint }, async (req, reply) => {
    const { batch, id } = SessionParam.parse(req.params);
    await db.transaction(async (tx) => {
      const [row] = await tx
        .update(tagEncodeSessions)
        .set({ revokedAt: app.ctx.now() })
        .where(and(eq(tagEncodeSessions.id, id), eq(tagEncodeSessions.batch, batch), isNull(tagEncodeSessions.revokedAt)))
        .returning({ id: tagEncodeSessions.id });
      if (!row) throw notFound('encode_session');
      await audit(tx, req, { action: 'tags.encode_session.revoke', targetType: 'tag_batch', targetId: batch, after: { sessionId: id } });
    });
    return reply.status(204).send();
  });

  app.post('/:code/disable', { preHandler: write }, async (req) => {
    const { code } = z.object({ code: TagCode }).parse(req.params);
    const { reason } = Reason.parse(req.body);
    return db.transaction(async (tx) => {
      const [before] = await tx.select().from(profileTags).where(eq(profileTags.code, code));
      if (!before) throw notFound('tag');
      await tx.update(profileTags).set({ disabledAt: app.ctx.now() }).where(eq(profileTags.code, code));
      await audit(tx, req, { action: 'tags.disable', targetType: 'tag', targetId: code, reason, before: { userId: before.userId, disabledAt: before.disabledAt }, after: { disabled: true } });
      return { ok: true };
    });
  });

  app.post('/:code/assign', { preHandler: write }, async (req) => {
    const { code } = z.object({ code: TagCode }).parse(req.params);
    const body = AdminAssignTag.parse(req.body);
    return db.transaction(async (tx) => {
      const [u] = await tx.select({ status: users.status, isGuest: users.isGuest }).from(users).where(eq(users.id, body.userId));
      if (!u) throw notFound('user');
      if (u.isGuest || u.status !== 'active') throw badRequest('user_not_eligible', 'Only active, signed-in accounts can own a tag');
      const row = await tags.linkTo(tx, app.ctx.now(), body.userId, code);
      await audit(tx, req, { action: 'tags.assign', targetType: 'tag', targetId: code, reason: body.reason, after: { userId: body.userId } });
      return tags.toTag(app.ctx, row);
    });
  });

  app.post('/:code/release', { preHandler: write }, async (req) => {
    const { code } = z.object({ code: TagCode }).parse(req.params);
    const { reason } = Reason.parse(req.body);
    return db.transaction(async (tx) => {
      const [before] = await tx.select().from(profileTags).where(eq(profileTags.code, code));
      if (!before) throw notFound('tag');
      await tx.update(profileTags).set({ userId: null, linkedAt: null, disabledAt: null, scans: 0 }).where(eq(profileTags.code, code));
      await audit(tx, req, { action: 'tags.release', targetType: 'tag', targetId: code, reason, before: { userId: before.userId, disabledAt: before.disabledAt }, after: { userId: null } });
      return { ok: true };
    });
  });
};
