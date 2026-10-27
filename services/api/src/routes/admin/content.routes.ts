import { and, asc, desc, eq, getTableColumns, gte, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { ContentStatus, ContentType, DailyTaskUpsert, ReviewDecision, UpsertContentRequest } from '@yaqeen/contracts';
import { type LiveContent, adminUsers, appConfig, contentItems, dailyTasks } from '../../db/schema.js';
import { localToday } from '../../domain/points.js';
import { audit } from '../../lib/audit.js';
import { conflict, forbidden, notFound } from '../../lib/errors.js';
import { adminOf } from '../../plugins/auth.js';

/** What the app is served once a reviewer approves this version. */
export function liveSnapshot(r: typeof contentItems.$inferSelect): LiveContent {
  return {
    category: r.category,
    title: r.title,
    textAr: r.textAr,
    translationEn: r.translationEn,
    source: r.source,
    virtue: r.virtue,
    repeatCount: r.repeatCount,
    sortOrder: r.sortOrder,
    featured: r.featured,
    version: r.version,
  };
}

/**
 * Content workflow:  draft → pending_review → (published | changes_requested → pending_review …)
 * Editors write; only a religious reviewer can publish, and never their own edit.
 */
export const adminContentRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const editor = app.requireAdmin(['content_editor']);
  const reviewer = app.requireAdmin(['religious_reviewer']);
  const anyContent = app.requireAdmin(['content_editor', 'religious_reviewer']);

  const { live: _live, liveAt: _liveAt, ...rest } = getTableColumns(contentItems);

  app.get('/', { preHandler: anyContent }, async (req) => {
    const q = z.object({ type: ContentType.optional(), status: ContentStatus.optional() }).parse(req.query);
    const conds = [];
    if (q.type) conds.push(eq(contentItems.type, q.type));
    if (q.status) conds.push(eq(contentItems.status, q.status));
    // `editorName` feeds the «آخر تعديل» history line.
    return db
      .select({ ...rest, editorName: adminUsers.name, liveVersion: sql<number | null>`(${contentItems.live}->>'version')::int` })
      .from(contentItems)
      .leftJoin(adminUsers, eq(adminUsers.id, contentItems.createdBy))
      .where(conds.length ? and(...conds) : undefined)
      .orderBy(desc(contentItems.updatedAt))
      .limit(200);
  });

  app.post('/', { preHandler: editor }, async (req) => {
    const body = UpsertContentRequest.parse(req.body);
    return db.transaction(async (tx) => {
      const [row] = await tx
        .insert(contentItems)
        .values({ ...body, translationEn: body.translationEn ?? null, virtue: body.virtue ?? null, createdBy: adminOf(req).sub })
        .returning();
      await audit(tx, req, { action: 'content.create', targetType: 'content', targetId: row!.id, after: row });
      return row;
    });
  });

  /**
   * Any edit sends the item back to draft and through review again. The last approved version
   * (`live`) keeps being served meanwhile; approving the edit replaces it.
   */
  app.put('/:id', { preHandler: editor }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const body = UpsertContentRequest.parse(req.body);
    return db.transaction(async (tx) => {
      const [before] = await tx.select().from(contentItems).where(eq(contentItems.id, id));
      if (!before) throw notFound('content');
      const [row] = await tx
        .update(contentItems)
        .set({
          ...body,
          translationEn: body.translationEn ?? null,
          virtue: body.virtue ?? null,
          status: 'draft',
          version: before.version + 1,
          createdBy: adminOf(req).sub,
          updatedAt: app.ctx.now(),
        })
        .where(eq(contentItems.id, id))
        .returning();
      await audit(tx, req, { action: 'content.update', targetType: 'content', targetId: id, before, after: row });
      return row;
    });
  });

  app.post('/:id/submit', { preHandler: editor }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const [row] = await db
      .update(contentItems)
      .set({ status: 'pending_review', updatedAt: app.ctx.now() })
      .where(eq(contentItems.id, id))
      .returning({ id: contentItems.id });
    if (!row) throw notFound('content');
    return { ok: true };
  });

  app.post('/:id/review', { preHandler: reviewer }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const body = ReviewDecision.parse(req.body);
    return db.transaction(async (tx) => {
      const [before] = await tx.select().from(contentItems).where(eq(contentItems.id, id));
      if (!before) throw notFound('content');
      if (before.status !== 'pending_review') throw conflict('not_pending_review');
      if (before.createdBy === adminOf(req).sub) throw forbidden('cannot_review_own_edit');
      const now = app.ctx.now();
      const [row] = await tx
        .update(contentItems)
        .set(
          body.decision === 'approve'
            ? {
                status: 'published',
                reviewedBy: adminOf(req).sub,
                reviewNote: body.note ?? null,
                publishedAt: now,
                updatedAt: now,
                live: liveSnapshot(before),
                liveAt: now,
              }
            : { status: 'changes_requested', reviewedBy: adminOf(req).sub, reviewNote: body.note ?? null, updatedAt: now },
        )
        .where(eq(contentItems.id, id))
        .returning();
      // An approved splash verse goes live in remote config in the same transaction.
      if (body.decision === 'approve' && row!.type === 'splash_verse') {
        const value = { textAr: row!.textAr, reference: row!.source };
        await tx
          .insert(appConfig)
          .values({ key: 'splashVerse', value, updatedBy: adminOf(req).sub })
          .onConflictDoUpdate({ target: appConfig.key, set: { value, updatedBy: adminOf(req).sub, updatedAt: now } });
      }
      await audit(tx, req, { action: `content.review.${body.decision}`, targetType: 'content', targetId: id, reason: body.note, before: { status: before.status }, after: { status: row!.status } });
      return row;
    });
  });

  /* --------------------------------------------------------- daily tasks */
  app.get('/daily-tasks', { preHandler: anyContent }, async () =>
    db.select().from(dailyTasks).where(gte(dailyTasks.date, localToday(app.ctx.now()))).orderBy(asc(dailyTasks.date)).limit(60),
  );

  app.put('/daily-tasks', { preHandler: editor }, async (req) => {
    const body = DailyTaskUpsert.parse(req.body);
    await db.transaction(async (tx) => {
      await tx
        .insert(dailyTasks)
        .values({ ...body, updatedBy: adminOf(req).sub })
        .onConflictDoUpdate({ target: dailyTasks.date, set: { taskAr: body.taskAr, taskEn: body.taskEn, updatedBy: adminOf(req).sub, updatedAt: app.ctx.now() } });
      await audit(tx, req, { action: 'daily_task.upsert', targetType: 'daily_task', targetId: body.date, after: body });
    });
    return { ok: true };
  });
};
