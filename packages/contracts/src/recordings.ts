import { z } from 'zod';
import { PublicCompetitor } from './community.js';
import { SURAH_NAMES } from './surahs.js';

/**
 * «تلاواتي» — users' own recorded recitations on their profile (design doc §16, APP_SPEC §5.24 / §5.26
 * / §5.31). A recording is the owner's **own voice** reciting verses they chose (surah + ayah range):
 * user-generated content, not Yaqeen's religious content (CLAUDE.md rules 4 and 9 govern what Yaqeen
 * publishes; they are unaffected). Never sent to an ad or analytics platform (rule 1). Admins see a
 * recording only while it sits in the moderation queue (flagged by the AI check or reported), never a
 * user's list (rule 2 spirit).
 *
 * Refined schemas are never `.partial()`-ed or `.extend()`-ed: each has a `…Base` object and a refined export.
 */

/* ------------------------------------------------------------------ limits */

/** Longest recording, in milliseconds. The app stops recording here; the server reads the real duration from the file. */
export const RECORDING_MAX_MS = 30_000;
/** AAC priming/padding: a file may report up to this much over `RECORDING_MAX_MS` and still pass. */
export const RECORDING_DURATION_TOLERANCE_MS = 250;
/** Largest upload (a 30 s clip at the format below is ≈ 120 KB). */
export const RECORDING_MAX_BYTES = 200_000;
/**
 * The one format the app records and the API accepts: AAC-LC in an MPEG-4 audio container (.m4a),
 * mono, 16 kHz, ≈ 32 kbps CBR. The server checks the container (`ftyp`), the `mp4a` sample entry
 * (channels, sample rate) and the track duration; nothing is transcoded, the bytes are stored as uploaded.
 */
export const RECORDING_FORMAT = {
  container: 'm4a',
  codec: 'aac-lc',
  channels: 1,
  sampleRate: 16_000,
  bitrate: 32_000,
  /** The multipart `audio` part's content type; the first is canonical (served back with it). */
  mimes: ['audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac'],
} as const;
/** Recordings on one profile. */
export const PROFILE_RECORDINGS_MAX = 3;
/** Uploads plus share-verifications per user per Africa/Cairo day (the AI check costs CPU). */
export const RECORDING_UPLOADS_PER_DAY = 10;

/* ---------------------------------------------------------------- statuses */

/**
 * `private_ready` — private, never sent to the AI check, owner-only playback.
 * `processing` — shared (members/public) and waiting for the AI check.
 * `approved` — the AI check (or a reviewer) confirmed the chosen verses; stays approved when switched back to private.
 * `needs_review` — borderline: waiting for a `religious_reviewer`.
 * `rejected` — not shareable (`rejectReason`); the owner can still play or delete it.
 * `removed` — a moderator removed it after reports (`removed_by_moderator`).
 */
export const RECORDING_STATUSES = ['processing', 'private_ready', 'approved', 'needs_review', 'rejected', 'removed'] as const;
export const RecordingStatus = z.enum(RECORDING_STATUSES);
export type RecordingStatus = z.infer<typeof RecordingStatus>;

export const REJECT_REASONS = ['not_matching', 'unclear', 'silence', 'too_long', 'removed_by_moderator'] as const;
export const RejectReason = z.enum(REJECT_REASONS);
export type RejectReason = z.infer<typeof RejectReason>;

/** `public` = members + the owner's web card `/u/<handle>`. Default `private`. */
export const RECORDING_VISIBILITIES = ['private', 'members', 'public'] as const;
export const RecordingVisibility = z.enum(RECORDING_VISIBILITIES);
export type RecordingVisibility = z.infer<typeof RecordingVisibility>;

/* --------------------------------------------------------------- reactions */

/** One reaction per viewer per recording, changeable and removable. */
export const REACTION_KINDS = ['mashallah', 'barakallah', 'ahsant'] as const;
export const ReactionKind = z.enum(REACTION_KINDS);
export type ReactionKind = z.infer<typeof ReactionKind>;
/** Fixed copy (the app has the same strings in its ARB files). */
export const REACTION_COPY: Record<ReactionKind, { ar: string; en: string }> = {
  mashallah: { ar: 'ما شاء الله', en: "Masha'Allah" },
  barakallah: { ar: 'بارك الله فيك', en: 'Barak Allahu feek' },
  ahsant: { ar: 'أحسنت', en: 'Well done' },
};

export const ReactionCounts = z.object({
  mashallah: z.number().int().min(0),
  barakallah: z.number().int().min(0),
  ahsant: z.number().int().min(0),
});
export type ReactionCounts = z.infer<typeof ReactionCounts>;

/* ---------------------------------------------------------------- comments */

export const COMMENT_MAX = 280;
export const COMMENT_MIN = 2;
/** Per author; rejected comments don't count. */
export const COMMENT_RATE = { perMinute: 5, perDay: 50 } as const;
/** Distinct reporters that auto-hide a comment (or hold a recording) pending a moderator. */
export const AUTO_HIDE_REPORTS = 3;
/** Reports one user may file per rolling 24 h (recordings and comments together). */
export const RECORDING_REPORTS_PER_DAY = 20;
export const COMMENTS_PAGE_SIZE = 20;

/* ------------------------------------------------------- recitation match */

/**
 * The AI check's verdict (pure domain `services/api/src/domain/recitation-match.ts`; the rules and
 * test vectors are shared with the app in `packages/contracts/fixtures/recitation-match/`).
 *
 * `coverage` = expected words marked `ok`, in order, ÷ expected words. `speech` = speech ÷ duration (VAD).
 * `extraRatio` = heard words aligned to no expected word ÷ heard words.
 * Order: `speech < silenceSpeech` → reject `silence`; no words heard → reject `unclear`;
 * `coverage < rejectCoverage` → reject `not_matching`; `coverage ≥ approveCoverage` and
 * `speech ≥ approveSpeech` and `extraRatio ≤ maxExtraRatio` → approve; anything else → `needs_review`.
 */
export const RECITATION_MATCH = {
  approveCoverage: 0.75,
  approveSpeech: 0.4,
  silenceSpeech: 0.15,
  rejectCoverage: 0.35,
  maxExtraRatio: 0.5,
  /** Words of at least this many letters match at one edit (recogniser slips). */
  fuzzyMinLetters: 4,
} as const;

export const MatchVerdict = z.enum(['approve', 'needs_review', 'reject']);
export type MatchVerdict = z.infer<typeof MatchVerdict>;

/** A verified word for karaoke playback: `index` counts the ayah's words as the app splits them (ayah-end marks excluded). */
export const RecordingWord = z.object({
  ayah: z.number().int().min(1).max(286),
  index: z.number().int().min(0),
  startMs: z.number().int().min(0),
  endMs: z.number().int().min(0),
});
export type RecordingWord = z.infer<typeof RecordingWord>;

/* -------------------------------------------------------------- recordings */

/** The caller's own recording (`GET /v1/me/recordings`). */
export const Recording = z.object({
  id: z.string().uuid(),
  surah: z.number().int().min(1).max(114),
  fromAyah: z.number().int().min(1),
  toAyah: z.number().int().min(1),
  durationMs: z.number().int().min(0),
  status: RecordingStatus,
  rejectReason: RejectReason.nullable(),
  visibility: RecordingVisibility,
  commentsOn: z.boolean(),
  /** 1..PROFILE_RECORDINGS_MAX, the order on the profile. */
  position: z.number().int().min(1),
  reactions: ReactionCounts,
  myReaction: ReactionKind.nullable(),
  commentCount: z.number().int().min(0),
  createdAt: z.string(),
  /** Authed API path (`ApiClient.getBytes`): '/v1/me/recordings/<id>/audio'. */
  audioPath: z.string(),
  /** Null until the AI check verified the recording. */
  words: z.array(RecordingWord).nullable(),
});
export type Recording = z.infer<typeof Recording>;

export const MyRecordings = z.object({
  items: z.array(Recording).max(PROFILE_RECORDINGS_MAX),
  /** Uploads/verifications left today (`RECORDING_UPLOADS_PER_DAY`). */
  leftToday: z.number().int().min(0),
});
export type MyRecordings = z.infer<typeof MyRecordings>;

/** A shared, approved recording as members see it. */
export const PublicRecording = z.object({
  id: z.string().uuid(),
  surah: z.number().int().min(1).max(114),
  fromAyah: z.number().int().min(1),
  toAyah: z.number().int().min(1),
  durationMs: z.number().int().min(0),
  visibility: z.enum(['members', 'public']),
  commentsOn: z.boolean(),
  position: z.number().int().min(1),
  reactions: ReactionCounts,
  myReaction: ReactionKind.nullable(),
  commentCount: z.number().int().min(0),
  createdAt: z.string(),
  /** Authed API path: '/v1/recordings/<id>/audio'. */
  audioPath: z.string(),
  words: z.array(RecordingWord).nullable(),
  /** The community's public competitor shape (`points`/`rank` null). */
  owner: PublicCompetitor,
  mine: z.boolean(),
});
export type PublicRecording = z.infer<typeof PublicRecording>;

/** `GET /v1/community/members/:handle/recordings`. */
export const MemberRecordings = z.object({ owner: PublicCompetitor, items: z.array(PublicRecording).max(PROFILE_RECORDINGS_MAX) });
export type MemberRecordings = z.infer<typeof MemberRecordings>;

const ClientWords = z.array(RecordingWord).max(400);

/**
 * `POST /v1/me/recordings` multipart: part `meta` (this JSON) + part `audio` (the .m4a). `durationMs` is
 * the app's measurement (the server trusts the file's own duration). `clientScore`/`clientWords` are the
 * on-device pre-check, kept only while the recording waits in the review queue and never used to approve.
 */
export const RecordingMetaBase = z.object({
  surah: z.number().int().min(1).max(114),
  fromAyah: z.number().int().min(1),
  toAyah: z.number().int().min(1),
  durationMs: z.number().int().min(1).max(RECORDING_MAX_MS + RECORDING_DURATION_TOLERANCE_MS),
  visibility: RecordingVisibility.default('private'),
  commentsOn: z.boolean().default(true),
  clientScore: z.number().min(0).max(1).optional(),
  clientWords: ClientWords.optional(),
});
export const RecordingMeta = RecordingMetaBase.refine((m) => m.fromAyah <= m.toAyah, { message: 'recording_invalid_range' });
export type RecordingMeta = z.infer<typeof RecordingMeta>;

/** `PATCH /v1/me/recordings/:id`. Switching to members/public starts the AI check (unless already approved). */
export const RecordingPatchBase = z.object({
  visibility: RecordingVisibility.optional(),
  commentsOn: z.boolean().optional(),
  position: z.number().int().min(1).max(PROFILE_RECORDINGS_MAX).optional(),
});
export const RecordingPatch = RecordingPatchBase.refine((p) => p.visibility !== undefined || p.commentsOn !== undefined || p.position !== undefined, {
  message: 'empty_patch',
});
export type RecordingPatch = z.infer<typeof RecordingPatch>;

/** `PUT /v1/recordings/:id/reaction`. Returns the new counts. */
export const SetReaction = z.object({ kind: ReactionKind });
export type SetReaction = z.infer<typeof SetReaction>;
export const ReactionState = z.object({ reactions: ReactionCounts, myReaction: ReactionKind.nullable() });
export type ReactionState = z.infer<typeof ReactionState>;

export const RecordingComment = z.object({
  id: z.string().uuid(),
  author: PublicCompetitor,
  text: z.string(),
  createdAt: z.string(),
  mine: z.boolean(),
  /** The author or the recording's owner. */
  canDelete: z.boolean(),
});
export type RecordingComment = z.infer<typeof RecordingComment>;

/** `GET /v1/recordings/:id/comments?cursor=` — newest first. */
export const RecordingCommentsPage = z.object({
  items: z.array(RecordingComment),
  nextCursor: z.string().nullable(),
  commentsOn: z.boolean(),
});
export type RecordingCommentsPage = z.infer<typeof RecordingCommentsPage>;

export const PostComment = z.object({ text: z.string().trim().min(1).max(COMMENT_MAX) });
export type PostComment = z.infer<typeof PostComment>;

export const RECORDING_REPORT_REASONS = ['not_recitation', 'inappropriate', 'spam', 'other'] as const;
export const RecordingReportReason = z.enum(RECORDING_REPORT_REASONS);
export type RecordingReportReason = z.infer<typeof RecordingReportReason>;
export const RecordingReportRequest = z.object({ reason: RecordingReportReason });
export type RecordingReportRequest = z.infer<typeof RecordingReportRequest>;

/** Stable error codes of the recordings endpoints (the Dart failure enum has one value per code). */
export const RECORDING_ERROR_CODES = [
  'recording_too_long',
  'recording_too_large',
  'recording_bad_format',
  'recording_invalid_range',
  'recordings_limit',
  'recording_daily_limit',
  'recording_not_public',
  'attestation_required',
  'community_required',
  'community_banned',
  'account_required',
  'comments_off',
  'comment_rejected',
  'comment_rate_limited',
  'blocked',
  'rate_limited',
  'feature_off',
  'not_found',
] as const;
export type RecordingErrorCode = (typeof RECORDING_ERROR_CODES)[number];

/** «سورة الفاتحة · الآيات 1–4» / "Al-Fatihah · Ayat 1–4" (Western digits; one ayah: «الآية 5» / "Ayah 5"). */
export function verseRef(surah: number, fromAyah: number, toAyah: number, lang: 'ar' | 'en'): string {
  const name = SURAH_NAMES[surah - 1];
  if (!name) return '';
  const range = fromAyah === toAyah ? String(fromAyah) : `${fromAyah}–${toAyah}`;
  if (lang === 'ar') return `سورة ${name[0]} · ${fromAyah === toAyah ? 'الآية' : 'الآيات'} ${range}`;
  return `${name[1]} · ${fromAyah === toAyah ? 'Ayah' : 'Ayat'} ${range}`;
}

/* --------------------------------------------------------------------- ASR */

/** `POST /verify` on the internal ASR service (`services/asr`), header `X-ASR-Token`. */
export const AsrWord = z.object({ text: z.string(), startMs: z.number().int().min(0), endMs: z.number().int().min(0) });
export type AsrWord = z.infer<typeof AsrWord>;
export const AsrVerifyResponse = z.object({
  durationMs: z.number().int().min(0),
  speechMs: z.number().int().min(0),
  transcript: z.string(),
  words: z.array(AsrWord),
});
export type AsrVerifyResponse = z.infer<typeof AsrVerifyResponse>;

/* ------------------------------------------------------------------- admin */

/** Admin «التلاوات»: only what sits in the queue — never a user's list. */
export const AdminRecordingItem = z.object({
  kind: z.literal('recording'),
  id: z.string().uuid(),
  surah: z.number().int(),
  fromAyah: z.number().int(),
  toAyah: z.number().int(),
  durationMs: z.number().int(),
  status: RecordingStatus,
  visibility: RecordingVisibility,
  /** Why it is here: the AI check flagged it, members reported it, or both. */
  flagged: z.boolean(),
  held: z.boolean(),
  score: z.number().nullable(),
  speech: z.number().nullable(),
  /** Kept only while in the queue, then dropped. */
  transcript: z.string().nullable(),
  clientScore: z.number().nullable(),
  reports: z.number().int(),
  reasons: z.array(RecordingReportReason),
  createdAt: z.string(),
  /** Admin API path, proxied by the dashboard. */
  audioPath: z.string(),
  ownerHandle: z.string().nullable(),
});
export type AdminRecordingItem = z.infer<typeof AdminRecordingItem>;

export const AdminCommentItem = z.object({
  kind: z.literal('comment'),
  id: z.string().uuid(),
  recordingId: z.string().uuid(),
  surah: z.number().int(),
  fromAyah: z.number().int(),
  toAyah: z.number().int(),
  text: z.string(),
  status: z.enum(['visible', 'hidden', 'removed']),
  reports: z.number().int(),
  reasons: z.array(RecordingReportReason),
  createdAt: z.string(),
  authorHandle: z.string().nullable(),
});
export type AdminCommentItem = z.infer<typeof AdminCommentItem>;

export const AdminRecordingQueue = z.object({
  recordings: z.array(AdminRecordingItem),
  comments: z.array(AdminCommentItem),
});
export type AdminRecordingQueue = z.infer<typeof AdminRecordingQueue>;

const AdminNote = z.string().trim().min(3).max(500);

/**
 * `POST /admin/recordings/:id/decision`. `approve` / `reject` (verification, `religious_reviewer`);
 * `dismiss` (reports unfounded: lift the hold), `remove`, `restore` (support).
 */
export const AdminRecordingDecisionBase = z.object({
  action: z.enum(['approve', 'reject', 'dismiss', 'remove', 'restore']),
  rejectReason: z.enum(['not_matching', 'unclear', 'silence', 'too_long']).optional(),
  reason: AdminNote,
});
export const AdminRecordingDecision = AdminRecordingDecisionBase.refine((d) => d.action !== 'reject' || d.rejectReason !== undefined, {
  message: 'reject_reason_required',
});
export type AdminRecordingDecision = z.infer<typeof AdminRecordingDecision>;

/** `POST /admin/recordings/comments/:id/decision` (support). */
export const AdminCommentDecision = z.object({ action: z.enum(['remove', 'restore', 'dismiss']), reason: AdminNote });
export type AdminCommentDecision = z.infer<typeof AdminCommentDecision>;
