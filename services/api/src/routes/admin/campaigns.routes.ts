import { desc, eq, gte, sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { CampaignCreate, type CampaignKind, type CampaignSegment, type ConsentKind } from '@yaqeen/contracts';
import type { AppContext } from '../../context.js';
import { campaigns, consents, devices, pointsLedger, users } from '../../db/schema.js';
import { CONSENT_FOR_KIND, lintCampaignCopy } from '../../domain/guardrails.js';
import { audit } from '../../lib/audit.js';
import { badRequest, conflict, notFound } from '../../lib/errors.js';
import { adminOf } from '../../plugins/auth.js';

/**
 * SQL for a segment → user ids that also granted the consent bucket for `kind`
 * and have at least one valid device. Shared with the dispatcher job.
 */
export function segmentQuery(ctx: AppContext, segment: CampaignSegment, consentKind: ConsentKind) {
  const { db } = ctx;
  const now = ctx.now();
  const base = db
    .selectDistinct({ userId: users.id })
    .from(users)
    .innerJoin(consents, sql`${consents.userId} = ${users.id} and ${consents.kind} = ${consentKind} and ${consents.granted}`)
    .innerJoin(devices, sql`${devices.userId} = ${users.id} and ${devices.invalidatedAt} is null`);

  const active = sql`${users.status} = 'active'`;
  const bal = sql`coalesce((select sum(${pointsLedger.delta}) from ${pointsLedger} where ${pointsLedger.userId} = ${users.id}), 0)`;
  switch (segment) {
    case 'all':
      return base.where(active);
    case 'balance_gte_1000':
      return base.where(sql`${active} and ${bal} >= 1000`);
    case 'inactive_7d':
      return base.where(sql`${active} and ${users.lastSeenAt} < ${new Date(now.getTime() - 7 * 86_400_000)}`);
    case 'missed_yesterday':
      return base.where(
        sql`${active} and exists (select 1 from challenge_enrollments ce where ce.user_id = ${users.id})
            and not exists (select 1 from task_completions tc where tc.user_id = ${users.id} and tc.date = (current_date - 1))`,
      );
    case 'streak_gte_7':
      // Approximation for targeting: completed every task on each of the last 7 days.
      return base.where(
        sql`${active} and (select count(distinct tc.date) from task_completions tc where tc.user_id = ${users.id}
            and tc.date >= current_date - 7 and tc.date < current_date) >= 7`,
      );
  }
}

const consentFor = (kind: CampaignKind): ConsentKind => CONSENT_FOR_KIND[kind];

export const adminCampaignRoutes: FastifyPluginAsync = async (app) => {
  const { db } = app.ctx;
  const marketing = app.requireAdmin(['marketing']);

  app.get('/', { preHandler: marketing }, async () => db.select().from(campaigns).orderBy(desc(campaigns.createdAt)).limit(100));

  /** Dry run: reach estimate + copy lint, without saving. */
  app.post('/preview', { preHandler: marketing }, async (req) => {
    const body = CampaignCreate.parse(req.body);
    const rows = await segmentQuery(app.ctx, body.segment, consentFor(body.kind));
    return { estimatedReach: rows.length, issues: lintCampaignCopy(body) };
  });

  app.post('/', { preHandler: marketing }, async (req) => {
    const body = CampaignCreate.parse(req.body);
    if (body.schedule === 'scheduled' && !body.scheduledAt) throw badRequest('scheduled_at_required');
    const issues = lintCampaignCopy(body);
    if (issues.length) throw badRequest('copy_issues', issues.join(' · '), issues);
    const reach = (await segmentQuery(app.ctx, body.segment, consentFor(body.kind))).length;
    return db.transaction(async (tx) => {
      const [row] = await tx
        .insert(campaigns)
        .values({
          ...body,
          // 'now' and 'smart' are due immediately; the dispatcher applies guardrails per user.
          scheduledAt: body.schedule === 'scheduled' && body.scheduledAt ? new Date(body.scheduledAt) : app.ctx.now(),
          status: 'scheduled',
          estimatedReach: reach,
          createdBy: adminOf(req).sub,
        })
        .returning();
      await audit(tx, req, { action: 'campaign.create', targetType: 'campaign', targetId: row!.id, after: row });
      return row;
    });
  });

  app.post('/:id/cancel', { preHandler: marketing }, async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    return db.transaction(async (tx) => {
      const [before] = await tx.select().from(campaigns).where(eq(campaigns.id, id));
      if (!before) throw notFound('campaign');
      if (!['draft', 'scheduled'].includes(before.status)) throw conflict('not_cancellable');
      await tx.update(campaigns).set({ status: 'cancelled', updatedAt: app.ctx.now() }).where(eq(campaigns.id, id));
      await audit(tx, req, { action: 'campaign.cancel', targetType: 'campaign', targetId: id, before: { status: before.status } });
      return { ok: true };
    });
  });

  /** Campaigns sent in the last 30 days with open rate. */
  app.get('/stats', { preHandler: marketing }, async () => {
    const since = new Date(app.ctx.now().getTime() - 30 * 86_400_000);
    return db
      .select({ id: campaigns.id, name: campaigns.name, sent: campaigns.sentCount, opened: campaigns.openCount })
      .from(campaigns)
      .where(gte(campaigns.createdAt, since))
      .orderBy(desc(campaigns.createdAt));
  });

};
