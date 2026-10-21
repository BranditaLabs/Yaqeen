/**
 * PDPL erasure — run daily:  pnpm --filter @yaqeen/api job:purge
 *
 * Accounts whose deletion was requested more than DELETION_GRACE_DAYS ago are anonymised:
 * identities, sessions, devices, consents, worship records and activity are deleted; the user
 * row stays as an anonymous tombstone so the append-only points ledger and redemptions still
 * add up for accounting. Consent events (the legal record of what was agreed) are kept.
 */
import { and, eq, inArray, lt } from 'drizzle-orm';
import { loadEnv } from '../config/env.js';
import type { Db } from '../db/client.js';
import { createDb } from '../db/client.js';
import {
  authIdentities,
  challengeEnrollments,
  consents,
  devices,
  refreshTokens,
  taskCompletions,
  userActivityDays,
  users,
} from '../db/schema.js';
import { DELETION_GRACE_DAYS } from '../routes/public/me.routes.js';

export async function purgeDeleted(db: Db, now: Date): Promise<number> {
  const cutoff = new Date(now.getTime() - DELETION_GRACE_DAYS * 86_400_000);
  const due = await db
    .select({ id: users.id })
    .from(users)
    .where(and(eq(users.status, 'deletion_requested'), lt(users.deletionRequestedAt, cutoff)));
  if (due.length === 0) return 0;
  const ids = due.map((u) => u.id);
  await db.transaction(async (tx) => {
    for (const t of [authIdentities, refreshTokens, devices, consents, taskCompletions, challengeEnrollments, userActivityDays]) {
      await tx.delete(t).where(inArray(t.userId, ids));
    }
    await tx
      .update(users)
      .set({ status: 'deleted', displayName: null, email: null, city: null, lastSeenAt: null, updatedAt: now })
      .where(inArray(users.id, ids));
  });
  return ids.length;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const env = loadEnv();
  const { db, pool } = createDb(env.DATABASE_URL);
  const n = await purgeDeleted(db, new Date());
  console.log(`[purge] anonymised ${n} account(s)`);
  await pool.end();
}
