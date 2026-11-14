/**
 * The opt-in community (APP_SPEC §5.31, design §1.3–§1.5): switches, the derived `community` consent,
 * the 18+ attestation, competitor handles, blocks and reports, and the one public projection every
 * list uses.
 *
 * Privacy (CLAUDE.md rules 1–3): a public row carries only the handle, the name (null when support hid
 * it), the avatar (a photo only when it is publicly servable), the level ring from the nightly
 * `public_lifetime` snapshot and the period's snapshot points — never worship detail, never anything
 * live. Competitions never write `points_ledger`.
 */
import { and, eq, sql, type SQL } from 'drizzle-orm';
import {
  type Avatar,
  type BlockedUser,
  type CommunitySettings,
  type CommunityUpdate,
  type ConsentEventSource,
  type PublicCompetitor,
  type ReportReason,
  levelFor,
} from '@yaqeen/contracts';
import type { Db } from '../db/client.js';
import { auditLog, communityBlocks, communityMembers, communityReports, consentEvents, consents, publicProfiles, users } from '../db/schema.js';
import { competitorHandle, firstName, memberHandle, nameProblem } from '../domain/community.js';
import { AppError, badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { type CommunityCtx, featureOn, reservedNames } from './community-settings.service.js';

export type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
export type DbOrTx = Db | Tx;

/** Bump when the privacy policy text changes; stored with every consent event (re-exported by me.routes). */
export const POLICY_VERSION = '2026-11-13';

/* ------------------------------------------------------------- projection */

/** The single seam for where public photos are served from (a CDN later needs owner approval). */
export function avatarUrl(ctx: Pick<CommunityCtx, 'env'>, photoId: string, size: 96 | 256): string {
  return `${ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '')}/v1/public/avatars/${photoId}/${size}.webp`;
}

/** The caller's own photo: authed API paths, loaded by the app with `ApiClient.getBytes`. */
export const OWN_PHOTO = { url: '/v1/me/avatar/photo/256', smallUrl: '/v1/me/avatar/photo/96' } as const;

/** Admin dashboard proxy paths (app/api/competitors/[userId]/photos/[photoId]/[size]). */
export const adminPhotoUrls = (userId: string, photoId: string) => ({
  url: `/api/competitors/${userId}/photos/${photoId}/256`,
  smallUrl: `/api/competitors/${userId}/photos/${photoId}/96`,
});

export type AvatarColumns = {
  avatar_kind: string;
  avatar_preset: string | null;
  avatar_photo_id: string | null;
}

/** Preset (when set) or initial — what shows whenever a photo can't. */
export function fallbackAvatar(row: Pick<AvatarColumns, 'avatar_preset'>): Avatar {
  return row.avatar_preset ? ({ kind: 'preset', id: row.avatar_preset } as Avatar) : { kind: 'initial' };
}

/**
 * An avatar with the given photo URLs when `photoOk`, else the fallback. `initial` chosen on purpose
 * stays initial even with a preset on file.
 */
export function avatarOf(row: AvatarColumns, photoOk: boolean, urls: (photoId: string) => { url: string; smallUrl: string }): Avatar {
  if (row.avatar_kind === 'photo' && row.avatar_photo_id && photoOk) return { kind: 'photo', id: row.avatar_photo_id, ...urls(row.avatar_photo_id) };
  if (row.avatar_kind === 'initial') return { kind: 'initial' };
  return fallbackAvatar(row);
}

export function publicLevelRing(lifetime: number): { level: number; progress: number } {
  const l = levelFor(lifetime);
  return { level: l.level, progress: Math.round(l.progress * 1000) / 1000 };
}

/** One competitor row as stored in caches (no `me`; userId is server-only and stripped before sending). */
export type CompetitorRow = AvatarColumns & {
  user_id: string;
  handle: string;
  display_name: string | null;
  name_hidden: boolean;
  photo_ok: boolean;
  public_lifetime: number;
  points: number | null;
  rank: number | null;
}

/**
 * Whether a user's photo may be served publicly (aliases u, ap, and `cm` = community_members):
 * active photo, active account, attested 18+, and actually visible somewhere — in a live competition
 * (not banned) or on a published, unmoderated card.
 */
function photoPublicRule(cm: string): string {
  if (!/^[a-z_]+$/.test(cm)) throw new Error('bad alias');
  return `coalesce(
    ap.status = 'active' and u.status = 'active' and u.adult_attested_at is not null and (
      (coalesce(${cm}.banned_at is null, false) and (coalesce(${cm}.leagues, false) or coalesce(${cm}.leaderboard, false) or exists (
        select 1 from tournaments ptt
        where ptt.status = 'published' and ptt.closed_at is null and exists (
          select 1 from tournament_entries pe where pe.tournament_id = ptt.id and pe.user_id = u.id and pe.left_at is null))))
      or exists (select 1 from public_profiles cp where cp.user_id = u.id and cp.published and cp.moderated_at is null)
    ), false)`;
}

const competitorColumns = (photoOk: string) =>
  sql.raw(`u.id as user_id, pp.handle, u.display_name, (u.name_hidden_at is not null) as name_hidden,
  u.avatar_kind, u.avatar_preset, u.avatar_photo_id,
  ${photoOk} as photo_ok,
  coalesce(t.public_lifetime, 0)::int as public_lifetime`);

/**
 * Columns of a competitor (aliases: u = users, pp = public_profiles, ap = the active avatar photo,
 * pcm = community_members, t = user_point_totals) for rows of a LIVE list — an open league group, a
 * live tournament's standings, the level board — whose visibility filter (active, not banned, in
 * that live competition) already implies the public photo rule, so `photo_ok` only adds "active
 * photo, attested 18+".
 */
export const COMPETITOR_COLUMNS = competitorColumns(`coalesce(ap.status = 'active' and u.adult_attested_at is not null, false)`);

/**
 * The same columns for any other row — a closed tournament's standings, a closed league group, the
 * caller's own row, admin views: `photo_ok` is the public photo route's own rule (`photoPublicSql`),
 * so a row never carries a photo URL the route would refuse (the preset or initial shows instead).
 */
export const COMPETITOR_COLUMNS_ANY = competitorColumns(photoPublicRule('pcm'));

export const COMPETITOR_JOINS = sql.raw(`join public_profiles pp on pp.user_id = u.id
  left join avatar_photos ap on ap.id = u.avatar_photo_id
  left join community_members pcm on pcm.user_id = u.id
  left join user_point_totals t on t.user_id = u.id`);

/** Active account (not suspended, not deletion-requested) — the base of every visibility filter. */
export const ACTIVE_USER = sql.raw(`u.status = 'active'`);

export function toCompetitor(ctx: Pick<CommunityCtx, 'env'>, row: CompetitorRow, callerId: string | null): PublicCompetitor {
  return {
    handle: row.handle,
    name: row.name_hidden ? null : row.display_name,
    avatar: avatarOf(row, row.photo_ok, (id) => ({ url: avatarUrl(ctx, id, 256), smallUrl: avatarUrl(ctx, id, 96) })),
    level: publicLevelRing(Number(row.public_lifetime)),
    points: row.points === null || row.points === undefined ? null : Number(row.points),
    rank: row.rank === null || row.rank === undefined || Number(row.rank) < 1 ? null : Number(row.rank),
    me: callerId !== null && row.user_id === callerId,
  };
}

/** Users the caller blocked or who blocked the caller (display only — ranks keep their gaps). */
export async function blockedBothWays(db: DbOrTx, uid: string): Promise<Set<string>> {
  const r = await db.execute<{ id: string }>(sql`
    select blocked_user_id as id from community_blocks where user_id = ${uid}
    union select user_id as id from community_blocks where blocked_user_id = ${uid}`);
  return new Set(r.rows.map((x) => x.id));
}

/** Apply the caller's blocks and `me` to rows read from a shared cache. */
export function personalise(ctx: Pick<CommunityCtx, 'env'>, rows: CompetitorRow[], callerId: string, blocked: Set<string>): PublicCompetitor[] {
  return rows.filter((r) => !blocked.has(r.user_id)).map((r) => toCompetitor(ctx, r, callerId));
}

/** A handle → its user (any status but deleted), or null. */
export async function userByHandle(db: DbOrTx, handle: string): Promise<{ id: string } | null> {
  const h = handle.trim().replace(/^@/, '').toLowerCase();
  if (!h || h.length > 40) return null;
  const r = await db.execute<{ id: string }>(sql`
    select pp.user_id as id from public_profiles pp join users u on u.id = pp.user_id
    where pp.handle = ${h} and u.status <> 'deleted'`);
  return r.rows[0] ?? null;
}

/* ---------------------------------------------------------------- consent */

/** Granted while leagues or the level board is on (not banned) or a live tournament entry holds. */
export async function communityGranted(db: DbOrTx, uid: string): Promise<boolean> {
  const r = await db.execute<{ granted: boolean }>(sql`
    select (
      exists (select 1 from community_members where user_id = ${uid} and banned_at is null and (leagues or leaderboard))
      or exists (
        select 1 from tournament_entries e join tournaments t on t.id = e.tournament_id
        where e.user_id = ${uid} and e.left_at is null and t.status = 'published' and t.closed_at is null)
    ) as granted`);
  return r.rows[0]?.granted === true;
}

/**
 * Recompute the derived `community` consent and, when it flipped (or `force`, for an explicit user
 * withdrawal), store the state and an immutable event with the policy version and source.
 * `attestedAdult` marks the event of a join that carried the 18+ attestation. Every path that
 * changes membership calls this inside its own transaction.
 */
export async function recomputeCommunityConsent(
  tx: DbOrTx,
  uid: string,
  source: ConsentEventSource,
  opts: { attestedAdult?: boolean; force?: boolean } = {},
): Promise<{ granted: boolean; changed: boolean }> {
  const granted = await communityGranted(tx, uid);
  const [cur] = await tx
    .select({ granted: consents.granted })
    .from(consents)
    .where(and(eq(consents.userId, uid), eq(consents.kind, 'community')));
  const was = cur?.granted ?? false;
  const changed = was !== granted;
  if (!changed && !opts.force) return { granted, changed };
  await tx
    .insert(consents)
    .values({ userId: uid, kind: 'community', granted })
    .onConflictDoUpdate({ target: [consents.userId, consents.kind], set: { granted, updatedAt: sql`now()` } });
  await tx.insert(consentEvents).values({
    userId: uid,
    kind: 'community',
    granted,
    source,
    policyVersion: POLICY_VERSION,
    attestedAdult: granted && opts.attestedAdult ? true : null,
  });
  return { granted, changed };
}

/**
 * Set-based `recomputeCommunityConsent` for many users at once (tournament close/cancel): one
 * statement stores the new state and an event for exactly the users whose consent flipped.
 * `users` is a SQL fragment selecting a `user_id` column.
 */
export async function recomputeCommunityConsentMany(tx: DbOrTx, usersQuery: SQL, source: ConsentEventSource): Promise<number> {
  const r = await tx.execute<{ n: number }>(sql`
    with target as (select distinct user_id from (${usersQuery}) q),
    state as (
      select tg.user_id, (
        exists (select 1 from community_members c where c.user_id = tg.user_id and c.banned_at is null and (c.leagues or c.leaderboard))
        or exists (select 1 from tournament_entries e join tournaments t on t.id = e.tournament_id
                   where e.user_id = tg.user_id and e.left_at is null and t.status = 'published' and t.closed_at is null)
      ) as granted
      from target tg
    ),
    flipped as (
      select s.user_id, s.granted from state s
      left join consents c on c.user_id = s.user_id and c.kind = 'community'
      where s.granted <> coalesce(c.granted, false)
    ),
    upserted as (
      insert into consents (user_id, kind, granted, updated_at)
      select user_id, 'community', granted, now() from flipped
      on conflict (user_id, kind) do update set granted = excluded.granted, updated_at = now()
      returning user_id
    ),
    events as (
      insert into consent_events (user_id, kind, granted, source, policy_version)
      select user_id, 'community', granted, ${source}, ${POLICY_VERSION} from flipped
      returning user_id
    )
    select count(*)::int as n from events`);
  return Number(r.rows[0]?.n ?? 0);
}

/* ---------------------------------------------------------------- leaving */

/** Leave the live league week(s): the member disappears from standings at once and gets no result. */
export async function leaveLeague(tx: DbOrTx, uid: string, now: Date): Promise<void> {
  await tx.execute(sql`
    update league_members m set left_at = ${now}
    from league_weeks w
    where w.starts_on = m.starts_on and w.status = 'open' and m.user_id = ${uid} and m.left_at is null`);
}

/** Leave every unclosed tournament entry. */
export async function leaveTournaments(tx: DbOrTx, uid: string, now: Date): Promise<void> {
  await tx.execute(sql`
    update tournament_entries e set left_at = ${now}
    from tournaments t
    where t.id = e.tournament_id and e.user_id = ${uid} and e.left_at is null and t.closed_at is null`);
}

/** All switches off and every live row left (consent withdrawal, erasure, ban). The division is kept. */
export async function leaveEverything(tx: DbOrTx, uid: string, now: Date): Promise<void> {
  await tx
    .update(communityMembers)
    .set({ leagues: false, leaderboard: false, leaderboardCountry: false, updatedAt: now })
    .where(eq(communityMembers.userId, uid));
  await leaveLeague(tx, uid, now);
  await leaveTournaments(tx, uid, now);
}

/* --------------------------------------------------------------- settings */

interface MemberState {
  leagues: boolean;
  leaderboard: boolean;
  leaderboardCountry: boolean;
  banned: boolean;
  attestedAdult: boolean;
  country: string | null;
  isGuest: boolean;
  displayName: string | null;
  nameHidden: boolean;
  status: string;
}

async function memberState(db: DbOrTx, uid: string, lock = false): Promise<MemberState> {
  const r = await db.execute<{
    leagues: boolean | null;
    leaderboard: boolean | null;
    leaderboard_country: boolean | null;
    banned: boolean | null;
    attested: boolean;
    country: string | null;
    is_guest: boolean;
    display_name: string | null;
    name_hidden: boolean;
    status: string;
  }>(sql`
    select cm.leagues, cm.leaderboard, cm.leaderboard_country, (cm.banned_at is not null) as banned,
           (u.adult_attested_at is not null) as attested, u.country, u.is_guest, u.display_name,
           (u.name_hidden_at is not null) as name_hidden, u.status::text as status
    from users u left join community_members cm on cm.user_id = u.id
    where u.id = ${uid}
    ${lock ? sql`for update of u` : sql``}`);
  const row = r.rows[0];
  if (!row) throw notFound('user');
  return {
    leagues: row.leagues === true,
    leaderboard: row.leaderboard === true,
    leaderboardCountry: row.leaderboard_country === true,
    banned: row.banned === true,
    attestedAdult: row.attested,
    country: row.country,
    isGuest: row.is_guest,
    displayName: row.display_name,
    nameHidden: row.name_hidden,
    status: row.status,
  };
}

const toSettings = (s: MemberState): CommunitySettings => ({
  leagues: s.leagues,
  leaderboard: s.leaderboard,
  leaderboardCountry: s.leaderboard && s.leaderboardCountry,
  banned: s.banned,
  attestedAdult: s.attestedAdult,
  country: s.country,
});

export async function readSettings(db: DbOrTx, uid: string): Promise<CommunitySettings> {
  return toSettings(await memberState(db, uid));
}

/**
 * Validate the name a competitor shows (`users.display_name`): `name_locked` while support hid it,
 * `name_required`, `invalid_name` (filter + reserved handles + brand words + profanity).
 */
export async function checkDisplayName(ctx: CommunityCtx, name: string): Promise<void> {
  const problem = nameProblem(name, await reservedNames(ctx));
  if (problem === 'name_required') throw badRequest('name_required', 'A name is required');
  if (problem) throw badRequest('invalid_name', 'This name cannot be used');
}

const DEFAULT_CARD_SHOW = { level: true, streak: false, challengeDay: false, badges: false, memberSince: false, timeline: false };

/**
 * Every competitor has a stable @handle: an existing card handle is kept; otherwise a draft
 * (unpublished) card row with `competitorHandle(name)` — the first word + 4 digits, never the full name.
 */
export async function ensureCompetitorHandle(tx: DbOrTx, ctx: CommunityCtx, uid: string, name: string | null): Promise<string> {
  const [have] = await tx.select({ handle: publicProfiles.handle }).from(publicProfiles).where(eq(publicProfiles.userId, uid));
  if (have) return have.handle;
  const [u] = await tx.select({ hiddenAt: users.nameHiddenAt }).from(users).where(eq(users.id, uid));
  const hidden = !!u?.hiddenAt;
  const reserved = new Set(await reservedNames(ctx));
  for (let i = 0; i < 12; i++) {
    const handle = hidden ? memberHandle(Math.random) : competitorHandle(name, Math.random);
    if (reserved.has(handle)) continue;
    const inserted = await tx
      .insert(publicProfiles)
      .values({ userId: uid, handle, published: false, displayName: (hidden ? '' : firstName(name)) || 'Yaqeen', show: DEFAULT_CARD_SHOW })
      .onConflictDoNothing()
      .returning({ handle: publicProfiles.handle });
    if (inserted[0]) return inserted[0].handle;
    const [raced] = await tx.select({ handle: publicProfiles.handle }).from(publicProfiles).where(eq(publicProfiles.userId, uid));
    if (raced) return raced.handle;
  }
  throw new AppError(500, 'handle_unavailable');
}

/** Set `adult_attested_at` once (first attestation wins). Returns true when it was set now. */
async function attestOnce(tx: DbOrTx, uid: string, now: Date): Promise<boolean> {
  const r = await tx
    .update(users)
    .set({ adultAttestedAt: now, updatedAt: now })
    .where(and(eq(users.id, uid), sql`${users.adultAttestedAt} is null`))
    .returning({ id: users.id });
  return r.length > 0;
}

/** POST /v1/me/attestation — audited with the user as the actor. */
export async function attest(ctx: CommunityCtx, uid: string, ip: string | null): Promise<CommunitySettings> {
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    const s = await memberState(tx, uid, true);
    if (s.isGuest) throw forbidden('account_required', 'Sign in to take part in competitions');
    if (await attestOnce(tx, uid, now)) {
      await tx.insert(auditLog).values({ actorUserId: uid, action: 'user.attest_adult', targetType: 'user', targetId: uid, after: { attestedAt: now.toISOString() }, ip });
    }
  });
  await ctx.cache.bumpNamespace('community');
  await ctx.cache.bumpNamespace('profile');
  return readSettings(ctx.db, uid);
}

/**
 * PUT /v1/me/community — one transaction: attestation, name, switches, draft handle, leaving on
 * turn-off and the derived consent. Turning anything on needs a signed-in account, the flag, not
 * banned, the 18+ attestation (or `attestAdult` now) and a valid name.
 */
export async function updateCommunity(ctx: CommunityCtx, uid: string, body: CommunityUpdate, ip: string | null): Promise<CommunitySettings> {
  const now = ctx.now();
  const flags = {
    leagues: await featureOn(ctx, 'leagues'),
    leaderboard: await featureOn(ctx, 'leaderboard'),
  };
  await ctx.db.transaction(async (tx) => {
    const s = await memberState(tx, uid, true);
    if (s.isGuest) throw forbidden('account_required', 'Sign in to take part in competitions');
    const next = {
      leagues: body.leagues ?? s.leagues,
      leaderboard: body.leaderboard ?? s.leaderboard,
      leaderboardCountry: body.leaderboardCountry ?? s.leaderboardCountry,
    };
    // The country board refines the level board: turning it on turns the board on; off turns both off.
    if (body.leaderboardCountry === true && body.leaderboard === undefined) next.leaderboard = true;
    if (!next.leaderboard) next.leaderboardCountry = false;
    const turningOn = (next.leagues && !s.leagues) || (next.leaderboard && !s.leaderboard) || (next.leaderboardCountry && !s.leaderboardCountry);

    if (body.displayName !== undefined && s.nameHidden) throw conflict('name_locked', 'Support hid this name');
    if (turningOn) {
      if ((next.leagues && !s.leagues && !flags.leagues) || ((next.leaderboard || next.leaderboardCountry) && !s.leaderboard && !flags.leaderboard)) {
        throw forbidden('feature_off', 'This competition is not available');
      }
      if (s.banned) throw forbidden('community_banned', 'Your participation in competitions is suspended');
      if (s.status !== 'active') throw forbidden('account_inactive');
      if (!s.attestedAdult && body.attestAdult !== true) throw badRequest('attestation_required', 'Confirm you are 18 or older, or have a guardian’s consent');
      const name = body.displayName ?? s.displayName;
      if (!s.nameHidden) {
        if (!name || !name.trim()) throw badRequest('name_required', 'A name is required');
        await checkDisplayName(ctx, name);
      }
    } else if (body.displayName !== undefined) {
      await checkDisplayName(ctx, body.displayName);
    }

    let attestedNow = false;
    if (body.attestAdult === true && !s.attestedAdult) {
      attestedNow = await attestOnce(tx, uid, now);
      if (attestedNow) {
        await tx.insert(auditLog).values({ actorUserId: uid, action: 'user.attest_adult', targetType: 'user', targetId: uid, after: { attestedAt: now.toISOString(), via: 'community' }, ip });
      }
    }
    if (body.displayName !== undefined) {
      await tx.update(users).set({ displayName: body.displayName.trim(), updatedAt: now }).where(eq(users.id, uid));
    }

    await tx
      .insert(communityMembers)
      .values({ userId: uid, ...next })
      .onConflictDoUpdate({ target: communityMembers.userId, set: { ...next, updatedAt: now } });
    if (next.leagues || next.leaderboard) await ensureCompetitorHandle(tx, ctx, uid, body.displayName ?? s.displayName);
    if (!next.leagues && s.leagues) await leaveLeague(tx, uid, now);

    await recomputeCommunityConsent(tx, uid, body.source, { attestedAdult: turningOn && (attestedNow || s.attestedAdult) });
  });
  await ctx.cache.bumpNamespace('community');
  if (body.displayName !== undefined) await ctx.cache.bumpNamespace('profile');
  return readSettings(ctx.db, uid);
}

/**
 * Join-time checks shared by tournaments: signed-in, not banned, attested (or attesting now), a name.
 * Returns whether the attestation was given in this request.
 */
export async function prepareJoin(tx: Tx, ctx: CommunityCtx, uid: string, attestAdult: boolean | undefined, ip: string | null): Promise<{ attestedNow: boolean }> {
  const now = ctx.now();
  const s = await memberState(tx, uid, true);
  if (s.isGuest) throw forbidden('account_required', 'Sign in to take part in competitions');
  if (s.banned) throw forbidden('community_banned', 'Your participation in competitions is suspended');
  if (s.status !== 'active') throw forbidden('account_inactive');
  if (!s.attestedAdult && attestAdult !== true) throw badRequest('attestation_required', 'Confirm you are 18 or older, or have a guardian’s consent');
  if (!s.nameHidden) {
    if (!s.displayName || !s.displayName.trim()) throw badRequest('name_required', 'A name is required');
    await checkDisplayName(ctx, s.displayName);
  }
  let attestedNow = false;
  if (attestAdult === true && !s.attestedAdult) {
    attestedNow = await attestOnce(tx, uid, now);
    if (attestedNow) {
      await tx.insert(auditLog).values({ actorUserId: uid, action: 'user.attest_adult', targetType: 'user', targetId: uid, after: { attestedAt: now.toISOString(), via: 'tournament' }, ip });
    }
  }
  await tx.insert(communityMembers).values({ userId: uid }).onConflictDoNothing();
  await ensureCompetitorHandle(tx, ctx, uid, s.displayName);
  return { attestedNow };
}

/* --------------------------------------------------------- blocks, reports */

export async function listBlocks(ctx: CommunityCtx, uid: string): Promise<BlockedUser[]> {
  const r = await ctx.db.execute<AvatarColumns & { handle: string; display_name: string | null; name_hidden: boolean; photo_ok: boolean }>(sql`
    select pp.handle, u.display_name, (u.name_hidden_at is not null) as name_hidden, u.avatar_kind, u.avatar_preset, u.avatar_photo_id,
      ${photoPublicSql()} as photo_ok
    from community_blocks b
    join users u on u.id = b.blocked_user_id
    join public_profiles pp on pp.user_id = u.id
    left join avatar_photos ap on ap.id = u.avatar_photo_id
    left join community_members cm on cm.user_id = u.id
    where b.user_id = ${uid}
    order by b.created_at desc`);
  return r.rows.map((row) => ({
    handle: row.handle,
    name: row.name_hidden ? null : row.display_name,
    avatar: avatarOf(row, row.photo_ok, (id) => ({ url: avatarUrl(ctx, id, 256), smallUrl: avatarUrl(ctx, id, 96) })),
  }));
}

export async function block(ctx: CommunityCtx, uid: string, handle: string): Promise<void> {
  const target = await userByHandle(ctx.db, handle);
  if (!target) throw notFound('handle');
  if (target.id === uid) throw badRequest('cannot_block_self');
  await ctx.db.insert(communityBlocks).values({ userId: uid, blockedUserId: target.id }).onConflictDoNothing();
}

export async function unblock(ctx: CommunityCtx, uid: string, handle: string): Promise<void> {
  const target = await userByHandle(ctx.db, handle);
  if (!target) throw notFound('handle');
  await ctx.db.delete(communityBlocks).where(and(eq(communityBlocks.userId, uid), eq(communityBlocks.blockedUserId, target.id)));
}

export const REPORTS_PER_DAY = 20;

/** Idempotent while a report on the same person is open; at most 20 per reporter per rolling 24 h (counted in the DB). */
export async function report(ctx: CommunityCtx, uid: string, handle: string, reason: ReportReason): Promise<void> {
  const target = await userByHandle(ctx.db, handle);
  if (!target || target.id === uid) throw notFound('handle');
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    // Serialise one reporter's reports so the rolling count can't be raced past.
    await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${`report:${uid}`}))`);
    const open = await tx.execute(sql`
      select 1 from community_reports where reporter_id = ${uid} and target_user_id = ${target.id} and resolved_at is null`);
    if (open.rows.length) return;
    const recent = await tx.execute<{ n: number }>(sql`
      select count(*)::int as n from community_reports where reporter_id = ${uid} and created_at > ${new Date(now.getTime() - 86_400_000)}`);
    if ((recent.rows[0]?.n ?? 0) >= REPORTS_PER_DAY) throw new AppError(429, 'rate_limited', 'Report limit reached for today');
    await tx.insert(communityReports).values({ reporterId: uid, targetUserId: target.id, reason, createdAt: now }).onConflictDoNothing();
  });
}

/* ------------------------------------------------------------- visibility */

/**
 * Whether a user's photo may be served publicly (aliases u, ap and `cm` = community_members; the
 * same rule as every competitor row's `photo_ok`).
 */
export function photoPublicSql(cm = 'cm'): SQL {
  return sql.raw(photoPublicRule(cm));
}
