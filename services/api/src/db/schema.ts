/**
 * Yaqeen database schema (Postgres, Drizzle ORM).
 *
 * Design rules:
 *  - Points are NEVER stored as a mutable counter. `points_ledger` is append-only;
 *    a balance is SUM(delta). Corrections are new rows (reason = reversal/admin_adjustment).
 *  - Worship activity (task_completions) is personal data. It is never exported to ad
 *    platforms and admins only see aggregates (see docs/SECURITY_PRIVACY.md).
 *  - Every admin write produces an `audit_log` row.
 */
import { sql } from 'drizzle-orm';
import {
  boolean,
  date,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  smallint,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

/* ------------------------------------------------------------------ enums */

export const authProvider = pgEnum('auth_provider', ['google', 'apple', 'guest']);
export const userStatus = pgEnum('user_status', ['active', 'suspended', 'under_review', 'deletion_requested', 'deleted']);
export const platform = pgEnum('platform', ['ios', 'android']);
export const consentKind = pgEnum('consent_kind', [
  'worship_reminders',
  'challenge_rewards',
  'store_offers',
  'ads_measurement',
]);
export const taskKey = pgEnum('task_key', [
  'wird',
  'morning_azkar',
  'five_prayers',
  'evening_azkar',
  'listen',
  'daily_task',
]);
export const bonusKind = pgEnum('bonus_kind', ['white_days_fast', 'mon_thu_fast', 'friday_kahf']);
export const ledgerReason = pgEnum('ledger_reason', [
  'task',
  'bonus',
  'milestone',
  'grant',
  'qada',
  'redemption',
  'admin_adjustment',
  'reversal',
]);
export const contentType = pgEnum('content_type', ['dua', 'zikr', 'splash_verse']);
export const packKind = pgEnum('pack_kind', ['tafsir', 'font', 'audio', 'translation']);
export const contentStatus = pgEnum('content_status', ['draft', 'pending_review', 'changes_requested', 'published']);
export const rewardKind = pgEnum('reward_kind', ['fixed_amount', 'percentage', 'free_shipping']);
export const redemptionStatus = pgEnum('redemption_status', ['issued', 'used', 'expired', 'void']);
export const campaignKind = pgEnum('campaign_kind', ['challenge', 'rewards', 'offers']);
export const campaignStatus = pgEnum('campaign_status', ['draft', 'scheduled', 'sending', 'sent', 'cancelled', 'blocked']);
export const adminRole = pgEnum('admin_role', [
  'super_admin',
  'content_editor',
  'religious_reviewer',
  'marketing',
  'support',
]);

const ts = (name: string) => timestamp(name, { withTimezone: true, mode: 'date' });
const createdAt = () => ts('created_at').notNull().defaultNow();
const updatedAt = () => ts('updated_at').notNull().defaultNow();

/* ------------------------------------------------------------------ users */

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  displayName: text('display_name'),
  email: text('email'),
  isGuest: boolean('is_guest').notNull().default(false),
  status: userStatus('status').notNull().default('active'),
  locale: text('locale').notNull().default('ar'),
  city: text('city'),
  timezone: text('timezone').notNull().default('Africa/Cairo'),
  prayerMethod: text('prayer_method').notNull().default('egypt'),
  asrSchool: text('asr_school').notNull().default('standard'),
  hijriOffsetDays: smallint('hijri_offset_days').notNull().default(0),
  /** Set when a guest was linked into an account that already existed (POST /v1/auth/link). */
  mergedInto: uuid('merged_into'),
  /** When the PDPL erasure request was made; the purge job anonymises 30 days later. */
  deletionRequestedAt: ts('deletion_requested_at'),
  lastSeenAt: ts('last_seen_at'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

export const authIdentities = pgTable(
  'auth_identities',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    provider: authProvider('provider').notNull(),
    /** `sub` claim from Google/Apple; random id for guests. */
    subject: text('subject').notNull(),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('auth_identities_provider_subject_uq').on(t.provider, t.subject)],
);

export const refreshTokens = pgTable(
  'refresh_tokens',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    /** sha256 of the opaque token; the raw token is never stored. */
    tokenHash: text('token_hash').notNull(),
    expiresAt: ts('expires_at').notNull(),
    revokedAt: ts('revoked_at'),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('refresh_tokens_hash_uq').on(t.tokenHash)],
);

export const devices = pgTable(
  'devices',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    platform: platform('platform').notNull(),
    fcmToken: text('fcm_token').notNull(),
    appVersion: text('app_version').notNull(),
    lastSeenAt: ts('last_seen_at').notNull().defaultNow(),
    invalidatedAt: ts('invalidated_at'),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('devices_fcm_token_uq').on(t.fcmToken), index('devices_user_idx').on(t.userId)],
);

/**
 * One row per user per active day (any authenticated request). Feeds the DAU chart.
 * Holds no information about what the user did — only that the app was used.
 */
export const userActivityDays = pgTable(
  'user_activity_days',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    date: date('date', { mode: 'string' }).notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.date] }), index('user_activity_days_date_idx').on(t.date)],
);

/** Current consent state per bucket. */
export const consents = pgTable(
  'consents',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    kind: consentKind('kind').notNull(),
    granted: boolean('granted').notNull(),
    updatedAt: updatedAt(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.kind] })],
);

/** Append-only consent history — the PDPL record of who agreed to what, when, where. */
export const consentEvents = pgTable(
  'consent_events',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    kind: consentKind('kind').notNull(),
    granted: boolean('granted').notNull(),
    source: text('source').notNull(),
    policyVersion: text('policy_version').notNull(),
    createdAt: createdAt(),
  },
  (t) => [index('consent_events_user_idx').on(t.userId, t.createdAt)],
);

/* -------------------------------------------------------------- challenge */

export const challengeEnrollments = pgTable('challenge_enrollments', {
  userId: uuid('user_id')
    .primaryKey()
    .references(() => users.id, { onDelete: 'cascade' }),
  startedOn: date('started_on', { mode: 'string' }).notNull(),
  createdAt: createdAt(),
});

/** Point values per task. Admin-editable; must sum to 100 (enforced in the service). */
export const taskRules = pgTable('task_rules', {
  key: taskKey('key').primaryKey(),
  labelAr: text('label_ar').notNull(),
  labelEn: text('label_en').notNull(),
  points: integer('points').notNull(),
  /** Inactive tasks are hidden in the app and excluded from "day complete". */
  active: boolean('active').notNull().default(true),
  sortOrder: smallint('sort_order').notNull(),
  updatedAt: updatedAt(),
});

/** One-time automatic bonus when a user's streak first reaches `days`. */
export const streakMilestones = pgTable('streak_milestones', {
  days: integer('days').primaryKey(),
  points: integer('points').notNull(),
  labelAr: text('label_ar').notNull(),
  active: boolean('active').notNull().default(true),
  updatedAt: updatedAt(),
});

/** Bulk point gifts to a segment (e.g. "Ramadan gift"). Recipients get ledger rows `grant:<id>`. */
export const pointGrants = pgTable('point_grants', {
  id: uuid('id').primaryKey().defaultRandom(),
  segment: text('segment').notNull(),
  points: integer('points').notNull(),
  reasonAr: text('reason_ar').notNull(),
  recipients: integer('recipients').notNull().default(0),
  createdBy: uuid('created_by').notNull(),
  createdAt: createdAt(),
});

export const bonusRules = pgTable('bonus_rules', {
  kind: bonusKind('kind').primaryKey(),
  labelAr: text('label_ar').notNull(),
  points: integer('points').notNull(),
  enabled: boolean('enabled').notNull().default(false),
  updatedAt: updatedAt(),
});

export const taskCompletions = pgTable(
  'task_completions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    date: date('date', { mode: 'string' }).notNull(),
    task: taskKey('task').notNull(),
    /** true when completed on a later day as qada (make-up). */
    isQada: boolean('is_qada').notNull().default(false),
    clientEventId: text('client_event_id').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex('task_completions_user_date_task_uq').on(t.userId, t.date, t.task),
    uniqueIndex('task_completions_client_event_uq').on(t.userId, t.clientEventId),
    index('task_completions_date_idx').on(t.date),
  ],
);

export const pointsLedger = pgTable(
  'points_ledger',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    delta: integer('delta').notNull(),
    reason: ledgerReason('reason').notNull(),
    /** e.g. "2026-10-20:wird", redemption id, admin id. Unique per user to make awards idempotent. */
    refKey: text('ref_key').notNull(),
    note: text('note'),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex('points_ledger_user_ref_uq').on(t.userId, t.refKey),
    index('points_ledger_user_idx').on(t.userId, t.createdAt),
  ],
);

export const dailyTasks = pgTable('daily_tasks', {
  date: date('date', { mode: 'string' }).primaryKey(),
  taskAr: text('task_ar').notNull(),
  taskEn: text('task_en').notNull(),
  updatedBy: uuid('updated_by'),
  updatedAt: updatedAt(),
});

/* ---------------------------------------------------------------- rewards */

export const rewards = pgTable('rewards', {
  id: uuid('id').primaryKey().defaultRandom(),
  titleAr: text('title_ar').notNull(),
  titleEn: text('title_en').notNull(),
  kind: rewardKind('kind').notNull(),
  /** EGP amount for fixed_amount, 0–100 for percentage, 0 for free_shipping. */
  value: integer('value').notNull(),
  costPoints: integer('cost_points').notNull(),
  monthlyCap: integer('monthly_cap'),
  perUserMonthlyLimit: integer('per_user_monthly_limit'),
  shopifyCollectionIds: jsonb('shopify_collection_ids').$type<string[]>().notNull().default([]),
  validityDays: smallint('validity_days').notNull().default(30),
  active: boolean('active').notNull().default(true),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

export const redemptions = pgTable(
  'redemptions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    rewardId: uuid('reward_id')
      .notNull()
      .references(() => rewards.id),
    code: text('code').notNull(),
    shopifyDiscountId: text('shopify_discount_id'),
    status: redemptionStatus('status').notNull().default('issued'),
    costPoints: integer('cost_points').notNull(),
    expiresAt: ts('expires_at').notNull(),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('redemptions_code_uq').on(t.code), index('redemptions_user_idx').on(t.userId)],
);

/* ---------------------------------------------------------------- content */

export const contentItems = pgTable(
  'content_items',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    type: contentType('type').notNull(),
    category: text('category').notNull(),
    title: text('title').notNull(),
    textAr: text('text_ar').notNull(),
    translationEn: text('translation_en'),
    source: text('source').notNull(),
    repeatCount: smallint('repeat_count').notNull().default(1),
    status: contentStatus('status').notNull().default('draft'),
    reviewNote: text('review_note'),
    version: integer('version').notNull().default(1),
    createdBy: uuid('created_by'),
    reviewedBy: uuid('reviewed_by'),
    publishedAt: ts('published_at'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index('content_items_status_idx').on(t.status, t.type)],
);

/** Licensed recitations offered in the app (GET /v1/content/reciters). */
export const reciters = pgTable('reciters', {
  id: text('id').primaryKey(),
  nameAr: text('name_ar').notNull(),
  nameEn: text('name_en').notNull(),
  /** murattal | mujawwad */
  style: text('style').notNull().default('murattal'),
  riwaya: text('riwaya').notNull().default('hafs'),
  /** Per-surah MP3 base: `${baseUrl}/${surah:03}.mp3`. */
  baseUrl: text('base_url').notNull(),
  timingUrl: text('timing_url'),
  sampleUrl: text('sample_url'),
  sizeBytes: integer('size_bytes').notNull().default(0),
  sortOrder: smallint('sort_order').notNull().default(0),
  active: boolean('active').notNull().default(true),
  updatedAt: updatedAt(),
});

/** Downloadable data packs (tafsir, fonts, audio) with integrity hashes (GET /v1/content/packs). */
export const contentPacks = pgTable('content_packs', {
  id: text('id').primaryKey(),
  kind: packKind('kind').notNull(),
  titleAr: text('title_ar').notNull(),
  titleEn: text('title_en').notNull(),
  version: integer('version').notNull(),
  url: text('url').notNull(),
  sha256: text('sha256').notNull(),
  sizeBytes: integer('size_bytes').notNull(),
  active: boolean('active').notNull().default(true),
  updatedAt: updatedAt(),
});

/* -------------------------------------------------------------- campaigns */

export const campaigns = pgTable('campaigns', {
  id: uuid('id').primaryKey().defaultRandom(),
  name: text('name').notNull(),
  kind: campaignKind('kind').notNull(),
  segment: text('segment').notNull(),
  titleAr: text('title_ar').notNull(),
  bodyAr: text('body_ar').notNull(),
  titleEn: text('title_en').notNull(),
  bodyEn: text('body_en').notNull(),
  deepLink: text('deep_link').notNull(),
  schedule: text('schedule').notNull(),
  scheduledAt: ts('scheduled_at'),
  status: campaignStatus('status').notNull().default('draft'),
  blockedReason: text('blocked_reason'),
  estimatedReach: integer('estimated_reach'),
  sentCount: integer('sent_count').notNull().default(0),
  openCount: integer('open_count').notNull().default(0),
  createdBy: uuid('created_by').notNull(),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

/** One row per (campaign, user) send — used for the daily marketing cap and dedupe. */
export const campaignDeliveries = pgTable(
  'campaign_deliveries',
  {
    campaignId: uuid('campaign_id')
      .notNull()
      .references(() => campaigns.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    kind: campaignKind('kind').notNull(),
    sentAt: ts('sent_at').notNull().defaultNow(),
    openedAt: ts('opened_at'),
  },
  (t) => [primaryKey({ columns: [t.campaignId, t.userId] }), index('campaign_deliveries_user_idx').on(t.userId, t.sentAt)],
);

/* ----------------------------------------------------------------- config */

/** Single-row-per-key remote config (features, minVersion, maintenance, splashVerse). */
export const appConfig = pgTable('app_config', {
  key: text('key').primaryKey(),
  value: jsonb('value').notNull(),
  updatedBy: uuid('updated_by'),
  updatedAt: updatedAt(),
});

export const hijriAdjustments = pgTable(
  'hijri_adjustments',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    region: text('region').notNull(),
    offsetDays: smallint('offset_days').notNull(),
    effectiveHijriMonth: smallint('effective_hijri_month').notNull(),
    effectiveHijriYear: smallint('effective_hijri_year').notNull(),
    createdBy: uuid('created_by').notNull(),
    createdAt: createdAt(),
  },
  (t) => [index('hijri_adjustments_region_idx').on(t.region, t.effectiveHijriYear, t.effectiveHijriMonth)],
);

/* ------------------------------------------------------------------ admin */

export const adminUsers = pgTable(
  'admin_users',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    name: text('name').notNull(),
    email: text('email').notNull(),
    /** scrypt hash: "scrypt$N$r$p$salt$hash" */
    passwordHash: text('password_hash').notNull(),
    /** base32 TOTP secret. Encrypt at rest in production (KMS) — see SECURITY_PRIVACY.md. */
    totpSecret: text('totp_secret').notNull(),
    role: adminRole('role').notNull(),
    /** FCM tokens of this admin's own phones, for "send a test to my device". */
    testDeviceTokens: text('test_device_tokens').array().notNull().default(sql`'{}'::text[]`),
    active: boolean('active').notNull().default(true),
    lastLoginAt: ts('last_login_at'),
    createdAt: createdAt(),
  },
  (t) => [uniqueIndex('admin_users_email_uq').on(sql`lower(${t.email})`)],
);

export const auditLog = pgTable(
  'audit_log',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    /** The admin who acted, or null for actions a user took on their own account (actorUserId). */
    adminId: uuid('admin_id'),
    actorUserId: uuid('actor_user_id'),
    action: text('action').notNull(),
    targetType: text('target_type').notNull(),
    targetId: text('target_id'),
    reason: text('reason'),
    before: jsonb('before'),
    after: jsonb('after'),
    ip: text('ip'),
    createdAt: createdAt(),
  },
  (t) => [index('audit_log_created_idx').on(t.createdAt), index('audit_log_target_idx').on(t.targetType, t.targetId)],
);
