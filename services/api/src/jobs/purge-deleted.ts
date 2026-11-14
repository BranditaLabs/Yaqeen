/**
 * PDPL erasure — run daily:  pnpm --filter @yaqeen/api job:purge
 *
 * Accounts whose deletion was requested more than DELETION_GRACE_DAYS ago are anonymised:
 * identities, sessions, devices, consents, worship records, activity, the opt-in cloud backup and the
 * public card (handle, name, bio, links) are deleted; their medal tags are unlinked and stay switched off; the user
 * row stays as an anonymous tombstone so the append-only points ledger and redemptions still
 * add up for accounting. Consent events (the legal record of what was agreed) are kept. Every
 * community row (photos, switches, blocks both ways, league/tournament rows, badges, reports in both
 * roles, snapshots, rollups) is deleted and the identity columns nulled (purgeCommunity).
 *
 * The same daily run drops product events past retention, marks unused reward codes expired and
 * deletes replaced/removed profile photos older than 7 days.
 */
import { and, eq, inArray, lt, sql } from 'drizzle-orm';
import { loadEnv } from '../config/env.js';
import type { Db } from '../db/client.js';
import { createDb } from '../db/client.js';
import {
  authIdentities,
  challengeEnrollments,
  consents,
  devices,
  profileTags,
  publicProfiles,
  refreshTokens,
  taskCompletions,
  userActivityDays,
  users,
} from '../db/schema.js';
import { DELETION_GRACE_DAYS } from '../routes/public/me.routes.js';
import { runJob } from '../lib/observability.js';
import { RETENTION_DAYS, purgeOld } from '../services/product-analytics.service.js';
import { expireDue } from '../services/rewards.service.js';
import { wipe as wipeBackups } from '../services/backup.service.js';
import { PHOTO_RETENTION_DAYS, purgeOldPhotos } from '../services/avatar.service.js';
import { withJobLock } from './lock.js';

export async function purgeDeleted(db: Db, now: Date): Promise<number> {
  const cutoff = new Date(now.getTime() - DELETION_GRACE_DAYS * 86_400_000);
  const due = await db
    .select({ id: users.id })
    .from(users)
    .where(and(eq(users.status, 'deletion_requested'), lt(users.deletionRequestedAt, cutoff)));
  if (due.length === 0) return 0;
  const ids = due.map((u) => u.id);
  await db.transaction(async (tx) => {
    for (const t of [authIdentities, refreshTokens, devices, consents, taskCompletions, challengeEnrollments, userActivityDays, publicProfiles]) {
      await tx.delete(t).where(inArray(t.userId, ids));
    }
    // The user row is a tombstone (no cascade), so the backup goes explicitly.
    await wipeBackups(tx, ids);
    await purgeCommunity(tx, ids);
    await tx
      .update(profileTags)
      .set({ userId: null, linkedAt: null, disabledAt: sql`coalesce(${profileTags.disabledAt}, ${now})` })
      .where(inArray(profileTags.userId, ids));
    await tx
      .update(users)
      .set({ status: 'deleted', displayName: null, email: null, city: null, lastSeenAt: null, updatedAt: now })
      .where(inArray(users.id, ids));
  });
  return ids.length;
}

/**
 * Every row with a user FK added in migration 0017 (design §4.4): the tombstone never cascades, so
 * each table goes explicitly (purge.db test enumerates them), and the identity columns are nulled.
 * `points_earned_daily` / `user_point_totals` are derived caches; `yq_rebuild_points_rollups()`
 * would recreate them from the anonymised ledger, which is fine (no identity in them).
 */
export const COMMUNITY_USER_TABLES = [
  ['avatar_photos', ['user_id']],
  ['community_members', ['user_id']],
  ['community_blocks', ['user_id', 'blocked_user_id']],
  ['league_members', ['user_id']],
  ['tournament_entries', ['user_id']],
  ['user_badges', ['user_id']],
  ['community_reports', ['reporter_id', 'target_user_id']],
  ['leaderboard_snapshot', ['user_id']],
  ['points_earned_daily', ['user_id']],
  ['user_point_totals', ['user_id']],
] as const;

export async function purgeCommunity(tx: Parameters<Parameters<Db['transaction']>[0]>[0] | Db, ids: string[]): Promise<void> {
  if (!ids.length) return;
  const list = JSON.stringify(ids);
  // The active photo FK goes first so the photos can be deleted.
  await tx.execute(sql`
    update users set avatar_photo_id = null, avatar_kind = 'initial', avatar_preset = null, country = null,
      name_hidden_at = null, name_hidden_reason = null, photo_locked_at = null, adult_attested_at = null
    where id in (select x::uuid from jsonb_array_elements_text(${list}::jsonb) as x)`);
  for (const [table, cols] of COMMUNITY_USER_TABLES) {
    const where = sql.join(
      cols.map((c) => sql`${sql.raw(c)} in (select x::uuid from jsonb_array_elements_text(${list}::jsonb) as x)`),
      sql` or `,
    );
    await tx.execute(sql`delete from ${sql.raw(table)} where ${where}`);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const env = loadEnv();
  const { db, pool } = createDb(env.DATABASE_URL);
  const res = await runJob(env, 'yaqeen-purge', '17 1 * * *', () => withJobLock(pool, 'purge-deleted', () => purgeDeleted(db, new Date())));
  console.log(res.ran ? `[purge] anonymised ${res.result} account(s)` : '[purge] another run in progress — skipped');
  if (res.ran) {
    console.log(`[purge] removed ${await purgeOld(db, new Date())} product event(s) older than ${RETENTION_DAYS} days`);
    console.log(`[purge] expired ${await expireDue(db, new Date())} unused reward code(s)`);
    console.log(`[purge] removed ${await purgeOldPhotos(db, new Date())} replaced/removed photo(s) older than ${PHOTO_RETENTION_DAYS} days`);
  }
  await pool.end();
}
