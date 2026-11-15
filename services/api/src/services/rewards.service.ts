import { and, eq, gte, inArray, lt, sql } from 'drizzle-orm';
import type { Redemption } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import type { Db } from '../db/client.js';
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
export async function redeem(ctx: AppContext, userId: string, rewardId: string, idempotencyKey?: string): Promise<Redemption> {
  const [reward] = await ctx.db.select().from(rewards).where(eq(rewards.id, rewardId));
  if (!reward || !reward.active) throw notFound('reward');

  const now = ctx.now();
  const expiresAt = new Date(now.getTime() + reward.validityDays * 86_400_000);
  const code = generateCode();

  const redemption = await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${userId}))`);
    if (idempotencyKey) {
      const [prev] = await tx
        .select()
        .from(redemptions)
        .where(and(eq(redemptions.userId, userId), eq(redemptions.idempotencyKey, idempotencyKey)));
      if (prev) {
        // Same tap retried: the first request may still be talking to Shopify.
        if (!prev.shopifyDiscountId) throw conflict('redemption_in_progress');
        return { ...prev, replay: true as const };
      }
    }
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
      .values({ userId, rewardId: reward.id, code, costPoints: reward.costPoints, expiresAt, idempotencyKey: idempotencyKey ?? null })
      .returning();
    await tx.insert(pointsLedger).values({
      userId,
      delta: -reward.costPoints,
      reason: 'redemption',
      refKey: `redemption:${r!.id}`,
    });
    return { ...r!, replay: false as const };
  });

  if (redemption.replay) {
    return {
      id: redemption.id,
      rewardId: redemption.rewardId,
      code: redemption.code,
      status: redemption.status,
      expiresAt: redemption.expiresAt.toISOString(),
      balanceAfter: await balance(ctx, userId),
    };
  }

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
      // Free the key so the user can simply try again once the store is back.
      await tx.update(redemptions).set({ status: 'void', idempotencyKey: null }).where(eq(redemptions.id, redemption.id));
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

/**
 * Shopify orders/paid: our codes on a paid order become `used`. Idempotent (Shopify retries
 * webhooks): only `issued` codes change, so a replay or an already-expired code is a no-op.
 * Returns how many codes changed.
 */
export async function markUsed(ctx: AppContext, codes: string[], orderId: string): Promise<number> {
  if (codes.length === 0) return 0;
  const rows = await ctx.db
    .update(redemptions)
    .set({ status: 'used', usedAt: ctx.now(), shopifyOrderId: orderId })
    .where(and(inArray(redemptions.code, codes), eq(redemptions.status, 'issued')))
    .returning({ id: redemptions.id });
  return rows.length;
}

/**
 * Daily: issued codes past their date become `expired` (Shopify already rejects them at checkout).
 * Points are not returned — the reward was delivered; the code simply wasn't used in time.
 */
export async function expireDue(db: Db, now: Date): Promise<number> {
  const rows = await db
    .update(redemptions)
    .set({ status: 'expired' })
    .where(and(eq(redemptions.status, 'issued'), lt(redemptions.expiresAt, now)))
    .returning({ id: redemptions.id });
  return rows.length;
}
