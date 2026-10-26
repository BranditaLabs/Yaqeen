/**
 * Public profile cards («بطاقة يقين»): the owner's settings and the public view scanners see.
 *
 * Privacy: unpublished by default; the view carries only what the owner switched on and never any
 * worship detail — the level comes from lifetime points, the streak is a number of days, badges are
 * the streak milestones reached. A guest cannot publish (the card would vanish with the device).
 */
import { and, eq, gt, like, sql } from 'drizzle-orm';
import {
  type JourneyEvent,
  type MyJourney,
  JOURNEY_DAYS,
  LEVELS,
  type PublicProfileSettings,
  type PublicProfileUpdate,
  type PublicProfileView,
  PROFILE_HANDLE,
  RESERVED_HANDLES,
  levelFor,
} from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import { challengeEnrollments, pointsLedger, publicProfiles, users } from '../db/schema.js';
import { addDays } from '../domain/points.js';
import { conflict, forbidden, badRequest } from '../lib/errors.js';
import * as challenge from './challenge.service.js';

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
  if (!PROFILE_HANDLE.test(h) || RESERVED_HANDLES.has(h)) return false;
  const [row] = await ctx.db.select({ userId: publicProfiles.userId }).from(publicProfiles).where(eq(publicProfiles.handle, h));
  return !row || row.userId === uid;
}

export async function settings(ctx: AppContext, uid: string): Promise<PublicProfileSettings> {
  const [row] = await ctx.db.select().from(publicProfiles).where(eq(publicProfiles.userId, uid));
  if (row) {
    return {
      published: row.published,
      handle: row.handle,
      displayName: row.displayName,
      bio: row.bio,
      links: row.links as PublicProfileSettings['links'],
      show: { ...DEFAULT_SHOW, ...row.show },
      theme: row.theme as PublicProfileSettings['theme'],
      url: profileUrl(ctx, row.handle),
      views: row.views,
    };
  }
  // Not created yet: a draft the app shows in the editor (nothing is public until saved + published).
  const [u] = await ctx.db.select({ displayName: users.displayName }).from(users).where(eq(users.id, uid));
  const handle = await suggestHandle(ctx, u?.displayName ?? null, uid);
  return {
    published: false,
    handle,
    displayName: u?.displayName?.trim() || 'Yaqeen',
    bio: '',
    links: [],
    show: DEFAULT_SHOW,
    theme: 'sky',
    url: profileUrl(ctx, handle),
    views: 0,
  };
}

export async function update(ctx: AppContext, uid: string, isGuest: boolean, input: PublicProfileUpdate): Promise<PublicProfileSettings> {
  if (isGuest) throw forbidden('account_required', 'Sign in to publish a profile card');
  if (RESERVED_HANDLES.has(input.handle)) throw badRequest('handle_reserved');
  const [u] = await ctx.db.select({ status: users.status }).from(users).where(eq(users.id, uid));
  if (!u || u.status !== 'active') throw forbidden('account_inactive');
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
    .where(and(eq(publicProfiles.handle, h), eq(publicProfiles.published, true)));
  if (!row || row.status !== 'active') return null;
  const p = row.p;
  const show = { ...DEFAULT_SHOW, ...p.show };
  const uid = p.userId;

  let level: PublicProfileView['level'] = null;
  if (show.level) {
    // Lifetime earned points: spending on rewards never lowers the level.
    const l = levelFor(await lifetimePoints(ctx, uid));
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
  };
}

/* ------------------------------------------------------------------ journey */

/** Lifetime earned points (positive ledger rows): spending never lowers a level. */
async function lifetimePoints(ctx: AppContext, uid: string): Promise<number> {
  const [sum] = await ctx.db
    .select({ pts: sql<number>`coalesce(sum(${pointsLedger.delta}), 0)::int` })
    .from(pointsLedger)
    .where(and(eq(pointsLedger.userId, uid), gt(pointsLedger.delta, 0)));
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
  };
}

/** One page open (bots excluded by the caller). A counter only — nothing about the visitor. */
export async function countView(ctx: AppContext, handle: string) {
  await ctx.db
    .update(publicProfiles)
    .set({ views: sql`${publicProfiles.views} + 1` })
    .where(and(eq(publicProfiles.handle, handle.trim().toLowerCase()), eq(publicProfiles.published, true)));
}
