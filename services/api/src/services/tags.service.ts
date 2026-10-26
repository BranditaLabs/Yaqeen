/**
 * Physical card tags — key medals and cards sold in the Yaqeen store. Each carries a permanent code
 * link `/t/<code>` (NFC chip + printed QR) minted here in batches for the manufacturer. The buyer
 * activates it in the app; from then on it opens their card, whatever their handle becomes.
 *
 * A tag is claimed once: a lost one is switched off by its owner (or support), never handed to
 * whoever finds it. Only a scan counter is kept — no visitor data.
 */
import { randomInt } from 'node:crypto';
import { and, eq, isNotNull, isNull, sql } from 'drizzle-orm';
import { type ProfileTag, type TagKind, TAG_ALPHABET, TAG_CODE_LENGTH, TAG_LIMIT_PER_USER } from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import type { Db } from '../db/client.js';
import { profileTags, publicProfiles, users } from '../db/schema.js';
import { conflict, forbidden, notFound } from '../lib/errors.js';

type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

export const tagUrl = (ctx: AppContext, code: string) => `${ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '')}/t/${code}`;

/** 32^8 ≈ 1.1 × 10¹² codes from a CSPRNG — not guessable at the claim rate limit. */
export function newCode(): string {
  let s = '';
  for (let i = 0; i < TAG_CODE_LENGTH; i++) s += TAG_ALPHABET[randomInt(TAG_ALPHABET.length)];
  return s;
}

/** Mint [count] new codes in [batch]; collisions are simply redrawn. */
export async function mintBatch(tx: Db | Tx, input: { batch: string; kind: TagKind; count: number }): Promise<string[]> {
  const codes: string[] = [];
  while (codes.length < input.count) {
    const want = Math.min(500, input.count - codes.length);
    const rows = await tx
      .insert(profileTags)
      .values(Array.from({ length: want }, () => ({ code: newCode(), kind: input.kind, batch: input.batch })))
      .onConflictDoNothing()
      .returning({ code: profileTags.code });
    codes.push(...rows.map((r) => r.code));
  }
  return codes;
}

function toTag(ctx: AppContext, r: typeof profileTags.$inferSelect): ProfileTag {
  return { code: r.code, kind: r.kind as TagKind, url: tagUrl(ctx, r.code), linkedAt: (r.linkedAt ?? r.createdAt).toISOString(), scans: r.scans };
}

/** The owner's working tags, newest first. */
export async function mine(ctx: AppContext, uid: string): Promise<ProfileTag[]> {
  const rows = await ctx.db
    .select()
    .from(profileTags)
    .where(and(eq(profileTags.userId, uid), isNull(profileTags.disabledAt)))
    .orderBy(sql`${profileTags.linkedAt} desc`);
  return rows.map((r) => toTag(ctx, r));
}

/**
 * Activate a tag for the user. Idempotent for its owner; taken, switched-off and unknown codes all
 * answer the same way so codes can't be probed for their state.
 */
export async function claim(ctx: AppContext, uid: string, guest: boolean, code: string): Promise<ProfileTag> {
  if (guest) throw forbidden('account_required', 'Sign in to activate a Yaqeen medal or card');
  const [owned] = await ctx.db
    .select()
    .from(profileTags)
    .where(and(eq(profileTags.code, code), eq(profileTags.userId, uid), isNull(profileTags.disabledAt)));
  if (owned) return toTag(ctx, owned);

  const [count] = await ctx.db
    .select({ n: sql<number>`count(*)::int` })
    .from(profileTags)
    .where(and(eq(profileTags.userId, uid), isNull(profileTags.disabledAt)));
  if ((count?.n ?? 0) >= TAG_LIMIT_PER_USER) throw conflict('tag_limit', `At most ${TAG_LIMIT_PER_USER} active tags`);

  const [row] = await ctx.db
    .update(profileTags)
    .set({ userId: uid, linkedAt: ctx.now() })
    .where(and(eq(profileTags.code, code), isNull(profileTags.userId), isNull(profileTags.disabledAt)))
    .returning();
  if (!row) throw notFound('tag');
  return toTag(ctx, row);
}

/** The owner switches a tag off (lost, given away). It stays off; support can re-issue it. */
export async function disable(ctx: AppContext, uid: string, code: string): Promise<void> {
  const rows = await ctx.db
    .update(profileTags)
    .set({ disabledAt: ctx.now() })
    .where(and(eq(profileTags.code, code), eq(profileTags.userId, uid), isNull(profileTags.disabledAt)))
    .returning({ code: profileTags.code });
  if (!rows.length) throw notFound('tag');
}

/** Erasure / suspension: every tag of the user stops resolving at once. */
export async function disableAllFor(tx: Db | Tx, uid: string, at: Date) {
  await tx
    .update(profileTags)
    .set({ disabledAt: at })
    .where(and(eq(profileTags.userId, uid), isNull(profileTags.disabledAt)));
}

export type TagTarget = { state: 'missing' } | { state: 'unclaimed'; kind: TagKind } | { state: 'linked'; handle: string | null };

/** What `/t/<code>` should do. `handle` is null when the owner's card isn't public right now. */
export async function resolve(ctx: AppContext, code: string): Promise<TagTarget> {
  const [row] = await ctx.db
    .select({
      kind: profileTags.kind,
      userId: profileTags.userId,
      disabledAt: profileTags.disabledAt,
      handle: publicProfiles.handle,
      published: publicProfiles.published,
      status: users.status,
    })
    .from(profileTags)
    .leftJoin(publicProfiles, eq(publicProfiles.userId, profileTags.userId))
    .leftJoin(users, eq(users.id, profileTags.userId))
    .where(eq(profileTags.code, code));
  if (!row || row.disabledAt) return { state: 'missing' };
  if (!row.userId) return { state: 'unclaimed', kind: row.kind as TagKind };
  return { state: 'linked', handle: row.published && row.status === 'active' ? row.handle : null };
}

export async function countScan(ctx: AppContext, code: string) {
  await ctx.db
    .update(profileTags)
    .set({ scans: sql`${profileTags.scans} + 1` })
    .where(and(eq(profileTags.code, code), isNotNull(profileTags.userId), isNull(profileTags.disabledAt)));
}
