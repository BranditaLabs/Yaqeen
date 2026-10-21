import type { AppContext } from '../context.js';
import { userActivityDays, users } from '../db/schema.js';
import { localToday } from '../domain/points.js';
import { eq } from 'drizzle-orm';

/**
 * Remembers that a user opened the app today (for the DAU chart and `last_seen_at`).
 * At most one write per user per day per API instance; failures never affect the request.
 */
const seen = new Map<string, string>();
const MAX_ENTRIES = 50_000;

export function recordActivity(ctx: AppContext, userId: string): void {
  const now = ctx.now();
  const today = localToday(now);
  if (seen.get(userId) === today) return;
  if (seen.size > MAX_ENTRIES) seen.clear();
  seen.set(userId, today);
  void (async () => {
    await ctx.db.insert(userActivityDays).values({ userId, date: today }).onConflictDoNothing();
    await ctx.db.update(users).set({ lastSeenAt: now }).where(eq(users.id, userId));
  })().catch(() => seen.delete(userId));
}

/** Test hook. */
export function resetActivityCache(): void {
  seen.clear();
}
