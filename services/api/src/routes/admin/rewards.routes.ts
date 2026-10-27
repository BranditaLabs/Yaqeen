/**
 * Points & rewards control center (dashboard → النقاط والمكافآت).
 *
 *  program     global settings + the six tasks (labels, points, on/off)   super_admin
 *  milestones  automatic streak bonuses                                   super_admin
 *  bonuses     self-reported fasting / Kahf bonuses                       super_admin
 *  grants      bulk gift of points to a segment                           super_admin
 *  catalogue   Shopify rewards, caps, limits, validity                    marketing
 *  log         redemptions                                                marketing, support
 * Every write is audited in the same transaction.
 */
import { randomUUID } from 'node:crypto';
import { and, asc, desc, eq, gte, sql, type SQL } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { BonusRuleUpdate, BonusKind, GrantCreate, type GrantSegment, MilestonesUpdate, ProgramUpdate, RewardUpsert, type ShopifyStatus } from '@yaqeen/contracts';
import type { AppContext } from '../../context.js';
import { appConfig, bonusRules, pointGrants, redemptions, rewards, streakMilestones, taskRules, users } from '../../db/schema.js';
import { validateTaskRules } from '../../domain/points.js';
import { audit } from '../../lib/audit.js';
import { badRequest, notFound } from '../../lib/errors.js';
import { adminOf } from '../../plugins/auth.js';
import { POINTS_CONFIG_KEY, ensureBonusRules, getAllRules, getMilestones, getPointsSettings, totalByReason } from '../../services/program.service.js';

/** WHERE clause (on `users u`) for a grant segment. */
function grantWhere(ctx: AppContext, segment: GrantSegment): SQL {
  const base = sql`u.status = 'active' and u.is_guest = false`;
  const weekAgo = new Date(ctx.now().getTime() - 7 * 86_400_000);
  switch (segment) {
    case 'all_users':
      return base;
    case 'all_enrolled':
      return sql`${base} and exists (select 1 from challenge_enrollments ce where ce.user_id = u.id)`;
    case 'active_7d':
      return sql`${base} and u.last_seen_at >= ${weekAgo}`;
    case 'streak_gte_7':
      return sql`${base} and (select count(distinct tc.date) from task_completions tc
                 where tc.user_id = u.id and tc.date >= current_date - 7 and tc.date < current_date) >= 7`;
  }
}

async function countSegment(ctx: AppContext, segment: GrantSegment): Promise<number> {
  const res = await ctx.db.execute(sql`select count(*)::int as n from users u where ${grantWhere(ctx, segment)}`);
  return Number((res.rows[0] as { n: number } | undefined)?.n ?? 0);
}

export const adminRewardsRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const superOnly = app.requireAdmin([]);
  const read = app.requireAdmin(['marketing', 'support']);
  const marketing = app.requireAdmin(['marketing']);

  /* ------------------------------------------------------------ program */

  app.get('/program', { preHandler: read }, async () => {
    await ensureBonusRules(db);
    const [settings, tasks, bonuses, milestones, totals] = await Promise.all([
      getPointsSettings(app.ctx),
      getAllRules(app.ctx),
      db.select().from(bonusRules),
      getMilestones(app.ctx),
      totalByReason(app.ctx),
    ]);
    return {
      settings,
      tasks: tasks.map((t) => ({ key: t.key, labelAr: t.labelAr, labelEn: t.labelEn, points: t.points, active: t.active })),
      bonuses,
      milestones,
      totals: Object.fromEntries(totals.map((t) => [t.reason, Number(t.total)])),
    };
  });

  /** Settings + tasks together: active task values must add up to the daily total. */
  app.put('/program', { preHandler: superOnly }, async (req) => {
    const body = ProgramUpdate.parse(req.body);
    if (new Set(body.tasks.map((t) => t.key)).size !== 6) throw badRequest('duplicate_task');
    const check = validateTaskRules(body.tasks.filter((t) => t.active), body.settings.dailyTotal);
    if (!check.ok) throw badRequest('invalid_total', check.error);

    await db.transaction(async (tx) => {
      const before = { settings: await getPointsSettings(app.ctx), tasks: await getAllRules(app.ctx) };
      await tx
        .insert(appConfig)
        .values({ key: POINTS_CONFIG_KEY, value: body.settings, updatedBy: adminOf(req).sub })
        .onConflictDoUpdate({ target: appConfig.key, set: { value: body.settings, updatedBy: adminOf(req).sub, updatedAt: app.ctx.now() } });
      for (const t of body.tasks) {
        await tx
          .update(taskRules)
          .set({ labelAr: t.labelAr, labelEn: t.labelEn, points: t.points, active: t.active, updatedAt: app.ctx.now() })
          .where(eq(taskRules.key, t.key));
      }
      await audit(tx, req, { action: 'points.program.update', targetType: 'points_program', before, after: body });
    });
    return { ok: true };
  });

  /* ---------------------------------------------------------- milestones */

  /** Replaces the whole list. Already-awarded milestones stay awarded (ledger is append-only). */
  app.put('/milestones', { preHandler: superOnly }, async (req) => {
    const body = MilestonesUpdate.parse(req.body);
    await db.transaction(async (tx) => {
      const before = await tx.select().from(streakMilestones);
      await tx.delete(streakMilestones);
      if (body.length) await tx.insert(streakMilestones).values(body);
      await audit(tx, req, { action: 'points.milestones.update', targetType: 'streak_milestones', before, after: body });
    });
    return { ok: true };
  });

  /* ------------------------------------------------------------- bonuses */

  app.put('/bonus-rules/:kind', { preHandler: superOnly }, async (req) => {
    const { kind } = z.object({ kind: BonusKind }).parse(req.params);
    const body = BonusRuleUpdate.parse(req.body);
    await db.transaction(async (tx) => {
      const [before] = await tx.select().from(bonusRules).where(eq(bonusRules.kind, kind));
      if (!before) throw notFound('bonus_rule');
      await tx.update(bonusRules).set({ ...body, updatedAt: app.ctx.now() }).where(eq(bonusRules.kind, kind));
      await audit(tx, req, { action: 'bonus_rule.update', targetType: 'bonus_rule', targetId: kind, before, after: body });
    });
    return { ok: true };
  });

  /* -------------------------------------------------------------- grants */

  app.get('/grants', { preHandler: read }, async () => db.select().from(pointGrants).orderBy(desc(pointGrants.createdAt)).limit(50));

  app.post('/grants/preview', { preHandler: superOnly }, async (req) => {
    const body = GrantCreate.parse(req.body);
    const recipients = await countSegment(app.ctx, body.segment);
    return { recipients, totalPoints: recipients * body.points };
  });

  /** One ledger row per recipient (`grant:<id>`), all in one statement + transaction. */
  app.post('/grants', { preHandler: superOnly }, async (req) => {
    const body = GrantCreate.parse(req.body);
    const id = randomUUID();
    const recipients = await db.transaction(async (tx) => {
      const res = await tx.execute(sql`
        insert into points_ledger (user_id, delta, reason, ref_key, note)
        select u.id, ${body.points}, 'grant', ${`grant:${id}`}, ${body.reasonAr}
        from users u where ${grantWhere(app.ctx, body.segment)}
        on conflict do nothing`);
      const n = res.rowCount ?? 0;
      await tx.insert(pointGrants).values({ id, ...body, recipients: n, createdBy: adminOf(req).sub });
      await audit(tx, req, { action: 'points.grant', targetType: 'point_grant', targetId: id, reason: body.reasonAr, after: { ...body, recipients: n } });
      return n;
    });
    return { id, recipients };
  });

  /* ------------------------------------------------------------- shopify */

  /** Connection pill «متصل · yaqin-brand.com». Never throws: a broken connection is a status. */
  app.get('/shopify/status', { preHandler: read }, async (): Promise<ShopifyStatus> => {
    const shop = app.ctx.shopify;
    const [w] = await db.select({ at: sql<Date | null>`max(${redemptions.usedAt})` }).from(redemptions);
    const webhook = { configured: Boolean(app.ctx.env.SHOPIFY_WEBHOOK_SECRET), lastUsedAt: w?.at ? new Date(w.at).toISOString() : null };
    const base = { configured: shop.configured, connected: false, shopName: null, domain: shop.domain || null, scopes: [] as string[], webhook };
    const last = () => ({ lastError: shop.lastError?.message ?? null, lastErrorAt: shop.lastError?.at.toISOString() ?? null });
    if (!shop.configured) return { ...base, ...last() };
    try {
      const info = await shop.shopInfo();
      return { configured: true, connected: true, shopName: info.shopName, domain: info.domain, scopes: info.scopes, webhook, ...last() };
    } catch {
      return { ...base, ...last() };
    }
  });

  /** Collections for "+ مكافأة من منتجات Shopify". */
  app.get('/shopify/collections', { preHandler: marketing }, async (req) => {
    const q = z.object({ search: z.string().max(60).optional() }).parse(req.query);
    return app.ctx.shopify.collections(q.search);
  });

  /* ----------------------------------------------------------- catalogue */

  app.get('/', { preHandler: read }, async () => {
    const monthStart = new Date(Date.UTC(app.ctx.now().getUTCFullYear(), app.ctx.now().getUTCMonth(), 1));
    const rows = await db.select().from(rewards).orderBy(asc(rewards.costPoints));
    const used = await db
      .select({ rewardId: redemptions.rewardId, n: sql<string>`count(*)` })
      .from(redemptions)
      .where(and(gte(redemptions.createdAt, monthStart), sql`${redemptions.status} <> 'void'`))
      .groupBy(redemptions.rewardId);
    const usedMap = new Map(used.map((u) => [u.rewardId, Number(u.n)]));
    return rows.map((r) => ({ ...r, redeemedThisMonth: usedMap.get(r.id) ?? 0 }));
  });

  app.post('/', { preHandler: marketing }, async (req) => {
    const body = RewardUpsert.parse(req.body);
    return db.transaction(async (tx) => {
      const [row] = await tx.insert(rewards).values({ ...body, value: Math.round(body.value) }).returning();
      await audit(tx, req, { action: 'reward.create', targetType: 'reward', targetId: row!.id, after: row });
      return row;
    });
  });

  app.put('/:id', { preHandler: marketing }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const body = RewardUpsert.parse(req.body);
    return db.transaction(async (tx) => {
      const [before] = await tx.select().from(rewards).where(eq(rewards.id, id));
      if (!before) throw notFound('reward');
      const [row] = await tx
        .update(rewards)
        .set({ ...body, value: Math.round(body.value), updatedAt: app.ctx.now() })
        .where(eq(rewards.id, id))
        .returning();
      await audit(tx, req, { action: 'reward.update', targetType: 'reward', targetId: id, before, after: row });
      return row;
    });
  });

  /* ----------------------------------------------------------------- log */

  app.get('/redemptions', { preHandler: read }, async () =>
    db
      .select({
        id: redemptions.id,
        code: redemptions.code,
        status: redemptions.status,
        costPoints: redemptions.costPoints,
        createdAt: redemptions.createdAt,
        expiresAt: redemptions.expiresAt,
        reward: rewards.titleAr,
        user: users.displayName,
      })
      .from(redemptions)
      .innerJoin(rewards, eq(rewards.id, redemptions.rewardId))
      .innerJoin(users, eq(users.id, redemptions.userId))
      .orderBy(desc(redemptions.createdAt))
      .limit(200),
  );
};
