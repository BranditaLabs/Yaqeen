/**
 * Opt-in cloud backup (consent `cloud_backup`, spec §6.13): the user's device-first progress
 * (reading, notes, khatma, hifz, azkar counts, routine…) kept as one sealed JSON document per kind
 * so it comes back on a new phone.
 *
 * Rules:
 *  - signed-in (non-guest) accounts only, and only while `cloud_backup` is granted (else 403 `backup_off`);
 *  - every document is sealed with AES-256-GCM under BACKUP_SECRETS_KEY before it reaches Postgres;
 *  - optimistic concurrency per kind: a PUT names the version it merged from, a stale one is 409
 *    `backup_conflict` with the current document so the app merges and retries;
 *  - withdrawing the consent or erasure deletes every row; nothing here is read by admin routes,
 *    aggregates, product analytics or ad sinks.
 */
import { and, eq, inArray } from 'drizzle-orm';
import { BACKUP_MAX_BYTES, type BackupDocument, type BackupKind, type BackupManifest } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import type { Db } from '../db/client.js';
import { consents, userBackups, users } from '../db/schema.js';
import { AppError, conflict, forbidden, notFound } from '../lib/errors.js';
import { openSecret, sealSecret, secretsKey } from '../lib/crypto.js';

type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

const keyFor = (ctx: AppContext) => secretsKey(ctx.env.BACKUP_SECRETS_KEY, 'BACKUP_SECRETS_KEY');

export const seal = (data: unknown, key: Buffer | null) => sealSecret(JSON.stringify(data), key);
export const open = (blob: string, key: Buffer | null) => JSON.parse(openSecret(blob, key, 'BACKUP_SECRETS_KEY')) as Record<string, unknown>;

/** Throws unless the caller is a full account with the consent granted. */
export async function requireOn(db: Db, uid: string): Promise<void> {
  const [u] = await db.select({ isGuest: users.isGuest }).from(users).where(eq(users.id, uid));
  if (!u) throw notFound('user');
  if (u.isGuest) throw forbidden('account_required', 'Sign in with Google or Apple to use cloud backup');
  const [c] = await db
    .select({ granted: consents.granted })
    .from(consents)
    .where(and(eq(consents.userId, uid), eq(consents.kind, 'cloud_backup')));
  if (!c?.granted) throw forbidden('backup_off', 'Cloud backup is off for this account');
}

export async function manifest(ctx: AppContext, uid: string): Promise<BackupManifest> {
  await requireOn(ctx.db, uid);
  const rows = await ctx.db
    .select({ kind: userBackups.kind, version: userBackups.version, updatedAt: userBackups.updatedAt })
    .from(userBackups)
    .where(eq(userBackups.userId, uid));
  return { kinds: rows.map((r) => ({ kind: r.kind as BackupKind, version: r.version, updatedAt: r.updatedAt.toISOString() })) };
}

async function current(db: Db | Tx, ctx: AppContext, uid: string, kind: BackupKind): Promise<BackupDocument | null> {
  const [row] = await db
    .select()
    .from(userBackups)
    .where(and(eq(userBackups.userId, uid), eq(userBackups.kind, kind)));
  if (!row) return null;
  return { kind, version: row.version, updatedAt: row.updatedAt.toISOString(), data: open(row.blob, keyFor(ctx)) };
}

export async function get(ctx: AppContext, uid: string, kind: BackupKind): Promise<BackupDocument> {
  await requireOn(ctx.db, uid);
  const doc = await current(ctx.db, ctx, uid, kind);
  if (!doc) throw notFound('backup');
  return doc;
}

export async function put(
  ctx: AppContext,
  uid: string,
  kind: BackupKind,
  body: { baseVersion: number; data: Record<string, unknown>; deviceId?: string },
): Promise<{ version: number; updatedAt: string }> {
  await requireOn(ctx.db, uid);
  if (Buffer.byteLength(JSON.stringify(body.data), 'utf8') > BACKUP_MAX_BYTES) {
    throw new AppError(413, 'backup_too_large', `A backup document may hold at most ${BACKUP_MAX_BYTES} bytes`);
  }
  const key = keyFor(ctx);
  const now = ctx.now();
  return ctx.db.transaction(async (tx) => {
    // Row lock: two phones writing the same kind at once — one wins, the other gets the 409.
    const [row] = await tx
      .select({ version: userBackups.version })
      .from(userBackups)
      .where(and(eq(userBackups.userId, uid), eq(userBackups.kind, kind)))
      .for('update');
    const have = row?.version ?? 0;
    if (body.baseVersion !== have) {
      const doc = await current(tx, ctx, uid, kind);
      throw new AppError(409, 'backup_conflict', 'The backup changed on another device — merge and retry', doc);
    }
    const blob = seal(body.data, key);
    if (!row) {
      const inserted = await tx
        .insert(userBackups)
        .values({ userId: uid, kind, blob, version: 1, deviceId: body.deviceId ?? null, updatedAt: now })
        .onConflictDoNothing()
        .returning({ version: userBackups.version });
      // A concurrent first write landed between our read and insert.
      if (!inserted.length) throw conflict('backup_conflict', 'The backup changed on another device — merge and retry');
      return { version: 1, updatedAt: now.toISOString() };
    }
    await tx
      .update(userBackups)
      .set({ blob, version: have + 1, deviceId: body.deviceId ?? null, updatedAt: now })
      .where(and(eq(userBackups.userId, uid), eq(userBackups.kind, kind)));
    return { version: have + 1, updatedAt: now.toISOString() };
  });
}

/** Withdrawn consent or erasure: the server copy goes, in the caller's transaction. */
export async function wipe(tx: Db | Tx, uids: string[]): Promise<number> {
  if (!uids.length) return 0;
  const rows = await tx.delete(userBackups).where(inArray(userBackups.userId, uids)).returning({ kind: userBackups.kind });
  return rows.length;
}

/** For the user's own export only (never the admin export): every document, opened. */
export async function exportFor(ctx: AppContext, uid: string): Promise<BackupDocument[]> {
  const rows = await ctx.db.select().from(userBackups).where(eq(userBackups.userId, uid));
  const key = keyFor(ctx);
  return rows.map((r) => ({ kind: r.kind as BackupKind, version: r.version, updatedAt: r.updatedAt.toISOString(), data: open(r.blob, key) }));
}
