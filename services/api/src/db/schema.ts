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
  bigserial,
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
  'product_analytics',
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
  (t) => [uniqueIndex('refresh_tokens_hash_uq').on(t.tokenHash), index('refresh_tokens_user_idx').on(t.userId)],
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

/**
 * Opt-in public card («بطاقة يقين») for NFC tags and QR codes. One per account; unpublished by
 * default and unpublished again on an erasure request. Holds what the owner typed and the
 * visibility switches only — the activity it shows (level, streak, badges) is computed at read
 * time and never includes worship detail.
 */
export const publicProfiles = pgTable(
  'public_profiles',
  {
    userId: uuid('user_id')
      .primaryKey()
      .references(() => users.id, { onDelete: 'cascade' }),
    /** Lower-case; unique across all profiles. */
    handle: text('handle').notNull(),
    published: boolean('published').notNull().default(false),
    displayName: text('display_name').notNull(),
    bio: text('bio').notNull().default(''),
    links: jsonb('links').$type<{ kind: string; value: string }[]>().notNull().default([]),
    show: jsonb('show')
      .$type<{ level: boolean; streak: boolean; challengeDay: boolean; badges: boolean; memberSince: boolean; timeline?: boolean }>()
      .notNull(),
    theme: text('theme').notNull().default('sky'),
    /** Page opens (bots excluded). A count only — no visitor data is kept. */
    views: integer('views').notNull().default(0),
    /** Hidden by support (audited); the owner can't publish again until it is restored. */
    moderatedAt: ts('moderated_at'),
    moderationReason: text('moderation_reason'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [uniqueIndex('public_profiles_handle_uq').on(t.handle)],
);

/**
 * Physical card tags (key medals, cards): a permanent code in the NFC chip + printed QR, minted in
 * batches for the manufacturer and activated by the owner in the app. `/t/<code>` follows the owner's
 * current handle; a lost tag is switched off (`disabled_at`). Only a scan counter is kept.
 */
export const profileTags = pgTable(
  'profile_tags',
  {
    code: text('code').primaryKey(),
    kind: text('kind').notNull().default('medal'),
    batch: text('batch').notNull(),
    userId: uuid('user_id').references(() => users.id, { onDelete: 'set null' }),
    linkedAt: ts('linked_at'),
    disabledAt: ts('disabled_at'),
    scans: integer('scans').notNull().default(0),
    createdAt: createdAt(),
  },
  (t) => [index('profile_tags_user_idx').on(t.userId), index('profile_tags_batch_idx').on(t.batch)],
);

/**
 * Consented product analytics («تحسين التطبيق»). Keyed by a random per-install id, never the account:
 * no user_id column on purpose. Closed event list without worship activity (contracts PRODUCT_EVENTS).
 * Kept 180 days (purge job), shown to admins as aggregates with small counts withheld.
 */
export const productEvents = pgTable(
  'product_events',
  {
    id: bigserial('id', { mode: 'number' }).primaryKey(),
    anonId: uuid('anon_id').notNull(),
    name: text('name').notNull(),
    props: jsonb('props').$type<Record<string, string>>().notNull().default({}),
    platform: text('platform').notNull(),
    appVersion: text('app_version').notNull(),
    locale: text('locale').notNull(),
    occurredAt: ts('occurred_at').notNull(),
    receivedAt: createdAt(),
  },
  (t) => [index('product_events_time_idx').on(t.occurredAt), index('product_events_name_time_idx').on(t.name, t.occurredAt)],
);

/** A production run of tags: what the factory was asked for and where it stands. */
export const tagBatches = pgTable('tag_batches', {
  batch: text('batch').primaryKey(),
  kind: text('kind').notNull().default('medal'),
  /** ordered → received → on_sale; void = faulty run, every tag switched off. */
  status: text('status').notNull().default('ordered'),
  note: text('note').notNull().default(''),
  createdBy: uuid('created_by').references(() => adminUsers.id, { onDelete: 'set null' }),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
});

/**
 * Card programme counters per day (Africa/Cairo): page opens, medal scans, app / store clicks,
 * publishes, activations. Counts only — no visitor, user or handle is stored.
 */
export const cardDailyStats = pgTable(
  'card_daily_stats',
  {
    date: date('date', { mode: 'string' }).notNull(),
    metric: text('metric').notNull(),
    value: integer('value').notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.date, t.metric] })],
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
  // (kind, granted) serves campaign audience queries ("everyone who allowed store offers").
  (t) => [primaryKey({ columns: [t.userId, t.kind] }), index('consents_kind_granted_idx').on(t.kind, t.granted)],
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
    /** Client key for one confirm tap: a retry returns the same code instead of spending twice. */
    idempotencyKey: text('idempotency_key'),
    /** Set by the Shopify orders/paid webhook when the code is used at checkout. */
    usedAt: ts('used_at'),
    shopifyOrderId: text('shopify_order_id'),
    createdAt: createdAt(),
  },
  (t) => [
    uniqueIndex('redemptions_code_uq').on(t.code),
    uniqueIndex('redemptions_user_idem_uq').on(t.userId, t.idempotencyKey),
    index('redemptions_user_idx').on(t.userId),
    // Monthly caps count per reward per month inside the redeem transaction.
    index('redemptions_reward_created_idx').on(t.rewardId, t.createdAt),
    // The expiry job scans issued codes past their date.
    index('redemptions_status_expires_idx').on(t.status, t.expiresAt),
  ],
);

/* ---------------------------------------------------------------- content */

export interface LiveContent {
  category: string;
  title: string;
  textAr: string;
  translationEn: string | null;
  source: string;
  virtue: string | null;
  repeatCount: number;
  sortOrder: number;
  featured: boolean;
  version: number;
}

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
    virtue: text('virtue'),
    repeatCount: smallint('repeat_count').notNull().default(1),
    sortOrder: smallint('sort_order').notNull().default(0),
    featured: boolean('featured').notNull().default(false),
    status: contentStatus('status').notNull().default('draft'),
    reviewNote: text('review_note'),
    version: integer('version').notNull().default(1),
    createdBy: uuid('created_by'),
    reviewedBy: uuid('reviewed_by'),
    publishedAt: ts('published_at'),
    /**
     * The reviewer-approved text the app is served. An edit goes back through review while this
     * snapshot stays live; approving the edit replaces it.
     */
    live: jsonb('live').$type<LiveContent>(),
    liveAt: ts('live_at'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [index('content_items_status_idx').on(t.status, t.type), index('content_items_live_idx').on(t.type, t.liveAt)],
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

export const campaigns = pgTable(
  'campaigns',
  {
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
  },
  // The dispatcher polls due campaigns every few minutes.
  (t) => [index('campaigns_status_scheduled_idx').on(t.status, t.scheduledAt)],
);

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
