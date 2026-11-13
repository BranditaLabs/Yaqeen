/**
 * «المسابقات» in the admin (design §3.4, §11), prefix /admin/competitions:
 *   tournaments (marketing), weekly league settings/stats/rollover, the level board, moderation of
 *   competitor names/photos/participation and reports (support), the badge catalogue.
 * Every write runs in one transaction with its audit row; the onResponse hook bumps the `community`
 * and `profile` caches (INVALIDATES in app.ts). Standings come from the snapshots; aggregates are
 * suppressed under K_ANONYMITY. Never worship detail — points and levels only.
 */
import { sql } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import {
  type AdminCompetitorRow,
  type AdminLeagueStats,
  type AdminReportRow,
  AdminReason,
  AdminTournamentCreate,
  AdminTournamentPatch,
  BADGE_KINDS,
  CompetitorAction,
  LeaderboardScope,
  LeagueSettings,
  LeagueSettingsBase,
  ResolveReport,
} from '@yaqeen/contracts';
import type { Db } from '../../db/client.js';
import { appConfig } from '../../db/schema.js';
import { memberHandle, weekWindow } from '../../domain/community.js';
import { pct, suppress } from '../../domain/aggregates.js';
import { addDays } from '../../domain/points.js';
import { audit } from '../../lib/audit.js';
import { AppError, badRequest, conflict, notFound } from '../../lib/errors.js';
import { adminOf } from '../../plugins/auth.js';
import { runCommunityJob } from '../../jobs/community.js';
import * as avatar from '../../services/avatar.service.js';
import { LEAGUES_CONFIG_KEY, parseLeagueSettings, readLeagueSettings } from '../../services/community-settings.service.js';
import {
  type AvatarColumns,
  type DbOrTx,
  adminPhotoUrls,
  avatarOf,
  leaveEverything,
  recomputeCommunityConsent,
  toCompetitor,
  type CompetitorRow,
  COMPETITOR_COLUMNS,
  COMPETITOR_JOINS,
} from '../../services/community.service.js';
import * as leaderboard from '../../services/leaderboard.service.js';
import * as tournaments from '../../services/tournaments.service.js';
import { sendPhoto } from '../public/me.routes.js';

const UserParam = z.object({ userId: z.string().uuid() });
const IdParam = z.object({ id: z.string().uuid() });

type CompetitorDbRow = AvatarColumns & {
  user_id: string;
  handle: string | null;
  display_name: string | null;
  name_hidden: boolean;
  photo_locked: boolean;
  photo_active: boolean;
  banned: boolean;
  leagues: boolean;
  leaderboard: boolean;
  leaderboard_country: boolean;
  attested: boolean;
  division: number;
  open_reports: number;
  last_photo_at: Date | null;
};

const COMPETITOR_SELECT = sql.raw(`
  select u.id as user_id, pp.handle, u.display_name, (u.name_hidden_at is not null) as name_hidden,
    (u.photo_locked_at is not null) as photo_locked, coalesce(ap.status = 'active', false) as photo_active,
    u.avatar_kind, u.avatar_preset, u.avatar_photo_id,
    (cm.banned_at is not null) as banned, coalesce(cm.leagues, false) as leagues, coalesce(cm.leaderboard, false) as leaderboard,
    coalesce(cm.leaderboard_country, false) as leaderboard_country, (u.adult_attested_at is not null) as attested,
    coalesce(cm.division, 1)::int as division,
    (select count(*) from community_reports r where r.target_user_id = u.id and r.resolved_at is null)::int as open_reports,
    (select max(created_at) from avatar_photos x where x.user_id = u.id) as last_photo_at
  from users u
  left join public_profiles pp on pp.user_id = u.id
  left join avatar_photos ap on ap.id = u.avatar_photo_id
  left join community_members cm on cm.user_id = u.id`);

/** Competitor rows for support, with the photo history (any status within the 7-day retention). */
export async function competitorRows(db: DbOrTx, where: ReturnType<typeof sql>, now: Date, limit = 50): Promise<AdminCompetitorRow[]> {
  const r = await db.execute<CompetitorDbRow>(sql`${COMPETITOR_SELECT} where ${where} order by u.updated_at desc limit ${limit}`);
  if (!r.rows.length) return [];
  const ids = JSON.stringify(r.rows.map((x) => x.user_id));
  const cutoff = new Date(now.getTime() - avatar.PHOTO_RETENTION_DAYS * 86_400_000);
  const photos = await db.execute<{ id: string; user_id: string; status: 'active' | 'replaced' | 'removed'; created_at: Date; by_support: boolean }>(sql`
    select id, user_id, status, created_at, (removed_by is not null) as by_support from avatar_photos
    where user_id in (select x::uuid from jsonb_array_elements_text(${ids}::jsonb) as x)
      and (status = 'active' or coalesce(removed_at, created_at) > ${cutoff})
    order by created_at desc`);
  return r.rows.map((x) => ({
    userId: x.user_id,
    handle: x.handle,
    name: x.display_name,
    avatar: avatarOf(x, x.photo_active, (pid) => adminPhotoUrls(x.user_id, pid)),
    nameHidden: x.name_hidden,
    photoHidden: x.photo_locked,
    photoLocked: x.photo_locked,
    banned: x.banned,
    leagues: x.leagues,
    leaderboard: x.leaderboard,
    leaderboardCountry: x.leaderboard_country,
    attestedAdult: x.attested,
    division: Number(x.division),
    openReports: Number(x.open_reports),
    lastPhotoAt: x.last_photo_at ? new Date(x.last_photo_at).toISOString() : null,
    photos: photos.rows
      .filter((p) => p.user_id === x.user_id)
      .map((p) => ({ id: p.id, status: p.status, createdAt: new Date(p.created_at).toISOString(), removedBySupport: p.by_support })),
  }));
}

export async function competitor(db: DbOrTx, userId: string, now: Date): Promise<AdminCompetitorRow> {
  const [row] = await competitorRows(db, sql`u.id = ${userId}`, now, 1);
  if (!row) throw notFound('user');
  return row;
}

/** Hide-name rotates the handle unless the card is published and not moderated (the card URL stays). */
async function rotateHandle(tx: DbOrTx, userId: string, now: Date): Promise<{ from: string; to: string } | null> {
  const r = await tx.execute<{ handle: string; published: boolean; moderated: boolean }>(sql`
    select handle, published, (moderated_at is not null) as moderated from public_profiles where user_id = ${userId} for update`);
  const card = r.rows[0];
  if (!card || (card.published && !card.moderated)) return null;
  for (let i = 0; i < 10; i++) {
    const to = memberHandle(Math.random);
    const taken = await tx.execute(sql`select 1 from public_profiles where handle = ${to}`);
    if (taken.rows.length) continue;
    await tx.execute(sql`update public_profiles set handle = ${to}, updated_at = ${now} where user_id = ${userId}`);
    return { from: card.handle, to };
  }
  throw new AppError(500, 'handle_unavailable');
}

export const adminCompetitionsRoutes: FastifyPluginAsync = async (app) => {
  const { ctx } = app;
  const db: Db = ctx.db;
  const read = app.requireAdmin(['marketing', 'support']);
  const marketing = app.requireAdmin(['marketing']);
  const support = app.requireAdmin(['support']);
  const superOnly = app.requireAdmin([]);

  /* ------------------------------------------------------------ tournaments */

  app.get('/tournaments', { preHandler: read }, async () => tournaments.adminList(ctx));

  app.get('/tournaments/:id', { preHandler: read }, async (req) => {
    const { id } = IdParam.parse(req.params);
    return tournaments.adminGet(db, id, ctx.now());
  });

  app.post('/tournaments', { preHandler: marketing }, async (req) => {
    const body = AdminTournamentCreate.parse(req.body);
    return db.transaction(async (tx) => {
      const row = await tournaments.create(tx, body, adminOf(req).sub, ctx.now());
      await audit(tx, req, { action: 'tournament.create', targetType: 'tournament', targetId: row.id, after: row });
      return row;
    });
  });

  app.patch('/tournaments/:id', { preHandler: marketing }, async (req) => {
    const { id } = IdParam.parse(req.params);
    const body = AdminTournamentPatch.parse(req.body);
    return db.transaction(async (tx) => {
      const { before, after } = await tournaments.patch(tx, id, body, ctx.now());
      await audit(tx, req, { action: 'tournament.update', targetType: 'tournament', targetId: id, reason: body.reason ?? null, before, after });
      return after;
    });
  });

  app.post('/tournaments/:id/publish', { preHandler: marketing }, async (req) => {
    const { id } = IdParam.parse(req.params);
    return db.transaction(async (tx) => {
      const { before, after } = await tournaments.publish(tx, id, ctx.now());
      await audit(tx, req, { action: 'tournament.publish', targetType: 'tournament', targetId: id, before, after });
      return after;
    });
  });

  app.post('/tournaments/:id/close', { preHandler: marketing }, async (req) => {
    const { id } = IdParam.parse(req.params);
    const { reason } = AdminReason.parse(req.body);
    return db.transaction(async (tx) => {
      const { before, after } = await tournaments.closeEarly(tx, id, ctx.now());
      await audit(tx, req, { action: 'tournament.close', targetType: 'tournament', targetId: id, reason, before, after });
      return after;
    });
  });

  app.post('/tournaments/:id/cancel', { preHandler: marketing }, async (req) => {
    const { id } = IdParam.parse(req.params);
    const { reason } = AdminReason.parse(req.body);
    return db.transaction(async (tx) => {
      const { before, after } = await tournaments.cancel(tx, id, ctx.now());
      await audit(tx, req, { action: 'tournament.cancel', targetType: 'tournament', targetId: id, reason, before, after });
      return after;
    });
  });

  app.get('/tournaments/:id/standings', { preHandler: read }, async (req) => {
    const { id } = IdParam.parse(req.params);
    const { limit } = z.object({ limit: z.coerce.number().int().min(1).max(100).default(50) }).parse(req.query);
    return tournaments.adminStandings(ctx, id, limit);
  });

  app.get('/tournaments/:id/stats', { preHandler: read }, async (req) => {
    const { id } = IdParam.parse(req.params);
    return tournaments.stats(ctx, id);
  });

  /* ---------------------------------------------------------------- leagues */

  app.get('/leagues/settings', { preHandler: read }, async () => readLeagueSettings(ctx));

  /** Applies from the next week to start: a running week keeps the settings it started with. */
  app.put('/leagues/settings', { preHandler: marketing }, async (req) => {
    const base = LeagueSettingsBase.parse(req.body);
    const parsed = LeagueSettings.safeParse(base);
    if (!parsed.success) throw badRequest('settings_invalid', 'promote + demote must be smaller than the group size');
    const next = parsed.data;
    await db.transaction(async (tx) => {
      const before = await readLeagueSettings(ctx);
      await tx
        .insert(appConfig)
        .values({ key: LEAGUES_CONFIG_KEY, value: next, updatedBy: adminOf(req).sub })
        .onConflictDoUpdate({ target: appConfig.key, set: { value: next, updatedBy: adminOf(req).sub, updatedAt: ctx.now() } });
      await audit(tx, req, { action: 'leagues.settings', targetType: 'config', targetId: LEAGUES_CONFIG_KEY, before, after: next });
    });
    await ctx.cache.bumpNamespace('config');
    return readLeagueSettings(ctx);
  });

  app.get('/leagues/stats', { preHandler: read }, async (): Promise<AdminLeagueStats> => {
    const week = weekWindow(ctx.now());
    const w = await db.execute<{ settings: unknown }>(sql`select settings from league_weeks where starts_on = ${week.startsOn}`);
    const settingsInForce = w.rows[0]?.settings ? parseLeagueSettings(w.rows[0].settings) : await readLeagueSettings(ctx);
    const groups = await db.execute<{ n: number }>(sql`select count(*)::int as n from league_groups where starts_on = ${week.startsOn}`);
    const byDiv = await db.execute<{ division: number; n: number; active: number }>(sql`
      select division, count(*)::int as n, count(*) filter (where coalesce(snapshot_points, 0) > 0)::int as active
      from league_members where starts_on = ${week.startsOn} and left_at is null group by division`);
    const counts = new Map(byDiv.rows.map((r) => [Number(r.division), r]));
    const total = byDiv.rows.reduce((s, r) => s + Number(r.n), 0);
    const active = byDiv.rows.reduce((s, r) => s + Number(r.active), 0);
    const last = await db.execute<{ up: number; down: number; any: number }>(sql`
      select count(*) filter (where outcome = 'up')::int as up, count(*) filter (where outcome = 'down')::int as down, count(*)::int as any
      from league_members m join league_weeks w on w.starts_on = m.starts_on
      where m.starts_on = ${addDays(week.startsOn, -7)} and w.status = 'closed'`);
    const l = last.rows[0];
    return {
      startsOn: week.startsOn,
      endsAt: week.endsAt.toISOString(),
      groups: Number(groups.rows[0]?.n ?? 0),
      members: [1, 2, 3, 4, 5, 6].map((d) => ({ division: d, count: suppress(Number(counts.get(d)?.n ?? 0)) })),
      activeShare: pct(active, total),
      settingsInForce,
      lastWeek: l && Number(l.any) > 0 ? { up: suppress(Number(l.up)), down: suppress(Number(l.down)) } : null,
    };
  });

  /** One group, read-only (snapshot during the week, finals once closed). */
  app.get('/leagues/groups/:id', { preHandler: read }, async (req) => {
    const { id } = IdParam.parse(req.params);
    const g = await db.execute<{ id: string; starts_on: string; division: number; size: number; closed_at: Date | null }>(sql`
      select id, starts_on::text as starts_on, division, size, closed_at from league_groups where id = ${id}`);
    const group = g.rows[0];
    if (!group) throw notFound('group');
    const closed = group.closed_at !== null;
    const r = await db.execute<CompetitorRow & { outcome: string | null }>(sql`
      select ${COMPETITOR_COLUMNS}, ${closed ? sql.raw('m.final_points') : sql.raw('m.snapshot_points')} as points,
        ${closed ? sql.raw('m.final_rank') : sql.raw('m.snapshot_rank')} as rank, m.outcome
      from league_members m join users u on u.id = m.user_id ${COMPETITOR_JOINS}
      where m.group_id = ${id} and m.left_at is null
      order by coalesce(${closed ? sql.raw('m.final_rank') : sql.raw('m.snapshot_rank')}, 32767) asc, pp.handle asc`);
    return {
      id: group.id,
      startsOn: group.starts_on,
      division: Number(group.division),
      size: r.rows.length,
      closedAt: group.closed_at ? new Date(group.closed_at).toISOString() : null,
      rows: r.rows.map((x) => ({ ...toCompetitor(ctx, x, null), userId: x.user_id, outcome: x.outcome })),
    };
  });

  /** Run the community job body now (closes due weeks, snapshot, due tournaments). */
  app.post('/leagues/rollover', { preHandler: superOnly }, async (req) => {
    const { reason } = AdminReason.parse(req.body);
    await db.transaction((tx) => audit(tx, req, { action: 'leagues.rollover', targetType: 'config', targetId: LEAGUES_CONFIG_KEY, reason }));
    return runCommunityJob(ctx);
  });

  /* ------------------------------------------------------------ leaderboard */

  app.get('/leaderboard', { preHandler: read }, async (req) => {
    const q = z.object({ scope: LeaderboardScope.default('global'), country: z.string().regex(/^[A-Za-z]{2}$/).optional() }).parse(req.query);
    if (q.scope === 'country' && !q.country) throw badRequest('country_required');
    return leaderboard.adminView(ctx, q.scope, q.country);
  });

  /* ------------------------------------------------------------- moderation */

  app.get('/competitors', { preHandler: read }, async (req) => {
    const q = z
      .object({ filter: z.enum(['reported', 'hidden', 'banned', 'recent_photo']).optional(), q: z.string().trim().max(60).optional() })
      .parse(req.query);
    const conds = [sql`(cm.user_id is not null or exists (select 1 from avatar_photos z where z.user_id = u.id) or exists (select 1 from community_reports z where z.target_user_id = u.id))`];
    if (q.filter === 'reported') conds.push(sql`exists (select 1 from community_reports r where r.target_user_id = u.id and r.resolved_at is null)`);
    if (q.filter === 'hidden') conds.push(sql`(u.name_hidden_at is not null or u.photo_locked_at is not null)`);
    if (q.filter === 'banned') conds.push(sql`cm.banned_at is not null`);
    if (q.filter === 'recent_photo') conds.push(sql`exists (select 1 from avatar_photos z where z.user_id = u.id and z.created_at > ${new Date(ctx.now().getTime() - 7 * 86_400_000)})`);
    if (q.q) {
      const like = `%${q.q.replace(/^@/, '').replace(/[%_]/g, '')}%`;
      conds.push(sql`(pp.handle ilike ${like} or u.display_name ilike ${like})`);
    }
    return { items: await competitorRows(db, sql.join(conds, sql` and `), ctx.now(), 100) };
  });

  app.get('/competitors/:userId', { preHandler: read }, async (req) => {
    const { userId } = UserParam.parse(req.params);
    return competitor(db, userId, ctx.now());
  });

  /** A photo support moderates: any status within the 7-day retention, never cached. */
  app.get('/competitors/:userId/photos/:photoId/:size', { preHandler: support }, async (req, reply) => {
    const p = z.object({ userId: z.string().uuid(), photoId: z.string().uuid(), size: z.enum(['96', '256']) }).parse(req.params);
    const photo = await avatar.adminPhotoBytes(db, p.userId, p.photoId, Number(p.size) as avatar.PhotoSize, ctx.now());
    if (!photo) throw notFound('photo');
    return sendPhoto(req, reply, photo, 'private, no-store');
  });

  app.post('/competitors/:userId/:action', { preHandler: support }, async (req) => {
    const { userId } = UserParam.parse(req.params);
    const action = CompetitorAction.parse((req.params as { action?: string }).action);
    const { reason } = AdminReason.parse(req.body);
    const now = ctx.now();
    const adminId = adminOf(req).sub;
    return db.transaction(async (tx) => {
      const exists = await tx.execute(sql`select 1 from users where id = ${userId} for update`);
      if (!exists.rows.length) throw notFound('user');
      const before = await competitor(tx, userId, now);
      const extra: Record<string, unknown> = {};
      switch (action) {
        case 'hide-name': {
          await tx.execute(sql`update users set name_hidden_at = ${now}, name_hidden_reason = ${reason}, updated_at = ${now} where id = ${userId}`);
          const rotated = await rotateHandle(tx, userId, now);
          if (rotated) Object.assign(extra, { handleFrom: rotated.from, handleTo: rotated.to });
          break;
        }
        case 'restore-name':
          await tx.execute(sql`update users set name_hidden_at = null, name_hidden_reason = null, updated_at = ${now} where id = ${userId}`);
          break;
        case 'hide-photo': {
          const r = await avatar.adminHidePhoto(tx, userId, adminId, reason, now);
          extra.photoId = r.photoId;
          break;
        }
        case 'restore-photo': {
          const r = await avatar.adminRestorePhoto(tx, userId, now);
          extra.photoId = r.photoId;
          break;
        }
        case 'ban':
          await tx.execute(sql`
            insert into community_members (user_id, banned_at, banned_reason) values (${userId}, ${now}, ${reason})
            on conflict (user_id) do update set banned_at = ${now}, banned_reason = ${reason}, updated_at = ${now}`);
          await leaveEverything(tx, userId, now);
          break;
        case 'unban':
          await tx.execute(sql`update community_members set banned_at = null, banned_reason = null, updated_at = ${now} where user_id = ${userId}`);
          break;
      }
      await recomputeCommunityConsent(tx, userId, 'support');
      const after = await competitor(tx, userId, now);
      await audit(tx, req, { action: `competitor.${action.replace('-', '_')}`, targetType: 'user', targetId: userId, reason, before, after: { ...after, ...extra } });
      return after;
    });
  });

  /* ---------------------------------------------------------------- reports */

  app.get('/reports', { preHandler: read }, async (req): Promise<{ items: AdminReportRow[] }> => {
    const { status } = z.object({ status: z.enum(['open', 'resolved']).default('open') }).parse(req.query);
    const r = await db.execute<{ id: string; target: string; reason: 'name' | 'photo' | 'other'; n: number; created_at: Date }>(sql`
      select (array_agg(id order by created_at))[1] as id, target_user_id as target, reason, count(*)::int as n, min(created_at) as created_at
      from community_reports
      where ${status === 'open' ? sql`resolved_at is null` : sql`resolved_at is not null`}
      group by target_user_id, reason
      order by count(*) desc, min(created_at) asc
      limit 100`);
    const targets = await competitorRows(db, sql`u.id in (select x::uuid from jsonb_array_elements_text(${JSON.stringify([...new Set(r.rows.map((x) => x.target))])}::jsonb) as x)`, ctx.now(), 100);
    const byId = new Map(targets.map((t) => [t.userId, t]));
    return {
      items: r.rows
        .filter((x) => byId.has(x.target))
        .map((x) => ({ id: x.id, target: byId.get(x.target)!, reason: x.reason, count: Number(x.n), createdAt: new Date(x.created_at).toISOString() })),
    };
  });

  /** Resolves every open report on the report's target (one decision per person). */
  app.post('/reports/:id/resolve', { preHandler: support }, async (req) => {
    const { id } = IdParam.parse(req.params);
    const body = ResolveReport.parse(req.body);
    const now = ctx.now();
    return db.transaction(async (tx) => {
      const r = await tx.execute<{ target_user_id: string }>(sql`select target_user_id from community_reports where id = ${id}`);
      const target = r.rows[0]?.target_user_id;
      if (!target) throw notFound('report');
      const done = await tx.execute<{ id: string }>(sql`
        update community_reports set resolved_at = ${now}, resolved_by = ${adminOf(req).sub}, resolution = ${body.resolution}
        where target_user_id = ${target} and resolved_at is null returning id`);
      if (!done.rows.length) throw conflict('report_resolved', 'Already resolved');
      await audit(tx, req, { action: 'report.resolve', targetType: 'user', targetId: target, reason: body.reason, after: { resolution: body.resolution, reports: done.rows.map((x) => x.id) } });
      return { ok: true, resolved: done.rows.length };
    });
  });

  /* ----------------------------------------------------------------- badges */

  app.get('/badges', { preHandler: read }, async () => {
    const stored = await db.execute<{ kind: string; n: number }>(sql`select kind, count(*)::int as n from user_badges group by kind`);
    const streak = await db.execute<{ n: number }>(sql`select count(*)::int as n from points_ledger where reason = 'milestone' and ref_key like 'milestone:%'`);
    const level = await db.execute<{ n: number }>(sql`select count(*)::int as n from user_point_totals where lifetime_earned >= 500`);
    const counts = new Map(stored.rows.map((x) => [x.kind, Number(x.n)]));
    counts.set('streak', Number(streak.rows[0]?.n ?? 0));
    counts.set('level', Number(level.rows[0]?.n ?? 0));
    return { items: BADGE_KINDS.map((kind) => ({ kind, count: suppress(counts.get(kind) ?? 0) })) };
  });
};
