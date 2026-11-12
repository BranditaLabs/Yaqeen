/**
 * Server-side `purchase` conversions: when a Yaqeen reward code is used on a paid Shopify order, tell
 * the configured ad platforms (Meta, GA4, TikTok) that a purchase happened — so campaigns that
 * brought people to the app can be measured against store sales.
 *
 * Guarantees (tested):
 *  - off unless the `serverConversions` flag is on, CONVERSIONS_ID_SALT is set and a platform has
 *    credentials;
 *  - only for a signed-in (non-guest, active) buyer whose CURRENT `ads_measurement` consent is
 *    granted when the webhook arrives — guests, withdrawn or missing consent → nothing is sent;
 *  - payloads carry only event, time, order id, total + currency and a salted per-platform hash of
 *    the user id (domain/conversions.ts) — never contact details or anything about worship;
 *  - at most one send per order and platform (`conversion_sends`); a replayed webhook only retries
 *    a send that failed, up to MAX_ATTEMPTS;
 *  - never throws into the webhook: failures are counted and reported to Sentry.
 */
import { and, asc, eq, sql } from 'drizzle-orm';
import type { AppContext } from '../context.js';
import { appConfig, consents, conversionSends, redemptions, users } from '../db/schema.js';
import { type ConversionPlatform, CONVERSION_PLATFORMS, configuredPlatforms, externalIdFor, purchaseFacts } from '../domain/conversions.js';
import { sendConversion } from '../integrations/conversions.js';
import { conversionSendsTotal } from '../lib/metrics.js';
import { captureError } from '../lib/observability.js';

export const CONVERSIONS_FLAG = 'serverConversions';
export const MAX_ATTEMPTS = 3;
const ROUTE = '/webhooks/shopify/orders-paid';

export type ConversionOutcome = 'sent' | 'failed' | 'duplicate';

/** The `serverConversions` remote-config flag — OFF unless an admin turns it on. */
export async function conversionsOn(ctx: AppContext): Promise<boolean> {
  const json = await ctx.cache.getJson('config', `feature:${CONVERSIONS_FLAG}`, 30, async () => {
    const [row] = await ctx.db.select({ value: appConfig.value }).from(appConfig).where(eq(appConfig.key, 'features'));
    return ((row?.value ?? {}) as Record<string, boolean>)[CONVERSIONS_FLAG] === true;
  });
  return JSON.parse(json) as boolean;
}

/**
 * The user the order is attributed to — the owner of the earliest-issued Yaqeen code on it — or
 * null unless that user is a real, active account with `ads_measurement` granted right now.
 */
async function consentingBuyer(ctx: AppContext, orderRef: string): Promise<string | null> {
  const [row] = await ctx.db
    .select({
      userId: redemptions.userId,
      isGuest: users.isGuest,
      status: users.status,
      mergedInto: users.mergedInto,
      deletionRequestedAt: users.deletionRequestedAt,
      granted: consents.granted,
    })
    .from(redemptions)
    .innerJoin(users, eq(users.id, redemptions.userId))
    .leftJoin(consents, and(eq(consents.userId, redemptions.userId), eq(consents.kind, 'ads_measurement')))
    .where(and(eq(redemptions.shopifyOrderId, orderRef), eq(redemptions.status, 'used')))
    .orderBy(asc(redemptions.createdAt))
    .limit(1);
  if (!row || row.isGuest || row.status !== 'active' || row.mergedInto || row.deletionRequestedAt) return null;
  return row.granted === true ? row.userId : null;
}

/** Reserve (order, platform); true when this call may send (new, or a failed one under the cap). */
async function claim(ctx: AppContext, orderId: string, platform: ConversionPlatform): Promise<boolean> {
  const rows = await ctx.db
    .insert(conversionSends)
    .values({ orderId, platform, status: 'pending' })
    .onConflictDoUpdate({
      target: [conversionSends.orderId, conversionSends.platform],
      set: { status: 'pending', attempts: sql`${conversionSends.attempts} + 1`, updatedAt: ctx.now() },
      setWhere: sql`${conversionSends.status} = 'failed' and ${conversionSends.attempts} < ${MAX_ATTEMPTS}`,
    })
    .returning({ orderId: conversionSends.orderId });
  return rows.length > 0;
}

async function record(ctx: AppContext, orderId: string, platform: ConversionPlatform, ok: boolean) {
  await ctx.db
    .update(conversionSends)
    .set(ok ? { status: 'sent', sentAt: ctx.now(), updatedAt: ctx.now() } : { status: 'failed', updatedAt: ctx.now() })
    .where(and(eq(conversionSends.orderId, orderId), eq(conversionSends.platform, platform)));
}

/**
 * Sends the order's purchase to every configured platform; returns what happened per platform
 * (empty when nothing may be sent). Never throws.
 */
export async function sendPurchaseConversions(
  ctx: AppContext,
  order: unknown,
  orderRef: string,
  fetchImpl: typeof fetch = fetch,
): Promise<Partial<Record<ConversionPlatform, ConversionOutcome>>> {
  try {
    const on = configuredPlatforms(ctx.env);
    const platforms = CONVERSION_PLATFORMS.filter((p) => on[p]);
    const salt = ctx.env.CONVERSIONS_ID_SALT;
    if (!salt || platforms.length === 0 || !orderRef) return {};
    if (!(await conversionsOn(ctx))) return {};
    const facts = purchaseFacts(order, orderRef, ctx.now());
    if (!facts) return {};
    const uid = await consentingBuyer(ctx, orderRef);
    if (!uid) return {};

    const results = await Promise.all(
      platforms.map(async (platform): Promise<[ConversionPlatform, ConversionOutcome]> => {
        if (!(await claim(ctx, facts.eventId, platform))) {
          conversionSendsTotal.inc({ platform, outcome: 'duplicate' });
          return [platform, 'duplicate'];
        }
        try {
          await sendConversion(ctx.env, platform, { ...facts, externalId: externalIdFor(salt, platform, uid) }, fetchImpl);
          await record(ctx, facts.eventId, platform, true);
          conversionSendsTotal.inc({ platform, outcome: 'sent' });
          return [platform, 'sent'];
        } catch (err) {
          await record(ctx, facts.eventId, platform, false).catch(() => undefined);
          conversionSendsTotal.inc({ platform, outcome: 'failed' });
          captureError(err, { route: ROUTE });
          return [platform, 'failed'];
        }
      }),
    );
    return Object.fromEntries(results);
  } catch (err) {
    captureError(err, { route: ROUTE });
    return {};
  }
}
