/**
 * «تلاواتي» — users' own recorded recitations (design doc §16, APP_SPEC §5.24 / §5.26 / §5.31).
 *
 * Lifecycle: upload (private → `private_ready`, never sent to the AI check; members/public →
 * `processing`) → the internal ASR service transcribes it and `domain/recitation-match` decides:
 * `approved` / `needs_review` (a religious reviewer decides) / `rejected`. A private recording switched
 * to members/public is verified then; switching back to private keeps an approved result. Without
 * `ASR_URL` shared recordings go to `needs_review` — never auto-approved.
 *
 * Privacy (CLAUDE.md rules 1–2): nothing here reaches analytics or ad sinks. Others see a recording only
 * when it is approved, shared, not held by reports, and its owner is an active, attested community
 * member (blocks hide both ways). Admins see a recording only while it is in the moderation queue.
 * Sharing needs a signed-in account, the 18+ attestation and the community opt-in (consent `community`
 * with a handle) — the same gates as the competitions.
 */
import { and, eq, sql } from 'drizzle-orm';
import type { FastifyRequest } from 'fastify';
import {
  type AdminCommentDecision,
  type AdminCommentItem,
  type AdminRecordingDecision,
  type AdminRecordingItem,
  type AdminRecordingQueue,
  AUTO_HIDE_REPORTS,
  COMMENT_RATE,
  COMMENTS_PAGE_SIZE,
  type MemberRecordings,
  type MyRecordings,
  PROFILE_RECORDINGS_MAX,
  type PublicRecording,
  type ReactionCounts,
  type ReactionKind,
  type ReactionState,
  RECORDING_DURATION_TOLERANCE_MS,
  RECORDING_MAX_BYTES,
  RECORDING_MAX_MS,
  RECORDING_REPORTS_PER_DAY,
  RECORDING_UPLOADS_PER_DAY,
  type Recording,
  type RecordingComment,
  type RecordingCommentsPage,
  type RecordingMeta,
  type RecordingPatch,
  type RecordingReportReason,
  type RecordingStatus,
  type RecordingWord,
} from '@yaqeen/contracts';
import type { AppContext } from '../context.js';
import type { Db } from '../db/client.js';
import { recordingComments, recordingDaily, recordingReactions, recordingReports, recordings } from '../db/schema.js';
import { checkComment } from '../domain/comments.js';
import { durations, inspectM4a, matchesRecordingFormat } from '../domain/m4a.js';
import { expectedAyat, validRange } from '../domain/quran-words.js';
import { ayahStarts } from '../domain/ayah-starts.js';
import { matchRecitation } from '../domain/recitation-match.js';
import { AsrTooLong, AsrUndecodable } from '../integrations/asr.js';
import { audit } from '../lib/audit.js';
import { AppError, badRequest, conflict, forbidden, notFound } from '../lib/errors.js';
import { captureError } from '../lib/observability.js';
import { COMPETITOR_COLUMNS_ANY, COMPETITOR_JOINS, type CompetitorRow, toCompetitor } from './community.service.js';
import { cardFeatureOn } from './cards-settings.service.js';
import { featureOn as flagOn } from './community-settings.service.js';

type Tx = Parameters<Parameters<Db['transaction']>[0]>[0];
type DbOrTx = Db | Tx;

/**
 * Failed AI-check attempts before a recording goes to a reviewer instead. The in-process queue makes at
 * most `1 + RETRY_DELAYS_MS.length` (2) of them, so the last one is always the sweeper's — at least
 * 10 minutes after queueing, in production at the next hourly community job: a short ASR outage or a
 * slow cold start does not send every shared recording to the human queue.
 */
export const MAX_ASR_ATTEMPTS = 3;
/** The sweeper retries `processing` recordings queued longer ago than this. */
export const SWEEP_AFTER_MS = 10 * 60_000;
/** Wall-clock budget for the sweeper's AI checks per run (each may take up to `ASR_TIMEOUT_MS`); the rest wait for the next run. */
export const SWEEP_BUDGET_MS = 180_000;
/** Removed recordings and support-removed comment text are kept this long for «restore», then deleted. */
export const REMOVED_RETENTION_DAYS = 7;
/** Transcript snippet kept for the reviewer while in the queue. */
const TRANSCRIPT_MAX = 500;

const tooMany = (code: string) => new AppError(429, code);

/* ------------------------------------------------------------------ basics */

/** Africa/Cairo calendar day (the daily upload cap). */
export function cairoDay(now: Date): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** Remote-config flag `recordings` (off by default, contracts `FEATURE_DEFAULTS_OFF`). */
export async function featureOn(ctx: AppContext): Promise<boolean> {
  return flagOn(ctx, 'recordings');
}

async function requireFeature(ctx: AppContext) {
  if (!(await featureOn(ctx))) throw forbidden('feature_off');
}

interface Identity {
  isGuest: boolean;
  active: boolean;
  attested: boolean;
  community: boolean;
  banned: boolean;
  handle: string | null;
}

async function identity(db: DbOrTx, uid: string): Promise<Identity> {
  const r = await db.execute<{ is_guest: boolean; status: string; attested: boolean; community: boolean; banned: boolean; handle: string | null }>(sql`
    select u.is_guest, u.status, (u.adult_attested_at is not null) as attested,
      exists (select 1 from consents c where c.user_id = u.id and c.kind = 'community' and c.granted) as community,
      exists (select 1 from community_members cm where cm.user_id = u.id and cm.banned_at is not null) as banned,
      (select pp.handle from public_profiles pp where pp.user_id = u.id) as handle
    from users u where u.id = ${uid}`);
  const row = r.rows[0];
  if (!row) throw notFound('user');
  return { isGuest: row.is_guest, active: row.status === 'active', attested: row.attested, community: row.community, banned: row.banned, handle: row.handle };
}

/**
 * Listening to members' recordings and reading their comments need a signed-in account: a guest token
 * (minted without signing in) or an inactive account is refused before anything is looked up.
 */
async function requireAccount(db: DbOrTx, uid: string) {
  const id = await identity(db, uid);
  if (id.isGuest || !id.active) throw forbidden('account_required');
}

/** Sharing, reacting and commenting need an account, the 18+ attestation and the community opt-in. */
function requireMember(id: Identity) {
  if (id.isGuest) throw forbidden('account_required');
  if (!id.active) throw forbidden('account_required');
  if (id.banned) throw forbidden('community_banned');
  if (!id.attested) throw forbidden('attestation_required');
  if (!id.community || !id.handle) throw forbidden('community_required');
}

/**
 * The owner/author of a member view is the community's public competitor projection
 * (`community.service`): the same handle, name (null while support hides it), avatar (a photo only
 * when the public avatar route would serve it) and nightly level ring as every competition list —
 * without points or rank. Aliases: u = users, pp = public_profiles, ap, pcm, t (`COMPETITOR_JOINS`).
 */
const OWNER_COLUMNS = sql`${COMPETITOR_COLUMNS_ANY}, null::int as points, null::int as rank`;
const OWNER_JOINS = sql`join users u on u.id = r.user_id ${COMPETITOR_JOINS}`;
/**
 * A user (alias `a`) may be seen by members — as a recording's owner or a comment's author: active,
 * attested, in the community (consent `community`), not banned. Leaving the community, a ban or a lost
 * attestation hides their recordings and their comments everywhere (nothing public after leaving).
 */
function shareable(a: 'u' | 'a') {
  return sql.raw(`${a}.status = 'active' and ${a}.adult_attested_at is not null
  and exists (select 1 from consents c where c.user_id = ${a}.id and c.kind = 'community' and c.granted)
  and not exists (select 1 from community_members cm where cm.user_id = ${a}.id and cm.banned_at is not null)`);
}
const OWNER_SHAREABLE = shareable('u');
/** A recording members may hear. */
const MEMBER_VISIBLE = sql.raw(`r.status = 'approved' and r.held_at is null and r.visibility in ('members', 'public')`);

type OwnerRow = CompetitorRow;

/** The public competitor shape without points or rank. */
function competitor(ctx: AppContext, row: OwnerRow, viewerId: string | null) {
  return toCompetitor(ctx, row, viewerId);
}

async function blockedEitherWay(db: DbOrTx, a: string, b: string): Promise<boolean> {
  if (a === b) return false;
  const r = await db.execute<{ x: number }>(sql`
    select 1 as x from community_blocks
    where (user_id = ${a} and blocked_user_id = ${b}) or (user_id = ${b} and blocked_user_id = ${a}) limit 1`);
  return r.rows.length > 0;
}

/** Reaction counts and the viewer's reaction for a set of recordings. */
async function reactionsFor(db: DbOrTx, ids: string[], viewerId: string | null): Promise<Map<string, { counts: ReactionCounts; mine: ReactionKind | null; comments: number }>> {
  const out = new Map<string, { counts: ReactionCounts; mine: ReactionKind | null; comments: number }>();
  for (const id of ids) out.set(id, { counts: { mashallah: 0, barakallah: 0, ahsant: 0 }, mine: null, comments: 0 });
  if (ids.length === 0) return out;
  const list = sql.join(
    ids.map((id) => sql`${id}::uuid`),
    sql`, `,
  );
  const rows = await db.execute<{ recording_id: string; kind: ReactionKind; n: number; mine: boolean }>(sql`
    select recording_id, kind, count(*)::int as n, bool_or(user_id = ${viewerId ?? '00000000-0000-0000-0000-000000000000'}::uuid) as mine
    from recording_reactions where recording_id in (${list}) group by recording_id, kind`);
  for (const r of rows.rows) {
    const e = out.get(r.recording_id)!;
    e.counts[r.kind] = Number(r.n);
    if (r.mine) e.mine = r.kind;
  }
  const comments = await db.execute<{ recording_id: string; n: number }>(sql`
    select c.recording_id, count(*)::int as n from recording_comments c join users a on a.id = c.user_id
    where c.recording_id in (${list}) and c.status = 'visible' and ${shareable('a')} group by c.recording_id`);
  for (const r of comments.rows) out.get(r.recording_id)!.comments = Number(r.n);
  return out;
}

/* ------------------------------------------------------------- daily cap */

/** Take one of today's uploads/verifications, or refuse with `recording_daily_limit`. */
async function takeDaily(tx: DbOrTx, uid: string, day: string) {
  const r = await tx.execute<{ count: number }>(sql`
    insert into recording_daily (user_id, day, count) values (${uid}, ${day}, 1)
    on conflict (user_id, day) do update set count = recording_daily.count + 1
    where recording_daily.count < ${RECORDING_UPLOADS_PER_DAY}
    returning count`);
  if (r.rows.length === 0) throw tooMany('recording_daily_limit');
}

async function leftToday(db: DbOrTx, uid: string, day: string): Promise<number> {
  const [row] = await db
    .select({ count: recordingDaily.count })
    .from(recordingDaily)
    .where(and(eq(recordingDaily.userId, uid), eq(recordingDaily.day, day)));
  return Math.max(0, RECORDING_UPLOADS_PER_DAY - (row?.count ?? 0));
}

/* ------------------------------------------------------------------- owner */

type RecordingRow = typeof recordings.$inferSelect;

function toRecording(r: RecordingRow, extra: { counts: ReactionCounts; mine: ReactionKind | null; comments: number }): Recording {
  return {
    id: r.id,
    surah: r.surah,
    fromAyah: r.fromAyah,
    toAyah: r.toAyah,
    durationMs: r.durationMs,
    status: r.status as RecordingStatus,
    rejectReason: (r.rejectReason as Recording['rejectReason']) ?? null,
    visibility: r.visibility as Recording['visibility'],
    commentsOn: r.commentsOn,
    position: r.position,
    reactions: extra.counts,
    myReaction: extra.mine,
    commentCount: extra.comments,
    createdAt: r.createdAt.toISOString(),
    audioPath: `/v1/me/recordings/${r.id}/audio`,
    // Karaoke timings only once verified (a queued recording's tentative words stay server-side).
    words: r.status === 'approved' ? ((r.words as RecordingWord[] | null) ?? null) : null,
  };
}

/** Owner columns only — never the audio bytes. */
const OWN_COLUMNS = {
  id: recordings.id,
  userId: recordings.userId,
  surah: recordings.surah,
  fromAyah: recordings.fromAyah,
  toAyah: recordings.toAyah,
  durationMs: recordings.durationMs,
  bytes: recordings.bytes,
  status: recordings.status,
  rejectReason: recordings.rejectReason,
  score: recordings.score,
  speech: recordings.speech,
  words: recordings.words,
  visibility: recordings.visibility,
  commentsOn: recordings.commentsOn,
  position: recordings.position,
  asrAttempts: recordings.asrAttempts,
  queuedAt: recordings.queuedAt,
  transcript: recordings.transcript,
  clientScore: recordings.clientScore,
  clientWords: recordings.clientWords,
  heldAt: recordings.heldAt,
  createdAt: recordings.createdAt,
  verifiedAt: recordings.verifiedAt,
  removedAt: recordings.removedAt,
};

async function ownRows(db: DbOrTx, uid: string): Promise<RecordingRow[]> {
  const rows = await db.select(OWN_COLUMNS).from(recordings).where(eq(recordings.userId, uid)).orderBy(recordings.position, recordings.createdAt);
  return rows as RecordingRow[];
}

export async function listMine(ctx: AppContext, uid: string): Promise<MyRecordings> {
  const rows = await ownRows(ctx.db, uid);
  const extra = await reactionsFor(
    ctx.db,
    rows.map((r) => r.id),
    uid,
  );
  return { items: rows.map((r) => toRecording(r, extra.get(r.id)!)), leftToday: await leftToday(ctx.db, uid, cairoDay(ctx.now())) };
}

async function ownOne(ctx: AppContext, uid: string, id: string): Promise<Recording> {
  const [row] = (await ctx.db
    .select(OWN_COLUMNS)
    .from(recordings)
    .where(and(eq(recordings.id, id), eq(recordings.userId, uid)))) as RecordingRow[];
  if (!row) throw notFound('recording');
  const extra = await reactionsFor(ctx.db, [id], uid);
  return toRecording(row, extra.get(id)!);
}

/**
 * Validate an upload's bytes: size, container, AAC-LC mono 16 kHz, duration. The limit is checked
 * against the longest of the header (`mdhd`), the sample timing (`stts`) and the decoded frames, and the
 * three must agree — a forged header cannot pass a long clip as 30 s. Returns the file's duration.
 */
export function checkAudio(audio: Buffer): number {
  if (audio.length > RECORDING_MAX_BYTES) throw new AppError(413, 'recording_too_large');
  const info = inspectM4a(audio);
  if (!info || !matchesRecordingFormat(info)) throw badRequest('recording_bad_format');
  const d = durations(info, RECORDING_DURATION_TOLERANCE_MS);
  if (d.longestMs > RECORDING_MAX_MS + RECORDING_DURATION_TOLERANCE_MS) throw badRequest('recording_too_long');
  if (!d.consistent || d.durationMs <= 0 || info.frames <= 0) throw badRequest('recording_bad_format');
  return d.durationMs;
}

/** POST /v1/me/recordings → 202 with the new recording. */
export async function upload(ctx: AppContext, uid: string, meta: RecordingMeta, audio: Buffer): Promise<Recording> {
  await requireFeature(ctx);
  const durationMs = checkAudio(audio);
  if (!validRange(meta.surah, meta.fromAyah, meta.toAyah)) throw badRequest('recording_invalid_range');
  const id0 = await identity(ctx.db, uid);
  if (id0.isGuest) throw forbidden('account_required');
  const shared = meta.visibility !== 'private';
  if (shared) requireMember(id0);
  const now = ctx.now();
  const { id, repeat } = await ctx.db.transaction(async (tx) => {
    // Serialise this user's uploads (the 3-per-profile limit, and the same take sent twice).
    await tx.execute(sql`select id from users where id = ${uid} for update`);
    if (meta.clientId) {
      // The same take again (a retry after a timeout, the offline queue): the recording already kept.
      const [kept] = await tx
        .select({ id: recordings.id })
        .from(recordings)
        .where(and(eq(recordings.userId, uid), eq(recordings.clientId, meta.clientId)));
      if (kept) return { id: kept.id, repeat: true };
    }
    const [{ n } = { n: 0 }] = await tx.select({ n: sql<number>`count(*)::int` }).from(recordings).where(eq(recordings.userId, uid));
    if (Number(n) >= PROFILE_RECORDINGS_MAX) throw conflict('recordings_limit');
    await takeDaily(tx, uid, cairoDay(now));
    const [row] = await tx
      .insert(recordings)
      .values({
        userId: uid,
        surah: meta.surah,
        fromAyah: meta.fromAyah,
        toAyah: meta.toAyah,
        durationMs,
        audio,
        bytes: audio.length,
        status: shared ? 'processing' : 'private_ready',
        visibility: meta.visibility,
        commentsOn: meta.commentsOn,
        position: Number(n) + 1,
        queuedAt: shared ? now : null,
        // The on-device pre-check: diagnostics for a reviewer only, never used to approve.
        clientScore: shared ? (meta.clientScore ?? null) : null,
        clientWords: shared ? (meta.clientWords ?? null) : null,
        clientId: meta.clientId ?? null,
        createdAt: now,
      })
      .returning({ id: recordings.id });
    return { id: row!.id, repeat: false };
  });
  if (shared && !repeat) schedule(ctx, id);
  return ownOne(ctx, uid, id);
}

export async function ownAudio(ctx: AppContext, uid: string, id: string): Promise<Buffer> {
  const [row] = await ctx.db
    .select({ audio: recordings.audio })
    .from(recordings)
    .where(and(eq(recordings.id, id), eq(recordings.userId, uid)));
  if (!row) throw notFound('recording');
  return row.audio;
}

/** PATCH /v1/me/recordings/:id — visibility, comments switch, position. */
export async function patch(ctx: AppContext, uid: string, id: string, p: RecordingPatch): Promise<Recording> {
  const now = ctx.now();
  let verify = false;
  await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`select id from users where id = ${uid} for update`);
    const rows = await ownRows(tx, uid);
    const rec = rows.find((r) => r.id === id);
    if (!rec) throw notFound('recording');
    const set: Partial<typeof recordings.$inferInsert> = {};
    if (p.commentsOn !== undefined) set.commentsOn = p.commentsOn;
    if (p.visibility !== undefined && p.visibility !== rec.visibility) {
      if (p.visibility === 'private') {
        set.visibility = 'private';
        // A pending check is abandoned (private recordings never reach the AI check or a reviewer);
        // an approved or rejected result is kept.
        if (rec.status === 'processing' || rec.status === 'needs_review') {
          Object.assign(set, { status: 'private_ready', queuedAt: null, transcript: null, clientScore: null, clientWords: null, score: null, speech: null });
        }
      } else {
        await requireFeature(ctx);
        requireMember(await identity(tx, uid));
        if (rec.status === 'rejected' || rec.status === 'removed') throw conflict('recording_not_public');
        set.visibility = p.visibility;
        if (rec.status === 'private_ready') {
          await takeDaily(tx, uid, cairoDay(now));
          Object.assign(set, { status: 'processing', queuedAt: now, asrAttempts: 0 });
          verify = true;
        }
      }
    }
    if (Object.keys(set).length) await tx.update(recordings).set(set).where(eq(recordings.id, id));
    if (p.position !== undefined) {
      const order = rows.filter((r) => r.id !== id).map((r) => r.id);
      order.splice(Math.min(p.position, rows.length) - 1, 0, id);
      for (const [k, rid] of order.entries()) await tx.update(recordings).set({ position: k + 1 }).where(eq(recordings.id, rid));
    }
  });
  if (verify) schedule(ctx, id);
  await ctx.cache.bumpNamespace('profile');
  return ownOne(ctx, uid, id);
}

/** DELETE /v1/me/recordings/:id — hard delete: audio, reactions, comments and their reports. */
export async function remove(ctx: AppContext, uid: string, id: string): Promise<void> {
  await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`select id from users where id = ${uid} for update`);
    const [rec] = await tx
      .select({ id: recordings.id })
      .from(recordings)
      .where(and(eq(recordings.id, id), eq(recordings.userId, uid)));
    if (!rec) throw notFound('recording');
    await deleteRecordings(tx, sql`r.id = ${id}`);
    const rest = await tx.select({ id: recordings.id }).from(recordings).where(eq(recordings.userId, uid)).orderBy(recordings.position, recordings.createdAt);
    for (const [k, r] of rest.entries()) await tx.update(recordings).set({ position: k + 1 }).where(eq(recordings.id, r.id));
  });
  await ctx.cache.bumpNamespace('profile');
}

/** Delete recordings matching `where` (alias r) with every report about them or their comments. */
async function deleteRecordings(tx: DbOrTx, where: ReturnType<typeof sql>) {
  await tx.execute(sql`
    delete from recording_reports rp using recording_comments c, recordings r
    where rp.target = 'comment' and rp.target_id = c.id and c.recording_id = r.id and ${where}`);
  await tx.execute(sql`
    delete from recording_reports rp using recordings r
    where rp.target = 'recording' and rp.target_id = r.id and ${where}`);
  // Reactions and comments cascade.
  await tx.execute(sql`delete from recordings r where ${where}`);
}

/* ------------------------------------------------------------ verification */

/** What the AI check needs (the community job builds one without HTTP clients). */
export type VerifyCtx = Pick<AppContext, 'db' | 'now' | 'cache' | 'asr'>;

interface Queue {
  chain: Promise<void>;
  pending: number;
  timers: Set<NodeJS.Timeout>;
}
const queues = new WeakMap<AppContext, Queue>();

function queueOf(ctx: AppContext): Queue {
  let q = queues.get(ctx);
  if (!q) {
    q = { chain: Promise.resolve(), pending: 0, timers: new Set() };
    queues.set(ctx, q);
  }
  return q;
}

/**
 * In-process backoff before retry n (1-based): one retry after 30 s. After that the recording stays
 * `processing` and the sweeper takes over (it makes the last of `MAX_ASR_ATTEMPTS`).
 */
export const RETRY_DELAYS_MS = [30_000];

/** Verify in the background, one at a time per process (bounded concurrency 1). */
export function schedule(ctx: AppContext, id: string, delayMs = 0) {
  const q = queueOf(ctx);
  q.pending++;
  const run = () => {
    q.chain = q.chain
      .then(async () => {
        const outcome = await verifyOne(ctx, id);
        if (outcome === 'retry') {
          const [row] = await ctx.db.select({ n: recordings.asrAttempts }).from(recordings).where(eq(recordings.id, id));
          const delay = RETRY_DELAYS_MS[(row?.n ?? 1) - 1];
          if (delay !== undefined) schedule(ctx, id, delay);
        }
      })
      .catch((err) => captureError(err, { job: 'recordings.verify' }))
      .finally(() => {
        q.pending--;
      });
  };
  if (delayMs > 0) {
    const t = setTimeout(() => {
      q.timers.delete(t);
      run();
    }, delayMs);
    t.unref?.();
    q.timers.add(t);
  } else {
    run();
  }
}

/** Wait until the in-process queue is idle (tests); delayed retries are cancelled. */
export async function drain(ctx: AppContext): Promise<void> {
  const q = queueOf(ctx);
  for (;;) {
    for (const t of q.timers) {
      clearTimeout(t);
      q.pending--;
    }
    q.timers.clear();
    if (q.pending <= 0) break;
    await q.chain;
  }
  await q.chain;
}

/**
 * One AI check of a `processing` recording. Updates are guarded on `status = 'processing'` so an
 * owner switching back to private meanwhile wins. Returns what happened.
 */
export async function verifyOne(ctx: VerifyCtx, id: string): Promise<'done' | 'retry' | 'skipped'> {
  const [rec] = await ctx.db
    .select({ audio: recordings.audio, surah: recordings.surah, fromAyah: recordings.fromAyah, toAyah: recordings.toAyah, durationMs: recordings.durationMs, status: recordings.status, attempts: recordings.asrAttempts })
    .from(recordings)
    .where(eq(recordings.id, id));
  if (!rec || rec.status !== 'processing') return 'skipped';
  const now = ctx.now();
  const guard = and(eq(recordings.id, id), eq(recordings.status, 'processing'));
  if (!ctx.asr) {
    await ctx.db.update(recordings).set({ status: 'needs_review', queuedAt: null }).where(guard);
    return 'done';
  }
  let res;
  try {
    res = await ctx.asr.verify(rec.audio);
  } catch (err) {
    if (err instanceof AsrUndecodable || err instanceof AsrTooLong) {
      // Definite answers, never retried: undecodable → unclear; longer than the file claimed → too_long.
      await ctx.db
        .update(recordings)
        .set({ status: 'rejected', rejectReason: err instanceof AsrTooLong ? 'too_long' : 'unclear', queuedAt: null, verifiedAt: now, clientScore: null, clientWords: null })
        .where(guard);
      return 'done';
    }
    const attempts = rec.attempts + 1;
    if (attempts >= MAX_ASR_ATTEMPTS) {
      await ctx.db.update(recordings).set({ status: 'needs_review', asrAttempts: attempts, queuedAt: null }).where(guard);
      return 'done';
    }
    await ctx.db.update(recordings).set({ asrAttempts: attempts }).where(guard);
    return 'retry';
  }
  const durationMs = res.durationMs > 0 ? res.durationMs : rec.durationMs;
  if (durationMs > RECORDING_MAX_MS + RECORDING_DURATION_TOLERANCE_MS) {
    await ctx.db
      .update(recordings)
      .set({ status: 'rejected', rejectReason: 'too_long', queuedAt: null, verifiedAt: now, clientScore: null, clientWords: null })
      .where(guard);
    return 'done';
  }
  const m = matchRecitation({ expected: expectedAyat(rec.surah, rec.fromAyah, rec.toAyah), heard: res.words, durationMs, speechMs: res.speechMs });
  const base = { score: m.coverage, speech: m.speech, queuedAt: null };
  if (m.verdict === 'approve') {
    await ctx.db
      .update(recordings)
      .set({ ...base, status: 'approved', rejectReason: null, words: m.words, verifiedAt: now, transcript: null, clientScore: null, clientWords: null })
      .where(guard);
    await ctx.cache.bumpNamespace('profile');
  } else if (m.verdict === 'reject') {
    await ctx.db
      .update(recordings)
      .set({ ...base, status: 'rejected', rejectReason: m.rejectReason, words: null, verifiedAt: now, transcript: null, clientScore: null, clientWords: null })
      .where(guard);
  } else {
    // Kept for the reviewer only while queued: the words (for karaoke if approved) and a transcript snippet.
    await ctx.db
      .update(recordings)
      .set({ ...base, status: 'needs_review', words: m.words, transcript: res.transcript.slice(0, TRANSCRIPT_MAX) })
      .where(guard);
  }
  return 'done';
}

/**
 * Sweeper (step 6 of the hourly community job): retry `processing` recordings stuck longer than 10 min (each
 * failure counts; after 3 → needs_review) within a wall-clock budget (`SWEEP_BUDGET_MS`; the rest wait
 * for the next run); delete recordings removed by a moderator past the 7-day restore window and wipe the
 * text of support-removed comments past it. `verify: false` (the admin «rollover» request) makes no AI
 * calls at all.
 */
export async function sweep(ctx: VerifyCtx, opts: { verify?: boolean; budgetMs?: number } = {}): Promise<{ retried: number; toReview: number; purged: number }> {
  const verify = opts.verify ?? true;
  const deadline = performance.now() + (opts.budgetMs ?? SWEEP_BUDGET_MS);
  const now = ctx.now();
  const stale = await ctx.db.execute<{ id: string; attempts: number }>(sql`
    select id, asr_attempts as attempts from recordings
    where status = 'processing' and (queued_at is null or queued_at < ${new Date(now.getTime() - SWEEP_AFTER_MS)}) order by queued_at limit 50`);
  let retried = 0;
  let toReview = 0;
  for (const r of stale.rows) {
    if (Number(r.attempts) >= MAX_ASR_ATTEMPTS) {
      await ctx.db.update(recordings).set({ status: 'needs_review', queuedAt: null }).where(and(eq(recordings.id, r.id), eq(recordings.status, 'processing')));
      toReview++;
      continue;
    }
    if (!verify || performance.now() >= deadline) continue;
    await ctx.db.update(recordings).set({ queuedAt: now }).where(eq(recordings.id, r.id));
    const out = await verifyOne(ctx, r.id);
    if (out === 'retry') retried++;
    else if (out === 'done') {
      const [s] = await ctx.db.select({ status: recordings.status }).from(recordings).where(eq(recordings.id, r.id));
      if (s?.status === 'needs_review') toReview++;
    }
  }
  const cutoff = new Date(now.getTime() - REMOVED_RETENTION_DAYS * 86_400_000);
  let purged = 0;
  await ctx.db.transaction(async (tx) => {
    const del = await tx.execute<{ id: string }>(sql`select id from recordings where status = 'removed' and removed_at < ${cutoff}`);
    purged = del.rows.length;
    if (purged) await deleteRecordings(tx, sql`r.status = 'removed' and r.removed_at < ${cutoff}`);
    await tx.execute(sql`update recording_comments set text = '' where status = 'removed' and removed_at < ${cutoff} and text <> ''`);
    // Resolved reports are kept 180 days (like community reports), then deleted.
    await tx.execute(sql`delete from recording_reports where resolved_at < ${new Date(now.getTime() - 180 * 86_400_000)}`);
  });
  return { retried, toReview, purged };
}

/* ----------------------------------------------------------------- members */

type VisibleRow = OwnerRow & {
  id: string;
  surah: number;
  from_ayah: number;
  to_ayah: number;
  duration_ms: number;
  visibility: 'members' | 'public';
  comments_on: boolean;
  position: number;
  created_at: Date | string;
  words: RecordingWord[] | null;
};

const VISIBLE_COLUMNS = sql.raw(`r.id, r.surah, r.from_ayah, r.to_ayah, r.duration_ms, r.visibility, r.comments_on, r.position, r.created_at, r.words`);

function toPublic(ctx: AppContext, r: VisibleRow, viewerId: string, extra: { counts: ReactionCounts; mine: ReactionKind | null; comments: number }): PublicRecording {
  return {
    id: r.id,
    surah: Number(r.surah),
    fromAyah: Number(r.from_ayah),
    toAyah: Number(r.to_ayah),
    durationMs: Number(r.duration_ms),
    visibility: r.visibility,
    commentsOn: r.comments_on,
    position: Number(r.position),
    reactions: extra.counts,
    myReaction: extra.mine,
    commentCount: extra.comments,
    createdAt: new Date(r.created_at).toISOString(),
    audioPath: `/v1/recordings/${r.id}/audio`,
    words: r.words ?? null,
    owner: competitor(ctx, r, viewerId),
    mine: r.user_id === viewerId,
  };
}

/** A recording members may hear, or 404 (also when either side blocked the other). */
async function visibleOne(ctx: AppContext, viewerId: string, id: string): Promise<VisibleRow> {
  const r = await ctx.db.execute<VisibleRow>(sql`
    select ${VISIBLE_COLUMNS}, ${OWNER_COLUMNS} from recordings r ${OWNER_JOINS}
    where r.id = ${id} and ${MEMBER_VISIBLE} and ${OWNER_SHAREABLE}`);
  const row = r.rows[0];
  if (!row || (await blockedEitherWay(ctx.db, viewerId, row.user_id))) throw notFound('recording');
  return row;
}

/** GET /v1/community/members/:handle/recordings — any signed-in user (not a guest) may listen. */
export async function memberRecordings(ctx: AppContext, viewerId: string, handle: string): Promise<MemberRecordings> {
  await requireFeature(ctx).catch(() => {
    throw notFound('recordings');
  });
  await requireAccount(ctx.db, viewerId);
  const h = handle.trim().replace(/^@/, '').toLowerCase();
  const owner = await ctx.db.execute<OwnerRow>(sql`
    select ${OWNER_COLUMNS} from users u ${COMPETITOR_JOINS}
    where pp.handle = ${h} and ${OWNER_SHAREABLE}`);
  const o = owner.rows[0];
  if (!o || (await blockedEitherWay(ctx.db, viewerId, o.user_id))) throw notFound('member');
  const rows = await ctx.db.execute<VisibleRow>(sql`
    select ${VISIBLE_COLUMNS}, ${OWNER_COLUMNS} from recordings r ${OWNER_JOINS}
    where r.user_id = ${o.user_id} and ${MEMBER_VISIBLE} order by r.position, r.created_at`);
  const extra = await reactionsFor(
    ctx.db,
    rows.rows.map((r) => r.id),
    viewerId,
  );
  return { owner: competitor(ctx, o, viewerId), items: rows.rows.map((r) => toPublic(ctx, r, viewerId, extra.get(r.id)!)) };
}

export async function memberAudio(ctx: AppContext, viewerId: string, id: string): Promise<Buffer> {
  await requireFeature(ctx).catch(() => {
    throw notFound('recording');
  });
  await requireAccount(ctx.db, viewerId);
  await visibleOne(ctx, viewerId, id);
  const [row] = await ctx.db.select({ audio: recordings.audio }).from(recordings).where(eq(recordings.id, id));
  return row!.audio;
}

/** Viewer gate for reacting, commenting and reporting. */
async function engage(ctx: AppContext, viewerId: string, id: string): Promise<VisibleRow> {
  await requireFeature(ctx);
  requireMember(await identity(ctx.db, viewerId));
  const r = await ctx.db.execute<VisibleRow>(sql`
    select ${VISIBLE_COLUMNS}, ${OWNER_COLUMNS} from recordings r ${OWNER_JOINS}
    where r.id = ${id} and ${MEMBER_VISIBLE} and ${OWNER_SHAREABLE}`);
  const row = r.rows[0];
  if (!row) throw notFound('recording');
  if (await blockedEitherWay(ctx.db, viewerId, row.user_id)) throw forbidden('blocked');
  return row;
}

async function reactionState(ctx: AppContext, id: string, viewerId: string): Promise<ReactionState> {
  const e = (await reactionsFor(ctx.db, [id], viewerId)).get(id)!;
  return { reactions: e.counts, myReaction: e.mine };
}

/** PUT /v1/recordings/:id/reaction — set or change (idempotent). Others react; the owner cannot (`own_recording`). */
export async function setReaction(ctx: AppContext, viewerId: string, id: string, kind: ReactionKind): Promise<ReactionState> {
  const rec = await engage(ctx, viewerId, id);
  if (rec.user_id === viewerId) throw forbidden('own_recording');
  await ctx.db
    .insert(recordingReactions)
    .values({ recordingId: id, userId: viewerId, kind, createdAt: ctx.now() })
    .onConflictDoUpdate({ target: [recordingReactions.recordingId, recordingReactions.userId], set: { kind } });
  await ctx.cache.bumpNamespace('profile');
  return reactionState(ctx, id, viewerId);
}

/** DELETE /v1/recordings/:id/reaction (idempotent). */
export async function clearReaction(ctx: AppContext, viewerId: string, id: string): Promise<ReactionState> {
  await engage(ctx, viewerId, id);
  await ctx.db.delete(recordingReactions).where(and(eq(recordingReactions.recordingId, id), eq(recordingReactions.userId, viewerId)));
  await ctx.cache.bumpNamespace('profile');
  return reactionState(ctx, id, viewerId);
}

type CommentRow = OwnerRow & {
  id: string;
  text: string;
  created_at: Date | string;
};

function encodeCursor(createdAt: Date | string, id: string): string {
  return Buffer.from(`${new Date(createdAt).toISOString()}|${id}`, 'utf8').toString('base64url');
}

function decodeCursor(cursor: string | undefined): { at: Date; id: string } | null {
  if (!cursor) return null;
  const [at, id] = Buffer.from(cursor, 'base64url').toString('utf8').split('|');
  const d = new Date(at ?? '');
  // The canonical UUID shape only: anything else would reach Postgres' ::uuid cast as a 500.
  if (Number.isNaN(d.getTime()) || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id ?? '')) throw badRequest('invalid_cursor');
  return { at: d, id: id! };
}

/**
 * GET /v1/recordings/:id/comments — newest first; comments by blocked users (either way) and by authors
 * who are no longer shareable (left the community, banned, attestation gone, inactive) are left out.
 */
export async function listComments(ctx: AppContext, viewerId: string, id: string, cursor?: string): Promise<RecordingCommentsPage> {
  await requireFeature(ctx).catch(() => {
    throw notFound('recording');
  });
  await requireAccount(ctx.db, viewerId);
  const rec = await visibleOne(ctx, viewerId, id);
  const after = decodeCursor(cursor);
  const rows = await ctx.db.execute<CommentRow>(sql`
    select c.id, c.text, c.created_at, ${OWNER_COLUMNS}
    from recording_comments c join users u on u.id = c.user_id ${COMPETITOR_JOINS}
    where c.recording_id = ${id} and c.status = 'visible' and ${OWNER_SHAREABLE}
      and not exists (select 1 from community_blocks b where (b.user_id = ${viewerId} and b.blocked_user_id = u.id) or (b.user_id = u.id and b.blocked_user_id = ${viewerId}))
      ${after ? sql`and (c.created_at, c.id) < (${after.at}, ${after.id}::uuid)` : sql``}
    order by c.created_at desc, c.id desc limit ${COMMENTS_PAGE_SIZE + 1}`);
  const page = rows.rows.slice(0, COMMENTS_PAGE_SIZE);
  const items: RecordingComment[] = page.map((c) => ({
    id: c.id,
    author: competitor(ctx, c, viewerId),
    text: c.text,
    createdAt: new Date(c.created_at).toISOString(),
    mine: c.user_id === viewerId,
    canDelete: c.user_id === viewerId || rec.user_id === viewerId,
  }));
  const last = page.at(-1);
  return { items, nextCursor: rows.rows.length > COMMENTS_PAGE_SIZE && last ? encodeCursor(last.created_at, last.id) : null, commentsOn: rec.comments_on };
}

/** POST /v1/recordings/:id/comments. */
export async function postComment(ctx: AppContext, viewerId: string, id: string, text: string): Promise<RecordingComment> {
  const rec = await engage(ctx, viewerId, id);
  if (!rec.comments_on) throw forbidden('comments_off');
  const check = checkComment(text);
  if (!check.ok) throw badRequest('comment_rejected', check.problem, { problem: check.problem });
  if (check.mentions.length) {
    const list = sql.join(
      check.mentions.map((m) => sql`${m}`),
      sql`, `,
    );
    const found = await ctx.db.execute<{ handle: string }>(sql`
      select pp.handle from public_profiles pp join users u on u.id = pp.user_id where pp.handle in (${list}) and ${OWNER_SHAREABLE}`);
    if (found.rows.length !== check.mentions.length) throw badRequest('comment_rejected', 'mention', { problem: 'mention' });
  }
  const now = ctx.now();
  // Count and insert under the author's row lock (like `report`): parallel posts cannot all pass the limit.
  const row = await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`select id from users where id = ${viewerId} for update`);
    const counts = await tx.execute<{ minute: number; day: number }>(sql`
      select count(*) filter (where created_at > ${new Date(now.getTime() - 60_000)})::int as minute,
        count(*) filter (where created_at > ${new Date(now.getTime() - 86_400_000)})::int as day
      from recording_comments where user_id = ${viewerId} and created_at > ${new Date(now.getTime() - 86_400_000)}`);
    const c = counts.rows[0]!;
    if (Number(c.minute) >= COMMENT_RATE.perMinute || Number(c.day) >= COMMENT_RATE.perDay) throw tooMany('comment_rate_limited');
    const [inserted] = await tx.insert(recordingComments).values({ recordingId: id, userId: viewerId, text: check.text, createdAt: now }).returning();
    return inserted;
  });
  const me = await ctx.db.execute<OwnerRow>(sql`
    select ${OWNER_COLUMNS} from users u ${COMPETITOR_JOINS} where u.id = ${viewerId}`);
  return { id: row!.id, author: competitor(ctx, me.rows[0]!, viewerId), text: row!.text, createdAt: row!.createdAt.toISOString(), mine: true, canDelete: true };
}

/** DELETE /v1/recordings/:id/comments/:cid — the author or the recording's owner. Text wiped at once. */
export async function deleteComment(ctx: AppContext, viewerId: string, id: string, cid: string): Promise<void> {
  const r = await ctx.db.execute<{ author: string; owner: string }>(sql`
    select c.user_id as author, r.user_id as owner from recording_comments c join recordings r on r.id = c.recording_id
    where c.id = ${cid} and c.recording_id = ${id} and c.status <> 'removed'`);
  const row = r.rows[0];
  if (!row || (row.author !== viewerId && row.owner !== viewerId)) throw notFound('comment');
  await ctx.db.transaction(async (tx) => {
    await tx.update(recordingComments).set({ status: 'removed', text: '', removedAt: ctx.now() }).where(eq(recordingComments.id, cid));
    await tx.execute(sql`delete from recording_reports where target = 'comment' and target_id = ${cid}`);
  });
}

/**
 * POST /v1/recordings/:id/report and /comments/:cid/report. One report per reporter and target
 * (repeat = no-op), 20 per reporter per rolling 24 h. 3 distinct open reports hide a comment or hold a
 * recording out of every view until support decides.
 */
export async function report(ctx: AppContext, viewerId: string, target: 'recording' | 'comment', recordingId: string, commentId: string | null, reason: RecordingReportReason): Promise<void> {
  const rec = await engage(ctx, viewerId, recordingId);
  let targetId = recordingId;
  if (target === 'comment') {
    const [c] = await ctx.db
      .select({ id: recordingComments.id, author: recordingComments.userId, status: recordingComments.status })
      .from(recordingComments)
      .where(and(eq(recordingComments.id, commentId!), eq(recordingComments.recordingId, recordingId)));
    if (!c || c.status === 'removed') throw notFound('comment');
    if (c.author === viewerId) return;
    targetId = c.id;
  } else if (rec.user_id === viewerId) {
    return;
  }
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    await tx.execute(sql`select id from users where id = ${viewerId} for update`);
    const [{ n } = { n: 0 }] = await tx
      .select({ n: sql<number>`count(*)::int` })
      .from(recordingReports)
      .where(and(eq(recordingReports.reporterId, viewerId), sql`${recordingReports.createdAt} > ${new Date(now.getTime() - 86_400_000)}`));
    if (Number(n) >= RECORDING_REPORTS_PER_DAY) throw tooMany('rate_limited');
    await tx.insert(recordingReports).values({ target, targetId, reporterId: viewerId, reason, createdAt: now }).onConflictDoNothing();
    const [{ open } = { open: 0 }] = await tx
      .select({ open: sql<number>`count(distinct ${recordingReports.reporterId})::int` })
      .from(recordingReports)
      .where(and(eq(recordingReports.target, target), eq(recordingReports.targetId, targetId), sql`${recordingReports.resolvedAt} is null`));
    if (Number(open) >= AUTO_HIDE_REPORTS) {
      if (target === 'comment') await tx.update(recordingComments).set({ status: 'hidden' }).where(and(eq(recordingComments.id, targetId), eq(recordingComments.status, 'visible')));
      else await tx.update(recordings).set({ heldAt: now }).where(and(eq(recordings.id, targetId), sql`${recordings.heldAt} is null`));
    }
  });
  if (target === 'recording') await ctx.cache.bumpNamespace('profile');
}

/* --------------------------------------------------------------------- web */

export interface CardRecording {
  id: string;
  surah: number;
  fromAyah: number;
  toAyah: number;
  durationMs: number;
  reactions: ReactionCounts;
  /**
   * Same-origin path of the audio (`/u/<handle>/r/<id>.m4a`), relative like the player script: the
   * page's CSP (media-src 'self') and CORP (same-origin) must allow it on whichever host serves the card.
   */
  audioUrl: string;
  /** Start (ms) of each ayah, `fromAyah`…`toAyah`, from the verified word timings (null: nothing to follow). */
  ayahStarts: number[] | null;
}

/**
 * Public, approved recordings for the owner's web card `/u/<handle>` (published, unmoderated card) —
 * under the same owner gate as the member views (`OWNER_SHAREABLE`): leaving the community, a ban or a
 * withdrawn attestation takes them off the open web too.
 */
export async function forCard(ctx: AppContext, handle: string): Promise<CardRecording[]> {
  // Both switches: «تلاواتي» (`recordings`) and the cards programme (`publicCards`, which 404s `/u/:handle`).
  if (!(await featureOn(ctx)) || !(await cardFeatureOn(ctx, 'publicCards'))) return [];
  const h = handle.trim().toLowerCase();
  const rows = await ctx.db.execute<{ id: string; surah: number; from_ayah: number; to_ayah: number; duration_ms: number; handle: string; words: RecordingWord[] | null }>(sql`
    select r.id, r.surah, r.from_ayah, r.to_ayah, r.duration_ms, pp.handle, r.words from recordings r ${OWNER_JOINS}
    where pp.handle = ${h} and pp.published and pp.moderated_at is null
      and ${MEMBER_VISIBLE} and r.visibility = 'public' and ${OWNER_SHAREABLE}
    order by r.position, r.created_at`);
  const extra = await reactionsFor(
    ctx.db,
    rows.rows.map((r) => r.id),
    null,
  );
  return rows.rows.map((r) => ({
    id: r.id,
    surah: Number(r.surah),
    fromAyah: Number(r.from_ayah),
    toAyah: Number(r.to_ayah),
    durationMs: Number(r.duration_ms),
    reactions: extra.get(r.id)!.counts,
    audioUrl: `/u/${encodeURIComponent(r.handle)}/r/${r.id}.m4a`,
    ayahStarts: ayahStarts(r.words, Number(r.from_ayah), Number(r.to_ayah)),
  }));
}

/** The audio behind `/u/<handle>/r/<id>.m4a`: only while public + approved on a live card (both switches on). */
export async function cardAudio(ctx: AppContext, handle: string, id: string): Promise<Buffer | null> {
  const list = await forCard(ctx, handle);
  if (!list.some((r) => r.id === id)) return null;
  const [row] = await ctx.db.select({ audio: recordings.audio }).from(recordings).where(eq(recordings.id, id));
  return row?.audio ?? null;
}

/* ------------------------------------------------------ export and erasure */

/** PDPL access: the user's recordings (metadata + audio as base64), reactions, comments and reports they made. */
export async function exportFor(ctx: AppContext, uid: string) {
  const recs = await ctx.db
    .select({
      id: recordings.id,
      surah: recordings.surah,
      fromAyah: recordings.fromAyah,
      toAyah: recordings.toAyah,
      durationMs: recordings.durationMs,
      status: recordings.status,
      rejectReason: recordings.rejectReason,
      visibility: recordings.visibility,
      commentsOn: recordings.commentsOn,
      position: recordings.position,
      createdAt: recordings.createdAt,
      verifiedAt: recordings.verifiedAt,
      audio: recordings.audio,
    })
    .from(recordings)
    .where(eq(recordings.userId, uid));
  return {
    recordings: recs.map(({ audio, ...r }) => ({ ...r, audioFormat: 'audio/mp4 (AAC-LC .m4a)', audioBase64: audio.toString('base64') })),
    reactions: await ctx.db
      .select({ recordingId: recordingReactions.recordingId, kind: recordingReactions.kind, createdAt: recordingReactions.createdAt })
      .from(recordingReactions)
      .where(eq(recordingReactions.userId, uid)),
    comments: await ctx.db
      .select({ recordingId: recordingComments.recordingId, text: recordingComments.text, status: recordingComments.status, createdAt: recordingComments.createdAt })
      .from(recordingComments)
      .where(eq(recordingComments.userId, uid)),
    reports: await ctx.db
      .select({ target: recordingReports.target, targetId: recordingReports.targetId, reason: recordingReports.reason, createdAt: recordingReports.createdAt })
      .from(recordingReports)
      .where(eq(recordingReports.reporterId, uid)),
  };
}

/** Erasure: every recording (audio, reactions, comments on it), every reaction, comment and report by the user. */
export async function eraseAll(tx: DbOrTx, uid: string): Promise<void> {
  await deleteRecordings(tx, sql`r.user_id = ${uid}`);
  await tx.execute(sql`
    delete from recording_reports rp using recording_comments c where rp.target = 'comment' and rp.target_id = c.id and c.user_id = ${uid}`);
  await tx.delete(recordingComments).where(eq(recordingComments.userId, uid));
  await tx.delete(recordingReactions).where(eq(recordingReactions.userId, uid));
  await tx.delete(recordingReports).where(eq(recordingReports.reporterId, uid));
  await tx.delete(recordingDaily).where(eq(recordingDaily.userId, uid));
}

/* ------------------------------------------------------------------- admin */

/** What sits in the queue (alias r): flagged by the AI check, held or reported, or removed within 7 days. */
function inQueue(now: Date) {
  return sql`(r.status = 'needs_review' and r.visibility <> 'private')
    or (r.status = 'approved' and (r.held_at is not null or exists (select 1 from recording_reports rp where rp.target = 'recording' and rp.target_id = r.id and rp.resolved_at is null)))
    or (r.status = 'removed' and r.removed_at > ${new Date(now.getTime() - REMOVED_RETENTION_DAYS * 86_400_000)})`;
}

export async function adminQueue(ctx: AppContext): Promise<AdminRecordingQueue> {
  const now = ctx.now();
  const recs = await ctx.db.execute<{
    id: string;
    surah: number;
    from_ayah: number;
    to_ayah: number;
    duration_ms: number;
    status: RecordingStatus;
    visibility: AdminRecordingItem['visibility'];
    held_at: Date | null;
    score: number | null;
    speech: number | null;
    transcript: string | null;
    client_score: number | null;
    created_at: Date | string;
    handle: string | null;
    reports: number;
    reasons: RecordingReportReason[] | null;
  }>(sql`
    select r.id, r.surah, r.from_ayah, r.to_ayah, r.duration_ms, r.status, r.visibility, r.held_at, r.score, r.speech, r.transcript, r.client_score, r.created_at,
      (select handle from public_profiles pp where pp.user_id = r.user_id) as handle,
      (select count(*)::int from recording_reports rp where rp.target = 'recording' and rp.target_id = r.id and rp.resolved_at is null) as reports,
      (select array_agg(distinct rp.reason) from recording_reports rp where rp.target = 'recording' and rp.target_id = r.id and rp.resolved_at is null) as reasons
    from recordings r where ${inQueue(now)} order by r.created_at limit 200`);
  const comments = await ctx.db.execute<{
    id: string;
    recording_id: string;
    surah: number;
    from_ayah: number;
    to_ayah: number;
    text: string;
    status: AdminCommentItem['status'];
    created_at: Date | string;
    handle: string | null;
    reports: number;
    reasons: RecordingReportReason[] | null;
  }>(sql`
    select c.id, c.recording_id, r.surah, r.from_ayah, r.to_ayah, c.text, c.status, c.created_at,
      (select handle from public_profiles pp where pp.user_id = c.user_id) as handle,
      (select count(*)::int from recording_reports rp where rp.target = 'comment' and rp.target_id = c.id and rp.resolved_at is null) as reports,
      (select array_agg(distinct rp.reason) from recording_reports rp where rp.target = 'comment' and rp.target_id = c.id and rp.resolved_at is null) as reasons
    from recording_comments c join recordings r on r.id = c.recording_id
    where c.status = 'hidden'
      or (c.status = 'visible' and exists (select 1 from recording_reports rp where rp.target = 'comment' and rp.target_id = c.id and rp.resolved_at is null))
      or (c.status = 'removed' and c.removed_at > ${new Date(now.getTime() - REMOVED_RETENTION_DAYS * 86_400_000)} and c.text <> '')
    order by c.created_at limit 200`);
  return {
    recordings: recs.rows.map((r) => ({
      kind: 'recording' as const,
      id: r.id,
      surah: Number(r.surah),
      fromAyah: Number(r.from_ayah),
      toAyah: Number(r.to_ayah),
      durationMs: Number(r.duration_ms),
      status: r.status,
      visibility: r.visibility,
      flagged: r.status === 'needs_review',
      held: r.held_at !== null,
      score: r.score === null ? null : Number(r.score),
      speech: r.speech === null ? null : Number(r.speech),
      transcript: r.transcript,
      clientScore: r.client_score === null ? null : Number(r.client_score),
      reports: Number(r.reports),
      reasons: r.reasons ?? [],
      createdAt: new Date(r.created_at).toISOString(),
      audioPath: `/admin/recordings/${r.id}/audio`,
      ownerHandle: r.handle,
    })),
    comments: comments.rows.map((c) => ({
      kind: 'comment' as const,
      id: c.id,
      recordingId: c.recording_id,
      surah: Number(c.surah),
      fromAyah: Number(c.from_ayah),
      toAyah: Number(c.to_ayah),
      text: c.text,
      status: c.status,
      reports: Number(c.reports),
      reasons: c.reasons ?? [],
      createdAt: new Date(c.created_at).toISOString(),
      authorHandle: c.handle,
    })),
  };
}

/** Audio for a reviewer: only while the recording is in the queue. */
export async function adminAudio(ctx: AppContext, id: string): Promise<Buffer> {
  const r = await ctx.db.execute<{ audio: Buffer }>(sql`select r.audio from recordings r where r.id = ${id} and (${inQueue(ctx.now())})`);
  if (!r.rows[0]) throw notFound('recording');
  return r.rows[0].audio;
}

/** Which role decides which action (super_admin always may). */
export const DECISION_ROLES: Record<AdminRecordingDecision['action'], 'religious_reviewer' | 'support'> = {
  approve: 'religious_reviewer',
  reject: 'religious_reviewer',
  dismiss: 'support',
  remove: 'support',
  restore: 'support',
};

async function resolveReports(tx: DbOrTx, target: 'recording' | 'comment', id: string, adminId: string, resolution: 'dismissed' | 'actioned', now: Date) {
  await tx
    .update(recordingReports)
    .set({ resolvedAt: now, resolvedBy: adminId, resolution })
    .where(and(eq(recordingReports.target, target), eq(recordingReports.targetId, id), sql`${recordingReports.resolvedAt} is null`));
}

/** POST /admin/recordings/:id/decision — audited in the same transaction. */
export async function decideRecording(ctx: AppContext, req: FastifyRequest, adminId: string, id: string, d: AdminRecordingDecision): Promise<void> {
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    const r = await tx.execute<{ status: RecordingStatus; visibility: string; held_at: Date | null; verified_at: Date | null; in_queue: boolean }>(sql`
      select r.status, r.visibility, r.held_at, r.verified_at, (${inQueue(now)}) as in_queue from recordings r where r.id = ${id} for update`);
    const before = r.rows[0];
    if (!before || !before.in_queue) throw notFound('recording');
    let set: Partial<typeof recordings.$inferInsert>;
    switch (d.action) {
      case 'approve':
        if (before.status !== 'needs_review') throw conflict('not_in_review');
        set = { status: 'approved', rejectReason: null, verifiedAt: now, transcript: null, clientScore: null, clientWords: null };
        break;
      case 'reject':
        if (before.status !== 'needs_review') throw conflict('not_in_review');
        set = { status: 'rejected', rejectReason: d.rejectReason!, words: null, verifiedAt: now, transcript: null, clientScore: null, clientWords: null };
        break;
      case 'dismiss':
        if (before.status !== 'approved') throw conflict('nothing_to_dismiss');
        set = { heldAt: null };
        await resolveReports(tx, 'recording', id, adminId, 'dismissed', now);
        break;
      case 'remove':
        if (before.status === 'removed') throw conflict('already_removed');
        set = { status: 'removed', rejectReason: 'removed_by_moderator', removedAt: now, heldAt: null, transcript: null, clientScore: null, clientWords: null };
        await resolveReports(tx, 'recording', id, adminId, 'actioned', now);
        break;
      case 'restore':
        if (before.status !== 'removed') throw conflict('nothing_to_restore');
        set = { status: before.verified_at ? 'approved' : 'needs_review', rejectReason: null, removedAt: null };
        break;
    }
    await tx.update(recordings).set(set).where(eq(recordings.id, id));
    await audit(tx, req, {
      action: `recording.${d.action}`,
      targetType: 'recording',
      targetId: id,
      reason: d.reason,
      before: { status: before.status, visibility: before.visibility, held: before.held_at !== null },
      after: { status: set.status ?? before.status, held: set.heldAt === undefined ? before.held_at !== null : set.heldAt !== null, rejectReason: set.rejectReason ?? null },
    });
  });
  await ctx.cache.bumpNamespace('profile');
}

/** POST /admin/recordings/comments/:id/decision (support) — audited in the same transaction. */
export async function decideComment(ctx: AppContext, req: FastifyRequest, adminId: string, id: string, d: AdminCommentDecision): Promise<void> {
  const now = ctx.now();
  await ctx.db.transaction(async (tx) => {
    const [before] = await tx
      .select({ status: recordingComments.status, removedAt: recordingComments.removedAt, text: recordingComments.text })
      .from(recordingComments)
      .where(eq(recordingComments.id, id))
      .for('update');
    if (!before) throw notFound('comment');
    let status: 'visible' | 'hidden' | 'removed';
    if (d.action === 'remove') {
      if (before.status === 'removed') throw conflict('already_removed');
      status = 'removed';
      await tx.update(recordingComments).set({ status, removedAt: now }).where(eq(recordingComments.id, id));
      await resolveReports(tx, 'comment', id, adminId, 'actioned', now);
    } else if (d.action === 'restore') {
      const fresh = before.removedAt && now.getTime() - before.removedAt.getTime() < REMOVED_RETENTION_DAYS * 86_400_000 && before.text !== '';
      if (before.status === 'visible' || (before.status === 'removed' && !fresh)) throw conflict('nothing_to_restore');
      status = 'visible';
      await tx.update(recordingComments).set({ status, removedAt: null }).where(eq(recordingComments.id, id));
      await resolveReports(tx, 'comment', id, adminId, 'dismissed', now);
    } else {
      if (before.status === 'removed') throw conflict('nothing_to_dismiss');
      status = 'visible';
      await tx.update(recordingComments).set({ status }).where(eq(recordingComments.id, id));
      await resolveReports(tx, 'comment', id, adminId, 'dismissed', now);
    }
    await audit(tx, req, { action: `recording_comment.${d.action}`, targetType: 'recording_comment', targetId: id, reason: d.reason, before: { status: before.status }, after: { status } });
  });
}
