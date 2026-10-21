import { z } from 'zod';
import {
  AdminRole,
  AsrSchool,
  AuthProvider,
  BonusKind,
  CampaignKind,
  CampaignSchedule,
  CampaignSegment,
  ConsentKind,
  ContentStatus,
  ContentType,
  DayStatus,
  DeepLink,
  LedgerReason,
  PackKind,
  Platform,
  PrayerMethod,
  RedemptionStatus,
  RewardKind,
  TaskKey,
  UserStatus,
} from './enums.js';

const IsoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'YYYY-MM-DD');
const Uuid = z.uuid();

/* ------------------------------------------------------------------ auth */

export const SignInRequest = z.object({
  provider: AuthProvider,
  /** Google/Apple ID token. Omitted for guest. */
  idToken: z.string().min(10).optional(),
  displayName: z.string().max(80).optional(),
  locale: z.enum(['ar', 'en']).default('ar'),
});
export type SignInRequest = z.infer<typeof SignInRequest>;

/** Upgrade the signed-in guest to a Google/Apple account, keeping their points. */
export const LinkRequest = z.object({
  provider: z.enum(['google', 'apple']),
  idToken: z.string().min(10),
  displayName: z.string().max(80).optional(),
});
export type LinkRequest = z.infer<typeof LinkRequest>;

export const SessionResponse = z.object({
  accessToken: z.string(),
  refreshToken: z.string(),
  expiresIn: z.number().int(),
  user: z.object({ id: Uuid, displayName: z.string().nullable(), isGuest: z.boolean() }),
});
export type SessionResponse = z.infer<typeof SessionResponse>;

/* -------------------------------------------------------------- me / prefs */

export const UserSettings = z.object({
  locale: z.enum(['ar', 'en']),
  city: z.string().max(80).nullable(),
  timezone: z.string().max(64),
  prayerMethod: PrayerMethod,
  asrSchool: AsrSchool,
  hijriOffsetDays: z.number().int().min(-2).max(2),
});
export type UserSettings = z.infer<typeof UserSettings>;

export const UpdateSettingsRequest = UserSettings.partial();
export type UpdateSettingsRequest = z.infer<typeof UpdateSettingsRequest>;

export const ConsentUpdate = z.object({
  kind: ConsentKind,
  granted: z.boolean(),
  /** Where the user changed it: onboarding screen, settings… (kept for the PDPL record). */
  source: z.enum(['onboarding', 'settings', 'system_prompt']),
});
export type ConsentUpdate = z.infer<typeof ConsentUpdate>;

export const ConsentsResponse = z.record(ConsentKind, z.boolean());
export type ConsentsResponse = z.infer<typeof ConsentsResponse>;

export const RegisterDeviceRequest = z.object({
  platform: Platform,
  fcmToken: z.string().min(20),
  appVersion: z.string().max(20),
});
export type RegisterDeviceRequest = z.infer<typeof RegisterDeviceRequest>;

/* ------------------------------------------------------------------ config */

export const RemoteConfig = z.object({
  features: z.record(z.string(), z.boolean()),
  /**
   * Gradual rollout per flag, 0–100. A flag that is ON is shown to a user only when
   * `inRollout(userId, flag, pct)` (see rollout.ts — mirrored in Dart). Missing = 100.
   */
  featureRollout: z.record(z.string(), z.number().int().min(0).max(100)).default({}),
  minVersion: z.object({ ios: z.string(), android: z.string() }),
  maintenance: z.object({ enabled: z.boolean(), messageAr: z.string(), messageEn: z.string() }),
  splashVerse: z.object({ textAr: z.string(), reference: z.string() }),
  hijri: z.object({ region: z.string(), offsetDays: z.number().int(), effectiveFrom: z.string().nullable() }),
  /** Read-only here; edited via /admin/rewards/program. */
  points: z.object({
    dailyTotal: z.number().int(),
    qadaDayPoints: z.number().int(),
    qadaWindowDays: z.number().int(),
    challengeLengthDays: z.number().int(),
    /** Cost of the cheapest active reward (onboarding: «1,000 نقطة = مكافأة»). null when none. */
    cheapestRewardPoints: z.number().int().nullable(),
  }),
});
export type RemoteConfig = z.infer<typeof RemoteConfig>;

/* ---------------------------------------------------------------- calendar */

export const HijriDay = z.object({
  gregorian: IsoDate,
  hijriDay: z.number().int(),
  hijriMonth: z.number().int(),
  hijriYear: z.number().int(),
  hijriMonthNameAr: z.string(),
  weekday: z.number().int().min(0).max(6),
});
export type HijriDay = z.infer<typeof HijriDay>;

export const HijriMonthResponse = z.object({
  method: z.literal('UAQ'),
  offsetDays: z.number().int(),
  days: z.array(HijriDay),
});
export type HijriMonthResponse = z.infer<typeof HijriMonthResponse>;

/* --------------------------------------------------------------- challenge */

export const CompleteTaskRequest = z.object({
  date: IsoDate,
  /** Client-generated id so retries from offline queues are idempotent. */
  clientEventId: z.string().min(8).max(64),
});
export type CompleteTaskRequest = z.infer<typeof CompleteTaskRequest>;

export const ChallengeDay = z.object({
  date: IsoDate,
  dayNumber: z.number().int(),
  status: DayStatus,
  points: z.number().int(),
  completedTasks: z.array(TaskKey),
  bonuses: z.array(BonusKind),
});
export type ChallengeDay = z.infer<typeof ChallengeDay>;

export const ChallengeSummary = z.object({
  enrolled: z.boolean(),
  startedOn: IsoDate.nullable(),
  dayNumber: z.number().int(),
  streak: z.number().int(),
  balance: z.number().int(),
  challengeLengthDays: z.number().int(),
  nextMilestone: z.object({ days: z.number().int(), points: z.number().int() }).nullable(),
  today: ChallengeDay.nullable(),
  tasks: z.array(z.object({ key: TaskKey, labelAr: z.string(), labelEn: z.string(), points: z.number().int() })),
});
export type ChallengeSummary = z.infer<typeof ChallengeSummary>;

/** One cell of the merged calendar (GET /v1/challenge/calendar?month=YYYY-MM). */
export const SpecialDay = z.enum(['white_day', 'friday', 'mon_thu', 'ramadan', 'eid_fitr', 'eid_adha', 'arafah', 'ashura']);
export type SpecialDay = z.infer<typeof SpecialDay>;

export const CalendarCell = HijriDay.extend({
  challenge: ChallengeDay.nullable(),
  special: z.array(SpecialDay),
});
export type CalendarCell = z.infer<typeof CalendarCell>;

export const ChallengeCalendar = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/),
  enrolled: z.boolean(),
  startedOn: IsoDate.nullable(),
  endsOn: IsoDate.nullable(),
  today: IsoDate,
  dayNumber: z.number().int(),
  streak: z.number().int(),
  balance: z.number().int(),
  qadaWindowDays: z.number().int(),
  qadaDayPoints: z.number().int(),
  dailyTotal: z.number().int(),
  days: z.array(CalendarCell),
});
export type ChallengeCalendar = z.infer<typeof ChallengeCalendar>;

/* ----------------------------------------------------------------- rewards */

export const Reward = z.object({
  id: Uuid,
  titleAr: z.string(),
  titleEn: z.string(),
  kind: RewardKind,
  value: z.number(),
  costPoints: z.number().int(),
  available: z.boolean(),
});
export type Reward = z.infer<typeof Reward>;

export const Redemption = z.object({
  id: Uuid,
  rewardId: Uuid,
  code: z.string(),
  status: RedemptionStatus,
  expiresAt: z.string(),
  balanceAfter: z.number().int(),
});
export type Redemption = z.infer<typeof Redemption>;

/* ----------------------------------------------------------------- content */

export const ContentItem = z.object({
  id: Uuid,
  type: ContentType,
  category: z.string(),
  title: z.string(),
  textAr: z.string(),
  translationEn: z.string().nullable(),
  source: z.string(),
  repeatCount: z.number().int().min(1),
  version: z.number().int(),
  updatedAt: z.string(),
});
export type ContentItem = z.infer<typeof ContentItem>;

export const Reciter = z.object({
  id: z.string(),
  nameAr: z.string(),
  nameEn: z.string(),
  style: z.enum(['murattal', 'mujawwad']),
  riwaya: z.string(),
  baseUrl: z.string(),
  timingUrl: z.string().nullable(),
  sampleUrl: z.string().nullable(),
  sizeBytes: z.number().int(),
});
export type Reciter = z.infer<typeof Reciter>;

export const ContentPack = z.object({
  id: z.string(),
  kind: PackKind,
  titleAr: z.string(),
  titleEn: z.string(),
  version: z.number().int(),
  url: z.string(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
  sizeBytes: z.number().int(),
});
export type ContentPack = z.infer<typeof ContentPack>;

/* ------------------------------------------------------------------- admin */

export const AdminLoginRequest = z.object({
  email: z.email(),
  password: z.string().min(10),
  totp: z.string().regex(/^\d{6}$/),
});
export type AdminLoginRequest = z.infer<typeof AdminLoginRequest>;

export const AdminMe = z.object({ id: Uuid, name: z.string(), email: z.email(), role: AdminRole });
export type AdminMe = z.infer<typeof AdminMe>;

export const AdminOverview = z.object({
  dau: z.number().int(),
  mau: z.number().int(),
  challengeParticipants: z.number().int(),
  pointsIssued30d: z.number().int(),
  pointsRedeemed30d: z.number().int(),
  /** Aggregates only. Never per-user worship data. */
  habitsToday: z.object({ wirdPct: z.number(), morningAzkarPct: z.number(), prayersPct: z.number() }),
  pendingReviews: z.number().int(),
});
export type AdminOverview = z.infer<typeof AdminOverview>;

/** Aggregates only. Buckets with fewer than K_ANONYMITY people are returned as null. */
export const K_ANONYMITY = 20;

export const OverviewRange = z.enum(['7d', '30d', '90d']);
export type OverviewRange = z.infer<typeof OverviewRange>;

export const SeriesPoint = z.object({ date: IsoDate, value: z.number().int().nullable() });
export const OverviewSeries = z.object({ metric: z.literal('dau'), range: OverviewRange, points: z.array(SeriesPoint) });
export type OverviewSeries = z.infer<typeof OverviewSeries>;

export const OverviewFunnel = z.object({
  steps: z.array(z.object({ days: z.number().int(), users: z.number().int().nullable() })),
});
export type OverviewFunnel = z.infer<typeof OverviewFunnel>;

export const OverviewAdherence = z.object({
  date: IsoDate,
  participants: z.number().int(),
  /** Percent of participants, or null when suppressed (participants < K_ANONYMITY). */
  wirdPct: z.number().nullable(),
  morningAzkarPct: z.number().nullable(),
  prayersPct: z.number().nullable(),
});
export type OverviewAdherence = z.infer<typeof OverviewAdherence>;

export const OverviewAlert = z.object({
  kind: z.enum(['pending_reviews', 'daily_task_missing', 'reward_low_stock', 'moon_sighting', 'shopify_error']),
  severity: z.enum(['info', 'warning']),
  messageAr: z.string(),
  href: z.string(),
});
export type OverviewAlert = z.infer<typeof OverviewAlert>;

export const AdminUserRow = z.object({
  id: Uuid,
  displayName: z.string().nullable(),
  emailMasked: z.string().nullable(),
  provider: AuthProvider,
  status: UserStatus,
  joinedAt: z.string(),
  challengeDay: z.number().int(),
  balance: z.number().int(),
});
export type AdminUserRow = z.infer<typeof AdminUserRow>;

export const AdjustPointsRequest = z.object({
  delta: z.number().int().refine((n) => n !== 0, 'delta cannot be 0'),
  reason: z.enum(['technical_compensation', 'approved_support', 'fraud_reversal']),
  note: z.string().max(200).optional(),
});
export type AdjustPointsRequest = z.infer<typeof AdjustPointsRequest>;

export const LedgerEntry = z.object({
  id: Uuid,
  delta: z.number().int(),
  reason: LedgerReason,
  note: z.string().nullable(),
  createdAt: z.string(),
});
export type LedgerEntry = z.infer<typeof LedgerEntry>;

export const UpsertContentRequest = z.object({
  type: ContentType,
  category: z.string().min(1).max(60),
  title: z.string().min(1).max(120),
  textAr: z.string().min(1),
  translationEn: z.string().nullable().optional(),
  source: z.string().min(2).max(160),
  repeatCount: z.number().int().min(1).default(1),
});
export type UpsertContentRequest = z.infer<typeof UpsertContentRequest>;

export const ReviewDecision = z.object({
  decision: z.enum(['approve', 'request_changes']),
  note: z.string().max(500).optional(),
});
export type ReviewDecision = z.infer<typeof ReviewDecision>;

export const ContentAdminRow = ContentItem.extend({ status: ContentStatus, reviewNote: z.string().nullable() });
export type ContentAdminRow = z.infer<typeof ContentAdminRow>;

export const DailyTaskUpsert = z.object({
  date: IsoDate,
  taskAr: z.string().min(2).max(120),
  taskEn: z.string().min(2).max(120),
});
export type DailyTaskUpsert = z.infer<typeof DailyTaskUpsert>;

/** "Send a test to my device" — same copy validation, admin's own test devices only. */
export const CampaignTest = z.object({
  titleAr: z.string().min(2).max(60),
  bodyAr: z.string().min(2).max(140),
  titleEn: z.string().min(2).max(60).optional(),
  bodyEn: z.string().min(2).max(140).optional(),
  deepLink: DeepLink,
  locale: z.enum(['ar', 'en']).default('ar'),
});
export type CampaignTest = z.infer<typeof CampaignTest>;

export const TestDevicesUpdate = z.object({ tokens: z.array(z.string().min(20).max(4096)).max(5) });
export type TestDevicesUpdate = z.infer<typeof TestDevicesUpdate>;

export const CampaignCreate = z.object({
  name: z.string().min(2).max(80),
  kind: CampaignKind,
  segment: CampaignSegment,
  titleAr: z.string().min(2).max(60),
  bodyAr: z.string().min(2).max(140),
  titleEn: z.string().min(2).max(60),
  bodyEn: z.string().min(2).max(140),
  deepLink: DeepLink,
  schedule: CampaignSchedule,
  scheduledAt: z.iso.datetime().optional(),
});
export type CampaignCreate = z.infer<typeof CampaignCreate>;

/* ------------------------------------------------- points program (admin) */

/** Global rules of the points program. Stored in app_config under key "points". */
export const PointsSettings = z
  .object({
    /** Points for a fully completed day; active task values must add up to this. */
    dailyTotal: z.number().int().min(10).max(1000),
    /** Max points a made-up (qada) day can be worth in total. */
    qadaDayPoints: z.number().int().min(0).max(1000),
    /** How many days back a missed day can be made up. 0 disables qada. */
    qadaWindowDays: z.number().int().min(0).max(30),
    challengeLengthDays: z.number().int().min(30).max(1000),
  })
  .refine((s) => s.qadaDayPoints <= s.dailyTotal, { message: 'qadaDayPoints cannot exceed dailyTotal', path: ['qadaDayPoints'] });
export type PointsSettings = z.infer<typeof PointsSettings>;

export const TaskRuleInput = z.object({
  key: TaskKey,
  labelAr: z.string().min(2).max(40),
  labelEn: z.string().min(2).max(40),
  points: z.number().int().min(0).max(500),
  active: z.boolean(),
});
export type TaskRuleInput = z.infer<typeof TaskRuleInput>;

/** Settings + all six tasks in one request so the total is validated atomically. */
export const ProgramUpdate = z.object({
  settings: PointsSettings,
  tasks: z.array(TaskRuleInput).length(6),
});
export type ProgramUpdate = z.infer<typeof ProgramUpdate>;

/** Automatic one-time bonus when a streak reaches `days`. */
export const StreakMilestone = z.object({
  days: z.number().int().min(2).max(1000),
  points: z.number().int().min(1).max(10000),
  labelAr: z.string().min(2).max(60),
  active: z.boolean(),
});
export type StreakMilestone = z.infer<typeof StreakMilestone>;
export const MilestonesUpdate = z
  .array(StreakMilestone)
  .max(20)
  .refine((a) => new Set(a.map((m) => m.days)).size === a.length, 'Each milestone needs a different number of days');

export const BonusRuleUpdate = z.object({ points: z.number().int().min(0).max(1000), enabled: z.boolean() });

export const GrantSegment = z.enum(['all_enrolled', 'active_7d', 'streak_gte_7', 'all_users']);
export type GrantSegment = z.infer<typeof GrantSegment>;

/** Gift points to a whole segment (e.g. Ramadan gift). Idempotent per grant. */
export const GrantCreate = z.object({
  segment: GrantSegment,
  points: z.number().int().min(1).max(5000),
  reasonAr: z.string().min(3).max(120),
});
export type GrantCreate = z.infer<typeof GrantCreate>;

export const RewardUpsert = z.object({
  titleAr: z.string().min(2),
  titleEn: z.string().min(2),
  kind: RewardKind,
  value: z.number().positive(),
  costPoints: z.number().int().positive(),
  /** Total codes of this reward per calendar month (all users). */
  monthlyCap: z.number().int().positive().nullable(),
  /** Max codes of this reward one user can redeem per calendar month. */
  perUserMonthlyLimit: z.number().int().positive().nullable().default(null),
  validityDays: z.number().int().min(1).max(365).default(30),
  shopifyCollectionIds: z.array(z.string()).default([]),
  active: z.boolean(),
});
export type RewardUpsert = z.infer<typeof RewardUpsert>;

export const HijriAdjustRequest = z.object({
  region: z.literal('EG'),
  offsetDays: z.number().int().min(-1).max(1),
  effectiveHijriMonth: z.number().int().min(1).max(12),
  effectiveHijriYear: z.number().int().min(1440),
});
export type HijriAdjustRequest = z.infer<typeof HijriAdjustRequest>;

/** Splash verse change → pending review. Goes live only after a religious reviewer (not the author) approves. */
export const SplashVerseUpdate = z.object({
  textAr: z.string().min(2).max(200),
  reference: z.string().min(2).max(60),
});
export type SplashVerseUpdate = z.infer<typeof SplashVerseUpdate>;

export const ShopifyStatus = z.object({
  configured: z.boolean(),
  connected: z.boolean(),
  shopName: z.string().nullable(),
  domain: z.string().nullable(),
  scopes: z.array(z.string()),
  lastError: z.string().nullable(),
  lastErrorAt: z.string().nullable(),
});
export type ShopifyStatus = z.infer<typeof ShopifyStatus>;

export const ShopifyCollection = z.object({ id: z.string(), title: z.string(), productsCount: z.number().int().nullable() });
export type ShopifyCollection = z.infer<typeof ShopifyCollection>;

export const ConfigPatch = RemoteConfig.partial();
export type ConfigPatch = z.infer<typeof ConfigPatch>;

export const Paged = <T extends z.ZodTypeAny>(item: T) =>
  z.object({ items: z.array(item), nextCursor: z.string().nullable() });
