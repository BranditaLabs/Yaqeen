import { z } from 'zod';
import type { LevelInfo } from './profile.js';

/**
 * Profile identity (avatar, name) and the opt-in community: weekly leagues, seasonal tournaments and
 * the level leaderboard (docs/design/2026-11-profile-community-quran.md §3.1, APP_SPEC §5.31).
 *
 * Privacy (CLAUDE.md non-negotiables 1–3): other users and admins see only the name/@handle, the
 * avatar (a photo only after the 18+ attestation), the level ring from the nightly public snapshot
 * and the period's points from the nightly snapshot. Never worship detail, never anything live.
 * Competitions never write the points ledger; rewards are badges only.
 *
 * Refined schemas are never `.partial()`-ed or `.extend()`-ed: each has a `…Base` object and a
 * refined export.
 */

/* ------------------------------------------------------------------ avatar */

/** Bundled preset avatars (packages/brand/avatars/avatars.json; Dart `kAvatarPresets`). */
export const AVATAR_PRESETS = ['m01', 'm02', 'm03', 'm04', 'm05', 'm06', 'm07', 'm08', 'f01', 'f02', 'f03', 'f04', 'f05', 'f06', 'f07', 'f08'] as const;
export const AvatarPresetId = z.enum(AVATAR_PRESETS);
export type AvatarPresetId = z.infer<typeof AvatarPresetId>;

export const AVATAR_KINDS = ['initial', 'preset', 'photo'] as const;

/**
 * `url`/`smallUrl`: absolute public URLs in public projections; in `MeProfile` (caller only) they are
 * the authed API paths '/v1/me/avatar/photo/256' and '/v1/me/avatar/photo/96', loaded with
 * `ApiClient.getBytes`.
 */
export const Avatar = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('initial') }),
  z.object({ kind: z.literal('preset'), id: AvatarPresetId }),
  z.object({ kind: z.literal('photo'), id: z.string().uuid(), url: z.string().min(1), smallUrl: z.string().min(1) }),
]);
export type Avatar = z.infer<typeof Avatar>;

/** What PATCH /v1/me/profile may set; photos go through PUT /v1/me/avatar/photo. */
export const SetAvatar = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('initial') }),
  z.object({ kind: z.literal('preset'), id: AvatarPresetId }),
]);
export type SetAvatar = z.infer<typeof SetAvatar>;

export const AVATAR_PHOTO = {
  maxBytes: 3 * 1024 * 1024,
  mimes: ['image/jpeg', 'image/png', 'image/webp'],
  sizes: [96, 256],
  minPx: 128,
  clientMaxPx: 1024,
  perHour: 10,
} as const;

/** The caller's own photo (authed; active only). */
export const OWN_AVATAR_PATHS = { large: '/v1/me/avatar/photo/256', small: '/v1/me/avatar/photo/96' } as const;

/* -------------------------------------------------------------------- name */

export const DISPLAY_NAME_MAX = 40;
/** URLs, control characters, bidi controls (U+200E–U+200F, U+202A–U+202E, U+2066–U+2069) and zero-width characters (U+200B–U+200D, U+FEFF). */
// eslint-disable-next-line no-control-regex
const NAME_FORBIDDEN = /https?:|www\.|[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ufeff]/i;
export const DisplayName = z
  .string()
  .trim()
  .min(1)
  .max(DISPLAY_NAME_MAX)
  .refine((s) => !NAME_FORBIDDEN.test(s), 'invalid_name');

/* ------------------------------------------------------------------ points */

/** Ledger reasons that count as points earned in a period (league week, tournament window). */
export const EARNED_REASONS = ['task', 'qada', 'bonus', 'milestone'] as const;
/** Ledger reasons that count toward the level (`delta > 0` only; reversals never raise a level). */
export const LEVEL_REASONS = ['task', 'qada', 'bonus', 'milestone', 'grant', 'admin_adjustment'] as const;

/* ---------------------------------------------------------------- leagues */

/** Monochrome tiers — the division named «ذهب» never gets gold styling. */
export const DIVISIONS = [
  { id: 1, key: 'bronze', ar: 'برونز', en: 'Bronze' },
  { id: 2, key: 'silver', ar: 'فضة', en: 'Silver' },
  { id: 3, key: 'gold', ar: 'ذهب', en: 'Gold' },
  { id: 4, key: 'emerald', ar: 'زمرّد', en: 'Emerald' },
  { id: 5, key: 'ruby', ar: 'ياقوت', en: 'Ruby' },
  { id: 6, key: 'diamond', ar: 'ألماس', en: 'Diamond' },
] as const;
export const DivisionId = z.number().int().min(1).max(6);

/** Saturday 00:00 to Saturday 00:00, Africa/Cairo (DST-safe). */
export const LEAGUE_WEEK = { startsOnWeekday: 6 /* Saturday */, timezone: 'Africa/Cairo' } as const;
/** A country board exists only with at least this many participants (equals `K_ANONYMITY`). */
export const K_COUNTRY_BOARD = 20;

export const LeagueSettingsBase = z.object({
  groupSize: z.number().int().min(10).max(50).default(30),
  promote: z.number().int().min(1).max(10).default(5),
  demote: z.number().int().min(0).max(10).default(5),
  divisionNames: z
    .array(z.object({ ar: z.string().trim().min(1).max(24), en: z.string().trim().min(1).max(24) }))
    .length(6)
    .optional(),
});
/** `app_config 'leagues'`; applies from the next week to start (each week keeps the settings it started with). */
export const LeagueSettings = LeagueSettingsBase.refine((s) => s.promote + s.demote < s.groupSize, { message: 'settings_invalid' });
export type LeagueSettings = z.infer<typeof LeagueSettings>;

/* ------------------------------------------------------------------ badges */

export const BADGE_KINDS = [
  'streak',
  'level',
  'league_first',
  'league_top3',
  'league_promoted',
  'division_reached',
  'tournament_podium',
  'tournament_top10',
  'tournament_finisher',
] as const;
export const BadgeKind = z.enum(BADGE_KINDS);
export type BadgeKind = z.infer<typeof BadgeKind>;

export const Badge = z.object({
  kind: BadgeKind,
  refKey: z.string(),
  awardedAt: z.string(),
  meta: z
    .object({
      days: z.number().int().optional(),
      level: z.number().int().optional(),
      division: DivisionId.optional(),
      rank: z.number().int().optional(),
      size: z.number().int().optional(),
      startsOn: z.string().optional(),
      tournamentId: z.string().uuid().optional(),
      titleAr: z.string().optional(),
      titleEn: z.string().optional(),
      labelAr: z.string().optional(),
      labelEn: z.string().optional(),
    })
    .default({}),
});
export type Badge = z.infer<typeof Badge>;

/* ------------------------------------------------------------------ levels */

/** Mirrors the `LevelInfo` interface (profile.ts). */
export const LevelInfoSchema = z.object({
  level: z.number().int().min(1).max(6),
  nameAr: z.string(),
  nameEn: z.string(),
  progress: z.number().min(0).max(1),
  nextAt: z.number().int().nullable(),
});
export type LevelInfoParsed = z.infer<typeof LevelInfoSchema>;
// Compile-time parity with the `LevelInfo` interface in profile.ts.
const _levelInfoParity: [LevelInfoParsed] extends [LevelInfo] ? ([LevelInfo] extends [LevelInfoParsed] ? true : never) : never = true;
void _levelInfoParity;

/** A public level ring — from `user_point_totals.public_lifetime` (nightly snapshot). */
export const PublicLevelRing = z.object({ level: z.number().int().min(1).max(6), progress: z.number().min(0).max(1) });
export type PublicLevelRing = z.infer<typeof PublicLevelRing>;

/* -------------------------------------------------------------- competitor */

/** rank is shared on ties (1, 1, 3); null when the member has no snapshot yet or 0 points. */
export const PublicCompetitor = z.object({
  handle: z.string(),
  /** null when support hid the name (clients render «عضو يقين»). */
  name: z.string().nullable(),
  avatar: Avatar,
  level: PublicLevelRing,
  /** Snapshot period points; null on the level board. */
  points: z.number().int().nullable(),
  rank: z.number().int().min(1).nullable(),
  me: z.boolean(),
});
export type PublicCompetitor = z.infer<typeof PublicCompetitor>;

/* ------------------------------------------------------------- settings */

/** `consent_events.source`. The client-facing `ConsentUpdate.source` enum is unchanged. */
export const ConsentEventSource = z.enum(['onboarding', 'settings', 'system_prompt', 'system', 'support', 'erasure']);
export type ConsentEventSource = z.infer<typeof ConsentEventSource>;

export const CommunitySettings = z.object({
  leagues: z.boolean(),
  leaderboard: z.boolean(),
  /** Refines `leaderboard`; never grants the consent alone. */
  leaderboardCountry: z.boolean(),
  banned: z.boolean(),
  attestedAdult: z.boolean(),
  country: z.string().regex(/^[A-Z]{2}$/).nullable(),
});
export type CommunitySettings = z.infer<typeof CommunitySettings>;

/** Turning anything on is a direct online call; `attestAdult` is required (true) when not yet attested. */
export const CommunityUpdate = z.object({
  leagues: z.boolean().optional(),
  leaderboard: z.boolean().optional(),
  leaderboardCountry: z.boolean().optional(),
  displayName: DisplayName.optional(),
  attestAdult: z.literal(true).optional(),
  source: z.enum(['onboarding', 'settings']).default('settings'),
});
export type CommunityUpdate = z.infer<typeof CommunityUpdate>;

export const AttestRequest = z.object({ attestAdult: z.literal(true) });
export type AttestRequest = z.infer<typeof AttestRequest>;

/* ----------------------------------------------------------------- profile */

export const LeagueOutcome = z.enum(['up', 'stay', 'down']);
export type LeagueOutcome = z.infer<typeof LeagueOutcome>;

export const LeagueLastWeek = z.object({
  startsOn: z.string(),
  division: DivisionId,
  newDivision: DivisionId,
  rank: z.number().int().nullable(),
  outcome: LeagueOutcome.nullable(),
  badge: Badge.nullable(),
});
export type LeagueLastWeek = z.infer<typeof LeagueLastWeek>;

export const LeagueSummary = z.object({
  division: DivisionId,
  divisionAr: z.string(),
  divisionEn: z.string(),
  /** Snapshot rank. */
  rank: z.number().int().nullable(),
  size: z.number().int(),
  lastWeek: LeagueLastWeek.nullable(),
});
export type LeagueSummary = z.infer<typeof LeagueSummary>;

/** GET /v1/me/profile — the caller only. */
export const MeProfile = z.object({
  displayName: z.string().nullable(),
  nameHidden: z.boolean(),
  handle: z.string().nullable(),
  /** Authed paths for a photo (`OWN_AVATAR_PATHS`). */
  avatar: Avatar,
  photoHidden: z.boolean(),
  photoPublic: z.boolean(),
  /** Live, the caller's own level. */
  level: LevelInfoSchema,
  lifetimePoints: z.number().int(),
  /** Live, self only. */
  weekPoints: z.number().int(),
  community: CommunitySettings,
  league: LeagueSummary.nullable(),
  recentBadges: z.array(Badge).max(12),
  badgesCount: z.number().int(),
});
export type MeProfile = z.infer<typeof MeProfile>;

export const UpdateProfileRequestBase = z.object({ displayName: DisplayName.optional(), avatar: SetAvatar.optional() });
/** PATCH /v1/me/profile. */
export const UpdateProfileRequest = UpdateProfileRequestBase.refine((v) => v.displayName !== undefined || v.avatar !== undefined);
export type UpdateProfileRequest = z.infer<typeof UpdateProfileRequest>;

/* ----------------------------------------------------------------- league */

export const LeagueCurrent = z.discriminatedUnion('state', [
  z.object({ state: z.literal('off') }),
  /** A past week is still being closed. */
  z.object({ state: z.literal('closing') }),
  z.object({
    state: z.literal('joined'),
    startsOn: z.string(),
    endsAt: z.string(),
    snapshotDay: z.string().nullable(),
    division: DivisionId,
    divisionAr: z.string(),
    divisionEn: z.string(),
    nextAr: z.string().nullable(),
    nextEn: z.string().nullable(),
    prevAr: z.string().nullable(),
    prevEn: z.string().nullable(),
    size: z.number().int(),
    promoteZone: z.number().int(),
    demoteZone: z.number().int(),
    /** Live, self only — shown in the stage caption, never in a row. */
    myLivePoints: z.number().int(),
    rows: z.array(PublicCompetitor),
    lastWeek: LeagueLastWeek.nullable(),
  }),
]);
export type LeagueCurrent = z.infer<typeof LeagueCurrent>;

export const LeagueHistoryItem = z.object({
  startsOn: z.string(),
  division: DivisionId,
  rank: z.number().int().nullable(),
  size: z.number().int(),
  points: z.number().int().nullable(),
  outcome: LeagueOutcome.nullable(),
});
export type LeagueHistoryItem = z.infer<typeof LeagueHistoryItem>;

/* ------------------------------------------------------------- tournaments */

export const TournamentPhase = z.enum(['upcoming', 'live', 'ended']);
export type TournamentPhase = z.infer<typeof TournamentPhase>;

export const Tournament = z.object({
  id: z.string().uuid(),
  slug: z.string(),
  titleAr: z.string(),
  titleEn: z.string(),
  bodyAr: z.string(),
  bodyEn: z.string(),
  startsAt: z.string(),
  endsAt: z.string(),
  joinUntil: z.string(),
  phase: TournamentPhase,
  closed: z.boolean(),
  joined: z.boolean(),
  participants: z.number().int(),
  badgeAr: z.string(),
  badgeEn: z.string(),
  me: z
    .object({
      /** Snapshot or final. */
      rank: z.number().int().nullable(),
      /** Live, self only. */
      points: z.number().int(),
    })
    .nullable(),
});
export type Tournament = z.infer<typeof Tournament>;

export const TournamentStandings = z.object({
  total: z.number().int(),
  snapshotDay: z.string().nullable(),
  rows: z.array(PublicCompetitor),
  me: PublicCompetitor.nullable(),
  nextCursor: z.string().nullable(),
});
export type TournamentStandings = z.infer<typeof TournamentStandings>;

export const JoinTournamentRequest = z.object({ acknowledge: z.literal(true), attestAdult: z.literal(true).optional() });
export type JoinTournamentRequest = z.infer<typeof JoinTournamentRequest>;

/* ------------------------------------------------------------- leaderboard */

export const LeaderboardScope = z.enum(['global', 'country']);
export type LeaderboardScope = z.infer<typeof LeaderboardScope>;

export const LeaderboardView = z.object({
  scope: LeaderboardScope,
  country: z.string().nullable(),
  snapshotDay: z.string().nullable(),
  joined: z.boolean(),
  countryJoined: z.boolean(),
  rows: z.array(PublicCompetitor),
  me: PublicCompetitor.nullable(),
});
export type LeaderboardView = z.infer<typeof LeaderboardView>;

/* ------------------------------------------------------------------ safety */

export const REPORT_REASONS = ['name', 'photo', 'other'] as const;
export const ReportReason = z.enum(REPORT_REASONS);
export type ReportReason = z.infer<typeof ReportReason>;

export const ReportRequest = z.object({ handle: z.string(), reason: ReportReason });
export type ReportRequest = z.infer<typeof ReportRequest>;

export const BlockRequest = z.object({ handle: z.string() });
export type BlockRequest = z.infer<typeof BlockRequest>;

export const BlockedUser = z.object({ handle: z.string(), name: z.string().nullable(), avatar: Avatar });
export type BlockedUser = z.infer<typeof BlockedUser>;

/** Stable error codes of the profile/community endpoints (Dart `CommunityFailure` has one value per code). */
export const COMMUNITY_ERROR_CODES = [
  'account_required',
  'community_banned',
  'name_required',
  'name_locked',
  'invalid_name',
  'feature_off',
  'attestation_required',
  'use_community_settings',
  'tournament_not_open',
  'ack_required',
  'country_unknown',
  'country_too_small',
  'photo_locked',
  'photo_too_large',
  'photo_type',
  'photo_unreadable',
  'rate_limited',
  'not_found',
] as const;
export type CommunityErrorCode = (typeof COMMUNITY_ERROR_CODES)[number];

/* ------------------------------------------------------------------- admin */

export const TournamentStatus = z.enum(['draft', 'published', 'cancelled']);
export type TournamentStatus = z.infer<typeof TournamentStatus>;

/** A Cairo calendar day. */
const Day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

export const AdminTournamentBase = z.object({
  slug: z.string().regex(/^[a-z0-9-]{3,40}$/),
  titleAr: z.string().trim().min(1).max(60),
  titleEn: z.string().trim().min(1).max(60),
  bodyAr: z.string().trim().max(280),
  bodyEn: z.string().trim().max(280),
  startsOn: Day,
  /** Inclusive; ends_at = lastDay + 1 at Cairo 00:00. */
  lastDay: Day,
  /** Inclusive; defaults to lastDay. */
  joinLastDay: Day.optional(),
  badgeAr: z.string().trim().min(1).max(40),
  badgeEn: z.string().trim().min(1).max(40),
  minPoints: z.number().int().min(1).max(100000).default(1),
});
export const AdminTournamentCreate = AdminTournamentBase;
export type AdminTournamentCreate = z.infer<typeof AdminTournamentCreate>;
/** `reason` is required by the server when the tournament is live. */
export const AdminTournamentPatch = AdminTournamentBase.partial().extend({ reason: z.string().trim().min(3).max(500).optional() });
export type AdminTournamentPatch = z.infer<typeof AdminTournamentPatch>;

export const AdminTournamentRow = Tournament.omit({ joined: true, me: true }).extend({
  status: TournamentStatus,
  closedAt: z.string().nullable(),
  minPoints: z.number().int(),
  createdBy: z.string().nullable(),
});
export type AdminTournamentRow = z.infer<typeof AdminTournamentRow>;

export const AdminCompetitorRow = z.object({
  userId: z.string().uuid(),
  handle: z.string().nullable(),
  name: z.string().nullable(),
  /** Admin photo route URLs. */
  avatar: Avatar,
  nameHidden: z.boolean(),
  photoHidden: z.boolean(),
  photoLocked: z.boolean(),
  banned: z.boolean(),
  leagues: z.boolean(),
  leaderboard: z.boolean(),
  leaderboardCountry: z.boolean(),
  attestedAdult: z.boolean(),
  division: DivisionId,
  openReports: z.number().int(),
  lastPhotoAt: z.string().nullable(),
  photos: z.array(
    z.object({
      id: z.string().uuid(),
      status: z.enum(['active', 'replaced', 'removed']),
      createdAt: z.string(),
      removedBySupport: z.boolean(),
    }),
  ),
});
export type AdminCompetitorRow = z.infer<typeof AdminCompetitorRow>;

export const AdminStandingRow = PublicCompetitor.extend({ userId: z.string().uuid() });
export type AdminStandingRow = z.infer<typeof AdminStandingRow>;

export const CompetitorAction = z.enum(['hide-name', 'restore-name', 'hide-photo', 'restore-photo', 'ban', 'unban']);
export type CompetitorAction = z.infer<typeof CompetitorAction>;

export const AdminLeagueStats = z.object({
  startsOn: z.string(),
  endsAt: z.string(),
  groups: z.number().int(),
  members: z.array(z.object({ division: DivisionId, count: z.number().int().nullable() })),
  activeShare: z.number().nullable(),
  settingsInForce: LeagueSettingsBase,
  lastWeek: z.object({ up: z.number().int().nullable(), down: z.number().int().nullable() }).nullable(),
});
export type AdminLeagueStats = z.infer<typeof AdminLeagueStats>;

export const AdminTournamentStats = z.object({
  participants: z.number().int().nullable(),
  active: z.number().int().nullable(),
  median: z.number().nullable(),
  buckets: z.array(z.object({ label: z.string(), count: z.number().int().nullable() })),
  badges: z.array(z.object({ kind: BadgeKind, count: z.number().int().nullable() })),
});
export type AdminTournamentStats = z.infer<typeof AdminTournamentStats>;

export const AdminReportRow = z.object({
  id: z.string().uuid(),
  target: AdminCompetitorRow,
  reason: ReportReason,
  count: z.number().int(),
  createdAt: z.string(),
});
export type AdminReportRow = z.infer<typeof AdminReportRow>;

export const ResolveReport = z.object({ resolution: z.enum(['dismissed', 'actioned']), reason: z.string().trim().min(3).max(500) });
export type ResolveReport = z.infer<typeof ResolveReport>;
