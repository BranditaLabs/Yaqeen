/**
 * Public profile cards («بطاقة يقين»): the owner's settings and the public view scanners see.
 *
 * Privacy: unpublished by default; the view carries only what the owner switched on and never any
 * worship detail — the level comes from lifetime points, the streak is a number of days, badges are
 * the streak milestones reached. A guest cannot publish (the card would vanish with the device).
 */
import { and, eq, gt, inArray, isNull, like, sql } from 'drizzle-orm';
import {
  type Avatar,
  type JourneyEvent,
  LEVEL_REASONS,
  type MeProfile,
  type MyJourney,
  JOURNEY_DAYS,
  LEVELS,
  type PublicProfileSettings,
  type PublicProfileUpdate,
  type PublicProfileView,
  PROFILE_HANDLE,
  type UpdateProfileRequest,
  levelFor,
} from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { challengeEnrollments, pointsLedger, publicProfiles, users } from '../db/schema.js';
import { nameProblem, weekWindow } from '../domain/community.js';
import { addDays } from '../domain/points.js';
import { conflict, forbidden, badRequest, notFound } from '../lib/errors.js';
import { ownAvatar, setAvatar } from './avatar.service.js';
import { listBadges } from './badges.service.js';
import * as stats from './card-stats.service.js';
import { cardFeatureOn, isReservedHandle } from './cards-settings.service.js';
import * as challenge from './challenge.service.js';
import { type CommunityCtx, featureOn } from './community-settings.service.js';
import { type AvatarColumns, avatarOf, avatarUrl, checkDisplayName, photoPublicSql, readSettings } from './community.service.js';
import * as leagues from './leagues.service.js';

const DEFAULT_SHOW = { level: true, streak: false, challengeDay: false, badges: false, memberSince: false, timeline: false };

export const profileUrl = (ctx: AppContext, handle: string) => `${ctx.env.PUBLIC_PROFILE_BASE_URL.replace(/\/$/, '')}/u/${handle}`;

/** A free handle based on the user's name (latin letters only) or `yaqeen_<n>`. */
async function suggestHandle(ctx: AppContext, name: string | null, uid: string): Promise<string> {
  const base = (name ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^[^a-z]+|_+$/g, '')
    .slice(0, 16);
  const stem = base.length >= 3 ? base : `yaqeen_${uid.replace(/-/g, '').slice(0, 6)}`;
  for (let i = 0; i < 20; i++) {
    const candidate = i === 0 ? stem : `${stem}${i + 1}`;
    if (await handleAvailable(ctx, candidate, uid)) return candidate;
  }
  return `yaqeen_${uid.replace(/-/g, '').slice(0, 10)}`;
}

export async function handleAvailable(ctx: AppContext, handle: string, uid?: string): Promise<boolean> {
  const h = handle.trim().toLowerCase();
  if (!PROFILE_HANDLE.test(h) || (await isReservedHandle(ctx, h))) return false;
  const [row] = await ctx.db.select({ userId: publicProfiles.userId }).from(publicProfiles).where(eq(publicProfiles.handle, h));
  return !row || row.userId === uid;
}

/** The handle a card may take while support hides the name: `yaqeen_<id>`, never derived from it. */
const NEUTRAL_HANDLE = /^yaqeen_[0-9a-f]{6,10}[0-9]*$/;

/**
 * A new card handle's own text must pass the community name filter (brand words, profanity), as
 * every competitor @handle is shown in public lists. The neutral `yaqeen_<id>` suggestion is ours.
 */
function handleProblem(handle: string): boolean {
  if (NEUTRAL_HANDLE.test(handle)) return false;
  return nameProblem(handle.replace(/_/g, ' ')) !== null;
}

export async function settings(ctx: AppContext, uid: string): Promise<PublicProfileSettings> {
  const [row] = await ctx.db.select().from(publicProfiles).where(eq(publicProfiles.userId, uid));
  const [u] = await ctx.db.select({ displayName: users.displayName, nameHiddenAt: users.nameHiddenAt }).from(users).where(eq(users.id, uid));
  // While support hides the name, nothing suggested here is derived from it.
  const hidden = !!u?.nameHiddenAt;
  if (row) {
    // A competitor handle (`omar-5521`, `member-x7k2p9`) isn't a card handle: suggest one to publish with.
    const handle = PROFILE_HANDLE.test(row.handle) ? row.handle : await suggestHandle(ctx, hidden ? null : row.displayName, uid);
    return {
      published: row.published,
      handle,
      displayName: row.displayName,
      bio: row.bio,
      links: row.links as PublicProfileSettings['links'],
      show: { ...DEFAULT_SHOW, ...row.show },
      theme: row.theme as PublicProfileSettings['theme'],
      url: profileUrl(ctx, handle),
      views: row.views,
      moderated: row.moderatedAt !== null,
    };
  }
  // Not created yet: a draft the app shows in the editor (nothing is public until saved + published).
  const handle = await suggestHandle(ctx, hidden ? null : (u?.displayName ?? null), uid);
  return {
    published: false,
    handle,
    displayName: (hidden ? '' : u?.displayName?.trim()) || 'Yaqeen',
    bio: '',
    links: [],
    show: DEFAULT_SHOW,
    theme: 'sky',
    url: profileUrl(ctx, handle),
    views: 0,
    moderated: false,
  };
}

export async function update(ctx: AppContext, uid: string, isGuest: boolean, input: PublicProfileUpdate): Promise<PublicProfileSettings> {
  if (isGuest) throw forbidden('account_required', 'Sign in to publish a profile card');
  if (await isReservedHandle(ctx, input.handle)) throw badRequest('handle_reserved');
  const [u] = await ctx.db.select({ status: users.status, nameHiddenAt: users.nameHiddenAt }).from(users).where(eq(users.id, uid));
  if (!u || u.status !== 'active') throw forbidden('account_inactive');
  const [before] = await ctx.db
    .select({ published: publicProfiles.published, moderatedAt: publicProfiles.moderatedAt, handle: publicProfiles.handle })
    .from(publicProfiles)
    .where(eq(publicProfiles.userId, uid));
  // The card handle is also the competitor @handle in every public list.
  if (!before || before.handle !== input.handle) {
    if (u.nameHiddenAt && input.handle !== (await suggestHandle(ctx, null, uid))) {
      throw conflict('name_locked', 'Support hid this name; the handle stays neutral until it is restored');
    }
    if (!u.nameHiddenAt && handleProblem(input.handle)) throw badRequest('handle_reserved');
  }
  if (input.published && before?.moderatedAt) throw forbidden('card_moderated', 'This card was hidden by Yaqeen support');
  if (input.published && !(await cardFeatureOn(ctx, 'publicCards'))) throw forbidden('feature_off', 'Public cards are paused');
  try {
    await ctx.db
      .insert(publicProfiles)
      .values({
        userId: uid,
        handle: input.handle,
        published: input.published,
        displayName: input.displayName,
        bio: input.bio,
        links: input.links,
        show: input.show,
        theme: input.theme,
      })
      .onConflictDoUpdate({
        target: publicProfiles.userId,
        set: {
          handle: input.handle,
          published: input.published,
          displayName: input.displayName,
          bio: input.bio,
          links: input.links,
          show: input.show,
          theme: input.theme,
          updatedAt: ctx.now(),
        },
      });
  } catch (e) {
    // Drizzle wraps the driver error; the unique violation (23505) sits on `cause`.
    const code = (e as { code?: string; cause?: { code?: string } }).cause?.code ?? (e as { code?: string }).code;
    if (code === '23505') throw conflict('handle_taken');
    throw e;
  }
  await ctx.cache.bumpNamespace('profile');
  if (input.published && !before?.published) await stats.bump(ctx, 'card_published');
  return settings(ctx, uid);
}

/** Erasure request / suspension: hide the card at once (the row goes with the account). */
export async function unpublish(ctx: AppContext, uid: string) {
  await ctx.db.update(publicProfiles).set({ published: false, updatedAt: ctx.now() }).where(eq(publicProfiles.userId, uid));
  await ctx.cache.bumpNamespace('profile');
}

/** What a scanner sees, or null when the card is missing, unpublished or the account inactive. */
export async function publicView(ctx: AppContext, handle: string): Promise<PublicProfileView | null> {
  const h = handle.trim().toLowerCase();
  if (!PROFILE_HANDLE.test(h)) return null;
  const [row] = await ctx.db
    .select({ p: publicProfiles, status: users.status, createdAt: users.createdAt })
    .from(publicProfiles)
    .innerJoin(users, eq(users.id, publicProfiles.userId))
    .where(and(eq(publicProfiles.handle, h), eq(publicProfiles.published, true), isNull(publicProfiles.moderatedAt)));
  if (!row || row.status !== 'active') return null;
  const p = row.p;
  const show = { ...DEFAULT_SHOW, ...p.show };
  const uid = p.userId;

  let level: PublicProfileView['level'] = null;
  if (show.level) {
    // The nightly public snapshot of lifetime earned points (never live; spending never lowers it).
    const l = levelFor(await publicLifetime(ctx, uid));
    level = { level: l.level, nameAr: l.nameAr, nameEn: l.nameEn, progress: l.progress };
  }

  let streak: number | null = null;
  let challengeDay: PublicProfileView['challengeDay'] = null;
  if (show.streak || show.challengeDay) {
    const s = await challenge.summary(ctx, uid);
    if (show.streak) streak = s.enrolled ? s.streak : 0;
    if (show.challengeDay && s.enrolled) challengeDay = { day: s.dayNumber, of: s.challengeLengthDays };
  }

  let badges: number[] | null = null;
  if (show.badges) {
    const rows = await ctx.db
      .select({ ref: pointsLedger.refKey })
      .from(pointsLedger)
      .where(and(eq(pointsLedger.userId, uid), eq(pointsLedger.reason, 'milestone'), like(pointsLedger.refKey, 'milestone:%')));
    badges = rows
      .map((r) => Number(r.ref.slice('milestone:'.length)))
      .filter((d) => Number.isFinite(d) && d > 0)
      .sort((a, b) => a - b);
  }

  const timeline = show.timeline ? (await journeyEvents(ctx, uid)).slice(0, 12) : null;

  return {
    handle: p.handle,
    displayName: p.displayName,
    bio: p.bio,
    links: p.links as PublicProfileView['links'],
    theme: p.theme as PublicProfileView['theme'],
    level,
    streak,
    challengeDay,
    badges,
    memberSince: show.memberSince ? row.createdAt.toISOString().slice(0, 10) : null,
    timeline,
    avatar: await publicAvatarOf(ctx, uid),
  };
}

/** The avatar a scanner sees: a photo only when it is publicly servable, else the preset or initial. */
export async function publicAvatarOf(ctx: Pick<CommunityCtx, 'db' | 'env'>, uid: string): Promise<Avatar> {
  const r = await ctx.db.execute<AvatarColumns & { photo_ok: boolean }>(sql`
    select u.avatar_kind, u.avatar_preset, u.avatar_photo_id, ${photoPublicSql()} as photo_ok
    from users u
    left join avatar_photos ap on ap.id = u.avatar_photo_id
    left join community_members cm on cm.user_id = u.id
    where u.id = ${uid}`);
  const row = r.rows[0];
  if (!row) return { kind: 'initial' };
  return avatarOf(row, row.photo_ok, (id) => ({ url: avatarUrl(ctx, id, 256), smallUrl: avatarUrl(ctx, id, 96) }));
}

/** `user_point_totals.public_lifetime` — every public level ring reads this nightly snapshot. */
export async function publicLifetime(ctx: Pick<CommunityCtx, 'db'>, uid: string): Promise<number> {
  const r = await ctx.db.execute<{ pts: number }>(sql`
    select coalesce((select public_lifetime from user_point_totals where user_id = ${uid}), 0)::int as pts`);
  return Number(r.rows[0]?.pts ?? 0);
}

/* ------------------------------------------------------------------ journey */

/**
 * Lifetime earned points — the caller's own, live: positive ledger rows with a `LEVEL_REASONS`
 * reason. Spending never lowers a level and a reversal (e.g. a failed redemption) never raises it.
 */
export async function lifetimePoints(ctx: Pick<CommunityCtx, 'db'>, uid: string): Promise<number> {
  const [sum] = await ctx.db
    .select({ pts: sql<number>`coalesce(sum(${pointsLedger.delta}), 0)::int` })
    .from(pointsLedger)
    .where(and(eq(pointsLedger.userId, uid), gt(pointsLedger.delta, 0), inArray(pointsLedger.reason, [...LEVEL_REASONS])));
  return sum?.pts ?? 0;
}

/**
 * The dated milestones of a user's journey, newest first: joined, challenge started, challenge
 * days 30/100/200/300/365, each level reached (the day lifetime points first crossed it) and each
 * streak badge. Nothing here names a prayer, zikr or page.
 */
export async function journeyEvents(ctx: AppContext, uid: string): Promise<JourneyEvent[]> {
  const day = (d: Date) => d.toISOString().slice(0, 10);
  const events: JourneyEvent[] = [];
  const [u] = await ctx.db.select({ createdAt: users.createdAt }).from(users).where(eq(users.id, uid));
  if (u) events.push({ kind: 'joined', date: day(u.createdAt), value: null });

  const [enr] = await ctx.db.select({ startedOn: challengeEnrollments.startedOn }).from(challengeEnrollments).where(eq(challengeEnrollments.userId, uid));
  if (enr) {
    events.push({ kind: 'challenge_start', date: enr.startedOn, value: 1 });
    const today = await challenge.todayFor(ctx, uid);
    for (const n of JOURNEY_DAYS) {
      const date = addDays(enr.startedOn, n - 1);
      if (date <= today) events.push({ kind: 'challenge_day', date, value: n });
    }
  }

  // The first moment the running total of earned points reached each level's threshold.
  const thresholds = LEVELS.slice(1).map((l) => l.min);
  if (thresholds.length) {
    const rows = await ctx.db.execute<{ min: number; reached: Date | string | null }>(sql`
      with earned as (
        select ${pointsLedger.createdAt} as at,
               sum(${pointsLedger.delta}) over (order by ${pointsLedger.createdAt}, ${pointsLedger.id}) as cum
        from ${pointsLedger}
        where ${pointsLedger.userId} = ${uid} and ${pointsLedger.delta} > 0
          and ${pointsLedger.reason}::text in (${sql.raw(LEVEL_REASONS.map((r) => `'${r}'`).join(', '))})
      )
      select t.min, (select min(at) from earned where cum >= t.min) as reached
      from unnest(${sql.raw(`array[${thresholds.join(',')}]`)}::int[]) as t(min)`);
    for (const r of rows.rows) {
      if (!r.reached) continue;
      const level = LEVELS.findIndex((l) => l.min === Number(r.min)) + 1;
      events.push({ kind: 'level', date: day(new Date(r.reached)), value: level });
    }
  }

  const badges = await ctx.db
    .select({ ref: pointsLedger.refKey, at: pointsLedger.createdAt })
    .from(pointsLedger)
    .where(and(eq(pointsLedger.userId, uid), eq(pointsLedger.reason, 'milestone'), like(pointsLedger.refKey, 'milestone:%')));
  for (const b of badges) {
    const days = Number(b.ref.slice('milestone:'.length));
    if (Number.isFinite(days) && days > 0) events.push({ kind: 'badge', date: day(b.at), value: days });
  }

  // Newest first; on the same day the bigger moment (level, badge) leads.
  const weight: Record<JourneyEvent['kind'], number> = { level: 4, badge: 3, challenge_day: 2, challenge_start: 1, joined: 0 };
  return events.sort((a, b) => (a.date === b.date ? weight[b.kind] - weight[a.kind] : a.date < b.date ? 1 : -1));
}

/** The owner's journey for the Profile tab (private — every milestone, plus where they stand). */
export async function myJourney(ctx: AppContext, uid: string): Promise<MyJourney> {
  const [pts, summary, events] = await Promise.all([lifetimePoints(ctx, uid), challenge.summary(ctx, uid), journeyEvents(ctx, uid)]);
  const l = levelFor(pts);
  return {
    lifetimePoints: pts,
    level: { level: l.level, nameAr: l.nameAr, nameEn: l.nameEn, progress: l.progress, nextAt: l.nextAt },
    streak: summary.enrolled ? summary.streak : 0,
    challengeDay: summary.enrolled ? summary.dayNumber : null,
    challengeOf: summary.challengeLengthDays,
    events,
    avatar: await ownAvatar(ctx.db, uid),
  };
}

/* ---------------------------------------------------------------- my profile */

/**
 * GET /v1/me/profile — the caller only: name, @handle, own avatar (authed photo paths), the live
 * level and this week's live points, community switches, the league summary (placing the member in
 * this week's group when opted in) and recent badges.
 */
export async function meProfile(ctx: CommunityCtx, uid: string): Promise<MeProfile> {
  const r = await ctx.db.execute<{
    display_name: string | null;
    name_hidden: boolean;
    photo_locked: boolean;
    photo_public: boolean | null;
    handle: string | null;
  }>(sql`
    select u.display_name, (u.name_hidden_at is not null) as name_hidden, (u.photo_locked_at is not null) as photo_locked,
      (u.avatar_kind = 'photo' and ${photoPublicSql()}) as photo_public,
      (select p.handle from public_profiles p where p.user_id = u.id) as handle
    from users u
    left join avatar_photos ap on ap.id = u.avatar_photo_id
    left join community_members cm on cm.user_id = u.id
    where u.id = ${uid}`);
  const u = r.rows[0];
  if (!u) throw notFound('user');
  const week = weekWindow(ctx.now());
  const [avatar, pts, weekPoints, community, badges] = await Promise.all([
    ownAvatar(ctx.db, uid),
    lifetimePoints(ctx, uid),
    leagues.livePoints(ctx.db, uid, week.startsOn, addDays(week.startsOn, 7)),
    readSettings(ctx.db, uid),
    listBadges(ctx, uid),
  ]);
  const league = community.leagues && !community.banned && (await featureOn(ctx, 'leagues')) ? await leagues.summary(ctx, uid) : null;
  const l = levelFor(pts);
  return {
    displayName: u.display_name,
    nameHidden: u.name_hidden,
    handle: u.handle,
    avatar,
    photoHidden: u.photo_locked,
    photoPublic: u.photo_public === true,
    level: { level: l.level, nameAr: l.nameAr, nameEn: l.nameEn, progress: l.progress, nextAt: l.nextAt },
    lifetimePoints: pts,
    weekPoints,
    community,
    league,
    recentBadges: badges.slice(0, 12),
    badgesCount: badges.length,
  };
}

/** PATCH /v1/me/profile — name and preset/initial avatar (a photo goes through PUT /v1/me/avatar/photo). */
export async function updateMe(ctx: CommunityCtx, uid: string, isGuest: boolean, body: UpdateProfileRequest): Promise<MeProfile> {
  if (isGuest) throw forbidden('account_required', 'Sign in to save your profile');
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    const [u] = await tx
      .select({ isGuest: users.isGuest, nameHiddenAt: users.nameHiddenAt })
      .from(users)
      .where(eq(users.id, uid))
      .for('update');
    if (!u) throw notFound('user');
    if (u.isGuest) throw forbidden('account_required', 'Sign in to save your profile');
    if (body.displayName !== undefined) {
      if (u.nameHiddenAt) throw conflict('name_locked', 'Support hid this name');
      await checkDisplayName(ctx, body.displayName);
      await tx.update(users).set({ displayName: body.displayName.trim(), updatedAt: now }).where(eq(users.id, uid));
    }
    if (body.avatar) await setAvatar(tx, uid, body.avatar, now);
  });
  await ctx.cache.bumpNamespace('community');
  await ctx.cache.bumpNamespace('profile');
  return meProfile(ctx, uid);
}

/** One page open (bots excluded by the caller). A counter only — nothing about the visitor. */
export async function countView(ctx: AppContext, handle: string) {
  await ctx.db
    .update(publicProfiles)
    .set({ views: sql`${publicProfiles.views} + 1` })
    .where(and(eq(publicProfiles.handle, handle.trim().toLowerCase()), eq(publicProfiles.published, true)));
}
