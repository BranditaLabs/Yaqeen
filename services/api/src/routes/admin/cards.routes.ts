/**
 * The public-card programme (spec §5.26):
 *   GET  /admin/cards                         cards directory (search, filter) — public fields only
 *   POST /admin/cards/:userId/moderate        hide a card; the owner can't republish (audited)
 *   POST /admin/cards/:userId/restore         lift the moderation (audited)
 *   POST /admin/cards/:userId/release-handle  give the handle back to the pool, e.g. impersonation (audited)
 *   GET  /admin/cards/settings · PUT          medal product link, store link, page CTA copy, reserved handles
 *   GET  /admin/cards/stats?days=30           daily counters + totals (numbers only, no visitors)
 * Never worship data: a card row is what anyone scanning it can already see.
 */
import { randomBytes } from 'node:crypto';
import { and, desc, eq, ilike, isNotNull, isNull, lt, or, sql } from 'drizzle-orm';
import type { FastifyPluginAsync, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { AdminReason, type AdminCardRow, CardsSettings } from '@yaqeen/contracts';
import type { Db } from '../../db/client.js';
import { appConfig, publicProfiles } from '../../db/schema.js';
import { audit } from '../../lib/audit.js';
import { notFound } from '../../lib/errors.js';
import { adminOf } from '../../plugins/auth.js';
import * as cardStats from '../../services/card-stats.service.js';
import { CARDS_CONFIG_KEY, readCardsSettings } from '../../services/cards-settings.service.js';
import { profileUrl } from '../../services/profile.service.js';

type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

const UserParam = z.object({ userId: z.string().uuid() });

/** Hide a card for good until support restores it. Shared with the user-detail «hide card» action. */
export async function moderateCard(tx: Db | Tx, req: FastifyRequest, userId: string, reason: string, now: Date) {
  const [before] = await tx
    .select({ handle: publicProfiles.handle, published: publicProfiles.published, moderatedAt: publicProfiles.moderatedAt })
    .from(publicProfiles)
    .where(eq(publicProfiles.userId, userId));
  if (!before) throw notFound('card');
  await tx
    .update(publicProfiles)
    .set({ published: false, moderatedAt: now, moderationReason: reason, updatedAt: now })
    .where(eq(publicProfiles.userId, userId));
  await audit(tx, req, { action: 'card.moderate', targetType: 'user', targetId: userId, reason, before, after: { published: false, moderated: true } });
}

export const adminCardsRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const read = app.requireAdmin(['support', 'marketing']);
  const support = app.requireAdmin(['support']);
  const marketing = app.requireAdmin(['marketing']);

  app.get('/', { preHandler: read }, async (req): Promise<{ items: AdminCardRow[]; nextCursor: string | null }> => {
    const q = z
      .object({
        search: z.string().trim().max(60).optional(),
        status: z.enum(['published', 'hidden', 'moderated']).optional(),
        cursor: z.iso.datetime().optional(),
        limit: z.coerce.number().int().min(1).max(100).default(50),
      })
      .parse(req.query);
    const conds = [];
    if (q.search) conds.push(or(ilike(publicProfiles.handle, `%${q.search.replace(/^@/, '')}%`), ilike(publicProfiles.displayName, `%${q.search}%`))!);
    if (q.status === 'published') conds.push(eq(publicProfiles.published, true), isNull(publicProfiles.moderatedAt));
    if (q.status === 'hidden') conds.push(eq(publicProfiles.published, false), isNull(publicProfiles.moderatedAt));
    if (q.status === 'moderated') conds.push(isNotNull(publicProfiles.moderatedAt));
    if (q.cursor) conds.push(lt(publicProfiles.updatedAt, new Date(q.cursor)));
    const rows = await db
      .select({
        p: publicProfiles,
        // Correlated subquery: columns are qualified by hand (drizzle renders them bare here).
        tags: sql<number>`(select count(*) from profile_tags t where t.user_id = public_profiles.user_id and t.disabled_at is null)::int`,
      })
      .from(publicProfiles)
      .where(conds.length ? and(...conds) : undefined)
      .orderBy(desc(publicProfiles.updatedAt))
      .limit(q.limit + 1);
    const items = rows.slice(0, q.limit).map(({ p, tags }) => ({
      userId: p.userId,
      handle: p.handle,
      displayName: p.displayName,
      bio: p.bio,
      url: profileUrl(app.ctx, p.handle),
      published: p.published,
      moderated: p.moderatedAt !== null,
      moderationReason: p.moderationReason,
      views: p.views,
      tags,
      updatedAt: p.updatedAt.toISOString(),
    }));
    return { items, nextCursor: rows.length > q.limit ? items[items.length - 1]!.updatedAt : null };
  });

  app.post('/:userId/moderate', { preHandler: support }, async (req) => {
    const { userId } = UserParam.parse(req.params);
    const { reason } = AdminReason.parse(req.body);
    await db.transaction((tx) => moderateCard(tx, req, userId, reason, app.ctx.now()));
    await app.ctx.cache.bumpNamespace('profile');
    return { ok: true };
  });

  app.post('/:userId/restore', { preHandler: support }, async (req) => {
    const { userId } = UserParam.parse(req.params);
    const { reason } = AdminReason.parse(req.body);
    await db.transaction(async (tx) => {
      const [before] = await tx
        .select({ moderatedAt: publicProfiles.moderatedAt, moderationReason: publicProfiles.moderationReason })
        .from(publicProfiles)
        .where(eq(publicProfiles.userId, userId));
      if (!before) throw notFound('card');
      // The owner decides when to publish again; restoring only lifts the block.
      await tx.update(publicProfiles).set({ moderatedAt: null, moderationReason: null, updatedAt: app.ctx.now() }).where(eq(publicProfiles.userId, userId));
      await audit(tx, req, { action: 'card.restore', targetType: 'user', targetId: userId, reason, before, after: { moderated: false } });
    });
    await app.ctx.cache.bumpNamespace('profile');
    return { ok: true };
  });

  app.post('/:userId/release-handle', { preHandler: support }, async (req) => {
    const { userId } = UserParam.parse(req.params);
    const { reason } = AdminReason.parse(req.body);
    const handle = `yaqeen_${randomBytes(3).toString('hex')}`;
    await db.transaction(async (tx) => {
      const [before] = await tx.select({ handle: publicProfiles.handle, published: publicProfiles.published }).from(publicProfiles).where(eq(publicProfiles.userId, userId));
      if (!before) throw notFound('card');
      await tx.update(publicProfiles).set({ handle, published: false, updatedAt: app.ctx.now() }).where(eq(publicProfiles.userId, userId));
      await audit(tx, req, { action: 'card.release_handle', targetType: 'user', targetId: userId, reason, before, after: { handle, published: false } });
    });
    await app.ctx.cache.bumpNamespace('profile');
    return { ok: true, handle };
  });

  app.get('/settings', { preHandler: read }, async () => readCardsSettings(app.ctx));

  app.put('/settings', { preHandler: marketing }, async (req) => {
    const next = CardsSettings.parse(req.body);
    next.reservedHandles = [...new Set(next.reservedHandles)].sort();
    await db.transaction(async (tx) => {
      const before = await readCardsSettings(app.ctx);
      await tx
        .insert(appConfig)
        .values({ key: CARDS_CONFIG_KEY, value: next, updatedBy: adminOf(req).sub })
        .onConflictDoUpdate({ target: appConfig.key, set: { value: next, updatedBy: adminOf(req).sub, updatedAt: app.ctx.now() } });
      await audit(tx, req, { action: 'cards.settings', targetType: 'config', targetId: CARDS_CONFIG_KEY, before, after: next });
    });
    await app.ctx.cache.bumpNamespace('config');
    return readCardsSettings(app.ctx);
  });

  app.get('/stats', { preHandler: read }, async (req) => {
    const { days } = z.object({ days: z.coerce.number().int().min(7).max(365).default(30) }).parse(req.query);
    return cardStats.stats(app.ctx, days);
  });
};
