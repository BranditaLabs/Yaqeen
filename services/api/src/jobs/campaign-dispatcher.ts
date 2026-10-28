/**
 * Campaign dispatcher — run every 10 minutes (cron / Cloud Scheduler / k8s CronJob):
 *   pnpm --filter @yaqeen/api job:campaigns
 *
 * For each due campaign, sends to every eligible user who passes the guardrails right now.
 * Users blocked by a *time* rule (quiet hours, near prayer, Jumu'ah) are retried on the next
 * run for `smart` campaigns until 22:00 local; other campaigns finish in one pass.
 */
import { and, eq, gte, inArray, isNull, lte, sql } from 'drizzle-orm';
import { Redis } from 'ioredis';
import type { CampaignKind, CampaignSegment, ConsentKind } from '@yaqeen/contracts';
import { loadEnv } from '../config/env.js';
import type { AppContext } from '../context.js';
import { createDb } from '../db/client.js';
import { campaignDeliveries, campaigns, devices, users } from '../db/schema.js';
import { CONSENT_FOR_KIND, QUIET_START_MIN, checkSend, localClock } from '../domain/guardrails.js';
import { coordsFor, prayerMinutes } from '../domain/prayer-times.js';
import { AlAdhanClient } from '../integrations/aladhan.js';
import { FcmSender } from '../integrations/fcm.js';
import { ShopifyClient } from '../integrations/shopify.js';
import { ResponseCache } from '../lib/cache.js';
import { segmentQuery } from '../routes/admin/campaigns.routes.js';
import { runJob } from '../lib/observability.js';
import { withJobLock } from './lock.js';

const DEEP_LINK_PREFIX = 'yaqeen://';
const TIME_REASONS = new Set(['quiet_hours', 'near_prayer', 'jumuah']);

export async function dispatchDue(ctx: AppContext): Promise<void> {
  const { db } = ctx;
  const now = ctx.now();
  const due = await db
    .select()
    .from(campaigns)
    .where(and(inArray(campaigns.status, ['scheduled', 'sending']), lte(campaigns.scheduledAt, now)));

  for (const c of due) {
    await db.update(campaigns).set({ status: 'sending', updatedAt: now }).where(eq(campaigns.id, c.id));
    const kind = c.kind as CampaignKind;
    const consentKind: ConsentKind = CONSENT_FOR_KIND[kind];
    const audience = (await segmentQuery(ctx, c.segment as CampaignSegment, consentKind)).map((r) => r.userId);

    const already = new Set(
      (await db.select({ u: campaignDeliveries.userId }).from(campaignDeliveries).where(eq(campaignDeliveries.campaignId, c.id))).map((r) => r.u),
    );
    const pending = audience.filter((u) => !already.has(u));
    let deferred = 0;
    let sent = 0;

    for (let i = 0; i < pending.length; i += 500) {
      const chunk = pending.slice(i, i + 500);
      const people = await db
        .select({ id: users.id, tz: users.timezone, locale: users.locale, city: users.city, method: users.prayerMethod })
        .from(users)
        .where(inArray(users.id, chunk));
      const dayAgo = new Date(now.getTime() - 24 * 3600_000);
      const counts = await db
        .select({ u: campaignDeliveries.userId, n: sql<string>`count(*)` })
        .from(campaignDeliveries)
        .where(and(inArray(campaignDeliveries.userId, chunk), eq(campaignDeliveries.kind, kind), gte(campaignDeliveries.sentAt, dayAgo)))
        .groupBy(campaignDeliveries.userId);
      const sentToday = new Map(counts.map((r) => [r.u, Number(r.n)]));

      const allowed: typeof people = [];
      for (const p of people) {
        const res = checkSend({
          kind,
          clock: localClock(now, p.tz),
          prayerMinutes: prayerMinutes(now, p.tz, coordsFor(p.city, p.tz), p.method),
          consents: { [consentKind]: true }, // segmentQuery already filtered on consent
          sentTodayOfKind: sentToday.get(p.id) ?? 0,
        });
        if (res.ok) allowed.push(p);
        else if (TIME_REASONS.has(res.reason)) deferred++;
      }
      if (allowed.length === 0) continue;

      const toks = await db
        .select({ userId: devices.userId, token: devices.fcmToken })
        .from(devices)
        .where(and(inArray(devices.userId, allowed.map((a) => a.id)), isNull(devices.invalidatedAt)));
      const localeOf = new Map(allowed.map((a) => [a.id, a.locale]));
      const result = await ctx.fcm.sendMany(
        toks.map((t) => ({
          token: t.token,
          title: localeOf.get(t.userId) === 'en' ? c.titleEn : c.titleAr,
          body: localeOf.get(t.userId) === 'en' ? c.bodyEn : c.bodyAr,
          link: `${DEEP_LINK_PREFIX}${c.deepLink}`,
          campaignId: c.id,
          kind,
        })),
      );
      if (result.invalidTokens.length) {
        await db.update(devices).set({ invalidatedAt: now }).where(inArray(devices.fcmToken, result.invalidTokens));
      }
      await db
        .insert(campaignDeliveries)
        .values(allowed.map((a) => ({ campaignId: c.id, userId: a.id, kind })))
        .onConflictDoNothing();
      sent += allowed.length;
    }

    const cairo = localClock(now, 'Africa/Cairo');
    const keepGoing = c.schedule === 'smart' && deferred > 0 && cairo.minutes < QUIET_START_MIN;
    await db
      .update(campaigns)
      .set({ status: keepGoing ? 'sending' : 'sent', sentCount: sql`${campaigns.sentCount} + ${sent}`, updatedAt: now })
      .where(eq(campaigns.id, c.id));
    console.log(`[campaigns] ${c.name}: sent ${sent}, deferred ${deferred}${keepGoing ? ' (will retry)' : ''}`);
  }
}

// Run directly
if (import.meta.url === `file://${process.argv[1]}`) {
  const env = loadEnv();
  const { db, pool } = createDb(env.DATABASE_URL);
  const redis = new Redis(env.REDIS_URL);
  const res = await runJob(env, 'yaqeen-campaigns', '*/10 * * * *', () => withJobLock(pool, 'campaign-dispatcher', () => dispatchDue({
    env,
    db,
    redis,
    cache: new ResponseCache(redis),
    aladhan: new AlAdhanClient(env.ALADHAN_BASE_URL, redis),
    shopify: new ShopifyClient({ shopDomain: env.SHOPIFY_SHOP_DOMAIN, adminToken: env.SHOPIFY_ADMIN_TOKEN, apiVersion: env.SHOPIFY_API_VERSION }),
    fcm: new FcmSender(env.FIREBASE_SERVICE_ACCOUNT_JSON),
    now: () => new Date(),
  })));
  if (!res.ran) console.log('[campaigns] another dispatcher is running — skipped');
  await pool.end();
  redis.disconnect();
}
