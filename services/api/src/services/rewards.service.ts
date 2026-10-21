import { and, eq, gte, sql } from 'drizzle-orm';
import type { Redemption } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { pointsLedger, redemptions, rewards } from '../db/schema.js';
import { canAfford } from '../domain/points.js';
import { buildDiscountRequest, generateCode } from '../domain/shopify.js';
import { AppError, badRequest, conflict, notFound } from '../lib/errors.js';
import { balance } from './challenge.service.js';

/**
 * Redeem points for a Shopify discount code.
 *
 * Order matters: points are debited in a DB transaction FIRST (with a per-user advisory
 * lock so two taps can't overspend), then Shopify is called. If Shopify fails, the debit
 * is reversed with a compensating ledger row and the redemption is voided.
 */
export async function redeem(ctx: AppContext, userId: string, rewardId: string): Promise<Redemption> {
  const [reward] = await ctx.db.select().from(rewards).where(eq(rewards.id, rewardId));
  if (!reward || !reward.active) throw notFound('reward');

  const now = ctx.now();
  const expiresAt = new Date(now.getTime() + reward.validityDays * 86_400_000);
  const code = generateCode();

  const redemption = await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${userId}))`);
    const [b] = await tx
      .select({ total: sql<string>`coalesce(sum(${pointsLedger.delta}), 0)` })
      .from(pointsLedger)
      .where(eq(pointsLedger.userId, userId));
    if (!canAfford(Number(b?.total ?? 0), reward.costPoints)) throw badRequest('insufficient_points');

    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    if (reward.perUserMonthlyLimit) {
      const [mine] = await tx
        .select({ n: sql<string>`count(*)` })
        .from(redemptions)
        .where(
          and(
            eq(redemptions.rewardId, reward.id),
            eq(redemptions.userId, userId),
            gte(redemptions.createdAt, monthStart),
            sql`${redemptions.status} <> 'void'`,
          ),
        );
      if (Number(mine?.n ?? 0) >= reward.perUserMonthlyLimit) throw conflict('user_reward_limit_reached');
    }
    if (reward.monthlyCap) {
      const [c] = await tx
        .select({ n: sql<string>`count(*)` })
        .from(redemptions)
        .where(and(eq(redemptions.rewardId, reward.id), gte(redemptions.createdAt, monthStart), sql`${redemptions.status} <> 'void'`));
      if (Number(c?.n ?? 0) >= reward.monthlyCap) throw conflict('reward_out_of_stock');
    }

    const [r] = await tx
      .insert(redemptions)
      .values({ userId, rewardId: reward.id, code, costPoints: reward.costPoints, expiresAt })
      .returning();
    await tx.insert(pointsLedger).values({
      userId,
      delta: -reward.costPoints,
      reason: 'redemption',
      refKey: `redemption:${r!.id}`,
    });
    return r!;
  });

  try {
    const discountId = await ctx.shopify.createDiscount(
      buildDiscountRequest({
        code,
        title: `Yaqeen · ${reward.titleEn} · ${redemption.id.slice(0, 8)}`,
        kind: reward.kind,
        value: reward.value,
        collectionIds: reward.shopifyCollectionIds,
        startsAt: now,
        endsAt: expiresAt,
      }),
    );
    await ctx.db.update(redemptions).set({ shopifyDiscountId: discountId }).where(eq(redemptions.id, redemption.id));
  } catch (err) {
    await ctx.db.transaction(async (tx) => {
      await tx.update(redemptions).set({ status: 'void' }).where(eq(redemptions.id, redemption.id));
      await tx.insert(pointsLedger).values({
        userId,
        delta: reward.costPoints,
        reason: 'reversal',
        refKey: `reversal:redemption:${redemption.id}`,
        note: 'Shopify discount creation failed',
      });
    });
    // One stable code for the app («المتجر غير متاح الآن، لم تُخصم نقاطك»); details stay in the message.
    throw new AppError(503, 'shopify_unavailable', err instanceof Error ? err.message : 'Shopify unavailable');
  }

  return {
    id: redemption.id,
    rewardId: reward.id,
    code,
    status: 'issued',
    expiresAt: expiresAt.toISOString(),
    balanceAfter: await balance(ctx, userId),
  };
}
