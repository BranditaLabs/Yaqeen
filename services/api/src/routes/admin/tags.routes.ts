/**
 * Physical card tags (key medals, cards sold in the store):
 *   GET  /admin/tags/batches            batches with totals
 *   POST /admin/tags/batches            mint codes for the manufacturer (audited)
 *   GET  /admin/tags/batches/:batch.csv code, url, kind — what goes in each NFC chip and QR print
 *   GET  /admin/tags                    tags (filter by batch, status, code)
 *   POST /admin/tags/:code/disable      switch a tag off, e.g. reported lost (audited)
 *   POST /admin/tags/:code/release      re-issue a returned tag as blank (audited)
 * Rows show the linked card's handle — never worship data.
 */
import { and, desc, eq, isNotNull, isNull, lt, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { type AdminTagBatch, AdminTagBatchRequest, type AdminTagRow, TagCode, TagStatus, normalizeTagCode } from '@yaqeen/contracts';
import { profileTags, publicProfiles } from '../../db/schema.js';
import { audit } from '../../lib/audit.js';
import { badRequest, notFound } from '../../lib/errors.js';
import * as tags from '../../services/tags.service.js';

const Reason = z.object({ reason: z.string().trim().min(3).max(500) });

export const adminTagsRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const read = app.requireAdmin(['support', 'marketing']);
  const mint = app.requireAdmin(['marketing']);
  const write = app.requireAdmin(['support']);

  app.get('/batches', { preHandler: read }, async (): Promise<AdminTagBatch[]> => {
    const rows = await db
      .select({
        batch: profileTags.batch,
        kind: sql<string>`min(${profileTags.kind})`,
        total: sql<number>`count(*)::int`,
        active: sql<number>`count(*) filter (where ${profileTags.userId} is not null and ${profileTags.disabledAt} is null)::int`,
        disabled: sql<number>`count(*) filter (where ${profileTags.disabledAt} is not null)::int`,
        createdAt: sql<Date>`min(${profileTags.createdAt})`,
      })
      .from(profileTags)
      .groupBy(profileTags.batch)
      .orderBy(sql`min(${profileTags.createdAt}) desc`);
    return rows.map((r) => ({ ...r, kind: r.kind as AdminTagBatch['kind'], createdAt: new Date(r.createdAt).toISOString() }));
  });

  app.post('/batches', { preHandler: mint }, async (req, reply) => {
    const body = AdminTagBatchRequest.parse(req.body);
    const [exists] = await db.select({ code: profileTags.code }).from(profileTags).where(eq(profileTags.batch, body.batch)).limit(1);
    if (exists) throw badRequest('batch_exists', 'Choose a new batch name');
    const codes = await db.transaction(async (tx) => {
      const minted = await tags.mintBatch(tx, body);
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
    }));
    return { items, nextCursor: rows.length > q.limit ? items[items.length - 1]!.createdAt : null };
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
