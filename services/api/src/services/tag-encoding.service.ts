/**
 * Staff encoding of medal chips (spec §5.26 › in-house encoding). Marketing opens a short-lived
 * session for one batch in admin; a staff phone opens `yaqeen://encode/<token>` and writes
 * `/t/<code>` onto blank chips, reporting each write back.
 *
 * The token is a capability scoped to one batch — no admin credentials ever reach the app. Only its
 * SHA-256 is stored; unknown, expired, revoked and voided-batch sessions all look the same (404).
 */
import { createHash, randomBytes } from 'node:crypto';
import { and, eq, gt, isNotNull, isNull, sql } from 'drizzle-orm';
import {
  type AdminEncodeSession,
  ENCODE_SESSION_HOURS,
  ENCODE_TOKEN,
  type EncodeSessionView,
  type EncodeWrittenRequest,
  type EncodeWrittenResponse,
  type TagKind,
} from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import type { Db } from '../db/client.js';
import { profileTags, tagBatches, tagEncodeSessions } from '../db/schema.js';
import { AppError, conflict } from '../lib/errors.js';

type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];

/** 32 random bytes, base64url (43 chars). */
export const newEncodeToken = () => randomBytes(32).toString('base64url');
export const hashEncodeToken = (token: string) => createHash('sha256').update(token).digest('hex');
export const encodeDeepLink = (token: string) => `yaqeen://encode/${token}`;
export const sessionTtlMs = ENCODE_SESSION_HOURS * 60 * 60 * 1000;

/** The one answer for every session that can't be used — nothing to tell them apart. */
export const sessionGone = () => new AppError(404, 'not_found', 'encoding session not found');

export function toAdminSession(r: typeof tagEncodeSessions.$inferSelect, now: Date): AdminEncodeSession {
  return {
    id: r.id,
    batch: r.batch,
    createdAt: r.createdAt.toISOString(),
    expiresAt: r.expiresAt.toISOString(),
    revokedAt: r.revokedAt?.toISOString() ?? null,
    active: !r.revokedAt && r.expiresAt > now,
  };
}

export async function createSession(tx: Db | Tx, now: Date, batch: string, createdBy: string) {
  const token = newEncodeToken();
  const [row] = await tx
    .insert(tagEncodeSessions)
    .values({ batch, tokenHash: hashEncodeToken(token), createdBy, expiresAt: new Date(now.getTime() + sessionTtlMs), createdAt: now })
    .returning();
  return { token, row: row! };
}

/** A live session for [token] on a batch that isn't void, or throws [sessionGone]. */
async function liveSession(ctx: AppContext, token: string) {
  if (!ENCODE_TOKEN.test(token)) throw sessionGone();
  const [row] = await ctx.db
    .select({ id: tagEncodeSessions.id, batch: tagEncodeSessions.batch, expiresAt: tagEncodeSessions.expiresAt, kind: tagBatches.kind })
    .from(tagEncodeSessions)
    .innerJoin(tagBatches, eq(tagBatches.batch, tagEncodeSessions.batch))
    .where(
      and(
        eq(tagEncodeSessions.tokenHash, hashEncodeToken(token)),
        isNull(tagEncodeSessions.revokedAt),
        gt(tagEncodeSessions.expiresAt, ctx.now()),
        sql`${tagBatches.status} <> 'void'`,
      ),
    );
  if (!row) throw sessionGone();
  return row;
}

export const baseUrl = (ctx: AppContext) => ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '');

/** GET /v1/encode/:token — the batch's working (not switched-off) codes, in print order. */
export async function view(ctx: AppContext, token: string): Promise<EncodeSessionView> {
  const s = await liveSession(ctx, token);
  const rows = await ctx.db
    .select({ code: profileTags.code, encodedAt: profileTags.encodedAt })
    .from(profileTags)
    .where(and(eq(profileTags.batch, s.batch), isNull(profileTags.disabledAt)))
    .orderBy(profileTags.code);
  return {
    batch: s.batch,
    kind: s.kind as TagKind,
    baseUrl: baseUrl(ctx),
    expiresAt: s.expiresAt.toISOString(),
    codes: rows.map((r) => ({ code: r.code, encodedAt: r.encodedAt?.toISOString() ?? null })),
  };
}

/**
 * POST /v1/encode/:token/written — record that a chip now holds `/t/<code>`. Idempotent: repeating
 * it (or re-encoding a replacement chip) only refreshes the last write. Codes outside the session's
 * batch — or switched off — are refused alike.
 */
export async function written(ctx: AppContext, token: string, parseBody: () => EncodeWrittenRequest): Promise<EncodeWrittenResponse> {
  const s = await liveSession(ctx, token);
  const body = parseBody();
  const now = ctx.now();
  const [row] = await ctx.db
    .update(profileTags)
    .set({ encodedAt: now, encodedUid: body.uid ?? null, encodedLocked: body.locked })
    .where(and(eq(profileTags.code, body.code), eq(profileTags.batch, s.batch), isNull(profileTags.disabledAt)))
    .returning({ code: profileTags.code, encodedAt: profileTags.encodedAt });
  if (!row) throw conflict('code_not_in_batch', 'This code is not part of the batch being encoded');
  const [counts] = await ctx.db
    .select({
      total: sql<number>`count(*)::int`,
      encoded: sql<number>`(count(*) filter (where ${isNotNull(profileTags.encodedAt)}))::int`,
    })
    .from(profileTags)
    .where(and(eq(profileTags.batch, s.batch), isNull(profileTags.disabledAt)));
  return { code: row.code, encodedAt: row.encodedAt!.toISOString(), encoded: counts?.encoded ?? 0, total: counts?.total ?? 0 };
}

/** Hide encoding tokens from request logs (`/v1/encode/<token>` → `/v1/encode/[token]`). */
export const redactEncodeToken = (url: string) => url.replace(/(\/v1\/encode\/)[^/?#]+/, '$1[token]');
