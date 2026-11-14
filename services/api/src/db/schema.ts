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
  type AnyPgColumn,
  bigint,
  bigserial,
  boolean,
  check,
  customType,
  date,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  real,
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
  'cloud_backup',
  'community',
]);
export const taskKey = pgEnum('task_key', [
  'wird',
  'morning_azkar',
  'five_prayers',
  'evening_azkar',
  'listen',
  'daily_task',
]);
export const bonusKind = pgEnum('bonus_kind', ['white_days_fast', 'mon_thu_fast', 'friday_kahf', 'ramadan_fast', 'taraweeh', 'ramadan_juz']);
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
  /** ISO-3166 alpha-2 of the chosen city (sent by the app). Used only for the opt-in country board. */
  country: text('country'),
  /** `initial` | `preset` | `photo` (contracts `Avatar`). */
  avatarKind: text('avatar_kind').notNull().default('initial'),
  /** One of contracts `AVATAR_PRESETS`; required for `preset`, kept as the fallback for `photo`. */
  avatarPreset: text('avatar_preset'),
  /** The active photo (FK added after `avatar_photos` exists, migration 0017). */
  avatarPhotoId: uuid('avatar_photo_id').references((): AnyPgColumn => avatarPhotos.id, { onDelete: 'set null' }),
  /** Support hid the name (audited): the public name is null and renaming is locked. */
  nameHiddenAt: ts('name_hidden_at'),
  nameHiddenReason: text('name_hidden_reason'),
  /** Support removed a photo (audited): uploads are refused with `photo_locked` until restored. */
  photoLockedAt: ts('photo_locked_at'),
  /** The 18+ (or guardian consent) attestation, set by any community join that carries `attestAdult`. */
  adultAttestedAt: ts('adult_attested_at'),
  createdAt: createdAt(),
  updatedAt: updatedAt(),
}, (t) => [
  check('users_country_ck', sql`${t.country} ~ '^[A-Z]{2}$'`),
  check('users_avatar_kind_ck', sql`${t.avatarKind} in ('initial', 'preset', 'photo')`),
  check(
    'users_avatar_preset_ck',
    sql`${t.avatarPreset} in ('m01','m02','m03','m04','m05','m06','m07','m08','f01','f02','f03','f04','f05','f06','f07','f08')`,
  ),
  check('users_avatar_preset_required_ck', sql`${t.avatarKind} <> 'preset' or ${t.avatarPreset} is not null`),
]);

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
    /** Written onto a chip in-house with the staff encoder (last write; null = not yet). */
    encodedAt: ts('encoded_at'),
    /** The chip's UID (hex) the encoder reported, when the phone could read it. */
    encodedUid: text('encoded_uid'),
    /** The chip was made read-only after writing (permanent). */
    encodedLocked: boolean('encoded_locked').notNull().default(false),
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

/**
 * Server-side `purchase` conversions already sent, one row per Shopify order and ad platform, so a
 * replayed orders/paid webhook never sends twice. No user id, no amount — only what dedupe needs.
 * `failed` rows may be retried by a later replay (`attempts` caps it).
 */
export const conversionSends = pgTable(
  'conversion_sends',
  {
    orderId: text('order_id').notNull(),
    /** meta · ga4 · tiktok */
    platform: text('platform').notNull(),
    /** pending · sent · failed */
    status: text('status').notNull(),
    attempts: smallint('attempts').notNull().default(1),
    sentAt: ts('sent_at'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [primaryKey({ columns: [t.orderId, t.platform] }), index('conversion_sends_sent_idx').on(t.sentAt)],
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
 * Short-lived staff encoding sessions: marketing opens one for a batch in admin, a staff phone opens
 * `yaqeen://encode/<token>` and writes `/t/<code>` onto blank chips. The token is a capability scoped
 * to one batch; only its SHA-256 is stored. Expires (2 h) or is revoked; creation/revocation audited.
 */
export const tagEncodeSessions = pgTable(
  'tag_encode_sessions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    batch: text('batch')
      .notNull()
      .references(() => tagBatches.batch, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull().unique(),
    createdBy: uuid('created_by').references(() => adminUsers.id, { onDelete: 'set null' }),
    expiresAt: ts('expires_at').notNull(),
    revokedAt: ts('revoked_at'),
    createdAt: createdAt(),
  },
  (t) => [index('tag_encode_sessions_batch_idx').on(t.batch)],
);

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
    /** contracts `ConsentEventSource`: onboarding, settings, system_prompt, system (job), support, erasure. */
    source: text('source').notNull(),
    policyVersion: text('policy_version').notNull(),
    /** true on the `community` row written by a join that carried the 18+ attestation. */
    attestedAdult: boolean('attested_adult'),
    createdAt: createdAt(),
  },
  (t) => [index('consent_events_user_idx').on(t.userId, t.createdAt)],
);

/**
 * Opt-in cloud backup of the user's personal progress (consent `cloud_backup`, signed-in accounts
 * only): one document per kind (contracts `BACKUP_KINDS`), sealed with AES-256-GCM under
 * BACKUP_SECRETS_KEY. Only the user reads it (GET /v1/me/backup, /v1/me/export); no admin route,
 * aggregate, analytics or ad sink touches it. Withdrawing the consent or erasure deletes the rows.
 */
export const userBackups = pgTable(
  'user_backups',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    kind: text('kind').notNull(),
    /** "enc:v1:<iv>.<tag>.<ciphertext>" — the JSON document, never stored in the clear in production. */
    blob: text('blob').notNull(),
    /** Optimistic-concurrency counter: 1 on the first write, +1 on each accepted PUT. */
    version: integer('version').notNull().default(1),
    deviceId: text('device_id'),
    updatedAt: updatedAt(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.kind] })],
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

/**
 * «مهمة اليوم». Religious content (CLAUDE rule 4): every write goes to review, a religious reviewer
 * who is not its author (`updated_by`) approves it, and the app is served only the approved `live`
 * text.
 */
export const dailyTasks = pgTable('daily_tasks', {
  date: date('date', { mode: 'string' }).primaryKey(),
  taskAr: text('task_ar').notNull(),
  taskEn: text('task_en').notNull(),
  updatedBy: uuid('updated_by'),
  status: contentStatus('status').notNull().default('pending_review'),
  reviewedBy: uuid('reviewed_by'),
  reviewNote: text('review_note'),
  live: jsonb('live').$type<{ taskAr: string; taskEn: string }>(),
  liveAt: ts('live_at'),
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

/**
 * Curated recitations offered in the app (GET /v1/content/reciters): our allowlist, order and
 * Arabic names. `source = 'qf'` rows point at a Quran Foundation chapter reciter (`qf_id`) whose
 * audio + timings are resolved per surah; `source = 'own'` rows serve files from our CDN.
 */
export const reciters = pgTable('reciters', {
  id: text('id').primaryKey(),
  nameAr: text('name_ar').notNull(),
  nameEn: text('name_en').notNull(),
  /** murattal | mujawwad | muallim */
  style: text('style').notNull().default('murattal'),
  riwaya: text('riwaya').notNull().default('hafs'),
  /** qf | own */
  source: text('source').notNull().default('own'),
  /** Quran Foundation chapter-reciter id (`/resources/chapter_reciters`), for `source = 'qf'`. */
  qfId: integer('qf_id'),
  /** `own` only — per-surah MP3 base: `${baseUrl}/${surah:03}.mp3`. */
  baseUrl: text('base_url'),
  timingUrl: text('timing_url'),
  sampleUrl: text('sample_url'),
  /** Whole-mushaf download size (Quran Foundation recitations exceed 2^31 bytes). */
  sizeBytes: bigint('size_bytes', { mode: 'number' }).notNull().default(0),
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

/* ------------------------------------------------------- profile & community */
/*
 * docs/design/2026-11-profile-community-quran.md §2, APP_SPEC §5.24 / §5.31. Others see only the
 * name/@handle, avatar, the public level ring and snapshot period points — never worship detail and
 * never anything live. Competitions never write `points_ledger`; badges live in `user_badges`.
 * `points_earned_daily` and `user_point_totals` are derived caches kept by the `yq_points_rollup`
 * trigger (migration 0017) and rebuildable with `select yq_rebuild_points_rollups();` — not balances.
 */

const bytea = customType<{ data: Buffer }>({ dataType: () => 'bytea' });

/** Re-encoded profile photos (sharp → WebP, EXIF stripped), ≈ 30 KB per user. New id per upload. */
export const avatarPhotos = pgTable(
  'avatar_photos',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    /** sha256 of each size — the per-size ETag. */
    shaSmall: text('sha_small').notNull(),
    shaLarge: text('sha_large').notNull(),
    /** 96-px WebP. */
    small: bytea('small').notNull(),
    /** 256-px WebP. */
    large: bytea('large').notNull(),
    bytes: integer('bytes').notNull(),
    status: text('status').notNull().default('active'),
    createdAt: createdAt(),
    removedAt: ts('removed_at'),
    /** Support removal (audited); null when the owner removed or replaced it. */
    removedBy: uuid('removed_by').references(() => adminUsers.id),
    removedReason: text('removed_reason'),
  },
  (t) => [
    // Also serves the 10-uploads-per-hour rate limit, counted in the database.
    index('avatar_photos_user_idx').on(t.userId, t.createdAt.desc()),
    index('avatar_photos_status_idx').on(t.status, t.createdAt.desc()),
    check('avatar_photos_status_ck', sql`${t.status} in ('active', 'replaced', 'removed')`),
  ],
);

/** Opt-in switches. The `community` consent is granted while leagues, leaderboard or a live tournament entry holds. */
export const communityMembers = pgTable(
  'community_members',
  {
    userId: uuid('user_id')
      .primaryKey()
      .references(() => users.id, { onDelete: 'cascade' }),
    leagues: boolean('leagues').notNull().default(false),
    leaderboard: boolean('leaderboard').notNull().default(false),
    /** Refines `leaderboard` (country board); never grants the consent alone. */
    leaderboardCountry: boolean('leaderboard_country').notNull().default(false),
    division: smallint('division').notNull().default(1),
    bannedAt: ts('banned_at'),
    bannedReason: text('banned_reason'),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [check('community_members_division_ck', sql`${t.division} between 1 and 6`)],
);

/** A block hides each user from the other's views (both directions, display only). */
export const communityBlocks = pgTable(
  'community_blocks',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    blockedUserId: uuid('blocked_user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    createdAt: createdAt(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.blockedUserId] }),
    index('community_blocks_blocked_idx').on(t.blockedUserId),
    check('community_blocks_not_self_ck', sql`${t.userId} <> ${t.blockedUserId}`),
  ],
);

/** Derived: points earned (contracts `EARNED_REASONS`) per Africa/Cairo day. No time-of-day column. */
export const pointsEarnedDaily = pgTable(
  'points_earned_daily',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    day: date('day', { mode: 'string' }).notNull(),
    earned: integer('earned').notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.day] }), index('points_earned_daily_day_idx').on(t.day, t.userId)],
);

/** Derived: lifetime earned (contracts `LEVEL_REASONS`, delta > 0) and its nightly public snapshot. */
export const userPointTotals = pgTable(
  'user_point_totals',
  {
    userId: uuid('user_id')
      .primaryKey()
      .references(() => users.id, { onDelete: 'cascade' }),
    lifetimeEarned: integer('lifetime_earned').notNull().default(0),
    /** Every public level ring reads this (refreshed once per Cairo day). */
    publicLifetime: integer('public_lifetime').notNull().default(0),
    publicDay: date('public_day', { mode: 'string' }),
  },
  (t) => [index('user_point_totals_public_idx').on(t.publicLifetime.desc())],
);

/** Saturday 00:00 → Saturday 00:00, Africa/Cairo. */
export const leagueWeeks = pgTable(
  'league_weeks',
  {
    startsOn: date('starts_on', { mode: 'string' }).primaryKey(),
    startsAt: ts('starts_at').notNull(),
    endsAt: ts('ends_at').notNull(),
    /** The contracts `LeagueSettings` in force for this week; filled when the week starts, never changed after. */
    settings: jsonb('settings'),
    status: text('status').notNull().default('open'),
    closedAt: ts('closed_at'),
  },
  (t) => [check('league_weeks_status_ck', sql`${t.status} in ('open', 'closed')`)],
);

export const leagueGroups = pgTable(
  'league_groups',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    startsOn: date('starts_on', { mode: 'string' })
      .notNull()
      .references(() => leagueWeeks.startsOn),
    division: smallint('division').notNull(),
    size: smallint('size').notNull().default(0),
    /** Set when the close step claimed and finished this group (resumable close). */
    closedAt: ts('closed_at'),
    createdAt: createdAt(),
  },
  (t) => [
    index('league_groups_fill_idx').on(t.startsOn, t.division, t.size),
    index('league_groups_open_idx').on(t.startsOn).where(sql`${t.closedAt} is null`),
    check('league_groups_division_ck', sql`${t.division} between 1 and 6`),
  ],
);

export const leagueMembers = pgTable(
  'league_members',
  {
    startsOn: date('starts_on', { mode: 'string' })
      .notNull()
      .references(() => leagueWeeks.startsOn),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    groupId: uuid('group_id')
      .notNull()
      .references(() => leagueGroups.id),
    division: smallint('division').notNull(),
    joinedAt: ts('joined_at').notNull().defaultNow(),
    leftAt: ts('left_at'),
    /** Nightly snapshot (earned days starts_on..yesterday). */
    snapshotPoints: integer('snapshot_points'),
    snapshotRank: smallint('snapshot_rank'),
    finalPoints: integer('final_points'),
    finalRank: smallint('final_rank'),
    outcome: text('outcome'),
  },
  (t) => [
    primaryKey({ columns: [t.startsOn, t.userId] }),
    index('league_members_group_rank_idx').on(t.groupId, t.snapshotRank),
    check('league_members_division_ck', sql`${t.division} between 1 and 6`),
    check('league_members_outcome_ck', sql`${t.outcome} in ('up', 'stay', 'down')`),
  ],
);

/** Admin seasonal tournaments: windows of whole Cairo days (instants are Cairo 00:00; ends/join exclusive). */
export const tournaments = pgTable(
  'tournaments',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    slug: text('slug').notNull(),
    titleAr: text('title_ar').notNull(),
    titleEn: text('title_en').notNull(),
    bodyAr: text('body_ar').notNull().default(''),
    bodyEn: text('body_en').notNull().default(''),
    startsAt: ts('starts_at').notNull(),
    endsAt: ts('ends_at').notNull(),
    joinUntil: ts('join_until').notNull(),
    badgeAr: text('badge_ar').notNull(),
    badgeEn: text('badge_en').notNull(),
    minPoints: integer('min_points').notNull().default(1),
    status: text('status').notNull().default('draft'),
    finalizingAt: ts('finalizing_at'),
    closedAt: ts('closed_at'),
    createdBy: uuid('created_by').references(() => adminUsers.id),
    createdAt: createdAt(),
    updatedAt: updatedAt(),
  },
  (t) => [
    uniqueIndex('tournaments_slug_uq').on(t.slug),
    check('tournaments_slug_ck', sql`${t.slug} ~ '^[a-z0-9-]{3,40}$'`),
    check('tournaments_titles_ck', sql`char_length(${t.titleAr}) <= 60 and char_length(${t.titleEn}) <= 60`),
    check('tournaments_bodies_ck', sql`char_length(${t.bodyAr}) <= 280 and char_length(${t.bodyEn}) <= 280`),
    check('tournaments_badges_ck', sql`char_length(${t.badgeAr}) <= 40 and char_length(${t.badgeEn}) <= 40`),
    check('tournaments_status_ck', sql`${t.status} in ('draft', 'published', 'cancelled')`),
    check('tournaments_window_ck', sql`${t.startsAt} < ${t.endsAt} and ${t.joinUntil} <= ${t.endsAt}`),
    check('tournaments_window_len_ck', sql`${t.endsAt} - ${t.startsAt} <= interval '90 days'`),
    check('tournaments_min_points_ck', sql`${t.minPoints} >= 1`),
  ],
);

export const tournamentEntries = pgTable(
  'tournament_entries',
  {
    tournamentId: uuid('tournament_id')
      .notNull()
      .references(() => tournaments.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    joinedAt: ts('joined_at').notNull().defaultNow(),
    leftAt: ts('left_at'),
    snapshotPoints: integer('snapshot_points'),
    snapshotRank: integer('snapshot_rank'),
    finalPoints: integer('final_points'),
    finalRank: integer('final_rank'),
  },
  (t) => [
    primaryKey({ columns: [t.tournamentId, t.userId] }),
    index('tournament_entries_snapshot_idx').on(t.tournamentId, t.snapshotRank),
    index('tournament_entries_final_idx').on(t.tournamentId, t.finalRank),
  ],
);

/** Level board ranks (nightly). `country` is '' for the global scope. */
export const leaderboardSnapshot = pgTable(
  'leaderboard_snapshot',
  {
    scope: text('scope').notNull(),
    country: text('country').notNull().default(''),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    rank: integer('rank').notNull(),
    lifetime: integer('lifetime').notNull(),
    day: date('day', { mode: 'string' }).notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.scope, t.country, t.userId] }),
    index('leaderboard_snapshot_rank_idx').on(t.scope, t.country, t.rank),
    check('leaderboard_snapshot_scope_ck', sql`${t.scope} in ('global', 'country')`),
  ],
);

/** Marks that the nightly snapshot for that Cairo day ran. */
export const communitySnapshotDays = pgTable('community_snapshot_days', {
  day: date('day', { mode: 'string' }).primaryKey(),
  takenAt: ts('taken_at').notNull().defaultNow(),
});

/**
 * Append-only badges (contracts `BADGE_KINDS`; streak and level badges stay derived). Unique
 * `(user_id, ref_key)`: `league:<startsOn>`, `division:<n>`, `tournament:<id>`. Never points.
 */
export const userBadges = pgTable(
  'user_badges',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    kind: text('kind').notNull(),
    refKey: text('ref_key').notNull(),
    /** {startsOn?, division?, rank?, size?, tournamentId?, titleAr?, titleEn?, labelAr?, labelEn?} */
    meta: jsonb('meta').notNull().default({}),
    awardedAt: ts('awarded_at').notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('user_badges_user_ref_uq').on(t.userId, t.refKey),
    check(
      'user_badges_kind_ck',
      sql`${t.kind} in ('league_first','league_top3','league_promoted','division_reached','tournament_podium','tournament_top10','tournament_finisher')`,
    ),
  ],
);

/** Reports of a competitor's name or photo (support queue). 20 per reporter per rolling 24 h, counted here. */
export const communityReports = pgTable(
  'community_reports',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    reporterId: uuid('reporter_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    targetUserId: uuid('target_user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    reason: text('reason').notNull(),
    createdAt: createdAt(),
    resolvedAt: ts('resolved_at'),
    resolvedBy: uuid('resolved_by').references(() => adminUsers.id),
    resolution: text('resolution'),
  },
  (t) => [
    uniqueIndex('community_reports_open_uq').on(t.reporterId, t.targetUserId).where(sql`${t.resolvedAt} is null`),
    index('community_reports_reporter_idx').on(t.reporterId, t.createdAt.desc()),
    check('community_reports_reason_ck', sql`${t.reason} in ('name', 'photo', 'other')`),
    check('community_reports_resolution_ck', sql`${t.resolution} in ('dismissed', 'actioned')`),
  ],
);

/* ------------------------------------------------------- «تلاواتي» recordings */
/*
 * Users' own recorded recitations (design doc §16, APP_SPEC §5.24/§5.31). User-generated content in
 * the owner's own voice — not Yaqeen's religious content. Never in analytics or ad sinks; admins see a
 * recording only while it is in the moderation queue (needs_review, or reported/held). The audio is
 * stored as uploaded (AAC-LC .m4a, ≤ 200 KB) — Postgres like avatar photos, no storage service.
 * `transcript`, `client_score` and `client_words` exist only while the recording waits for a reviewer.
 */

export const recordings = pgTable(
  'recordings',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    surah: smallint('surah').notNull(),
    fromAyah: smallint('from_ayah').notNull(),
    toAyah: smallint('to_ayah').notNull(),
    durationMs: integer('duration_ms').notNull(),
    audio: bytea('audio').notNull(),
    bytes: integer('bytes').notNull(),
    /** contracts `RecordingStatus`. */
    status: text('status').notNull(),
    rejectReason: text('reject_reason'),
    /** Coverage of the chosen verses (AI check), 0..1. */
    score: real('score'),
    /** Speech ÷ duration (VAD), 0..1. */
    speech: real('speech'),
    /** Karaoke timings `[{ayah, index, startMs, endMs}]`, set once verified. */
    words: jsonb('words'),
    visibility: text('visibility').notNull().default('private'),
    commentsOn: boolean('comments_on').notNull().default(true),
    position: smallint('position').notNull(),
    /** Failed AI-check attempts (the sweeper gives up after 3 → needs_review). */
    asrAttempts: smallint('asr_attempts').notNull().default(0),
    /** When the recording entered `processing` (the sweeper retries after 10 min). */
    queuedAt: ts('queued_at'),
    /** Queue-only diagnostics, dropped when a reviewer decides. */
    transcript: text('transcript'),
    clientScore: real('client_score'),
    clientWords: jsonb('client_words'),
    /** 3 distinct open reports hold an approved recording out of every view until support decides. */
    heldAt: ts('held_at'),
    createdAt: createdAt(),
    verifiedAt: ts('verified_at'),
    removedAt: ts('removed_at'),
  },
  (t) => [
    index('recordings_user_idx').on(t.userId, t.position),
    index('recordings_queue_idx').on(t.status, t.createdAt),
    check('recordings_status_ck', sql`${t.status} in ('processing', 'private_ready', 'approved', 'needs_review', 'rejected', 'removed')`),
    check('recordings_reject_reason_ck', sql`${t.rejectReason} in ('not_matching', 'unclear', 'silence', 'too_long', 'removed_by_moderator')`),
    check('recordings_visibility_ck', sql`${t.visibility} in ('private', 'members', 'public')`),
    check('recordings_range_ck', sql`${t.surah} between 1 and 114 and ${t.fromAyah} >= 1 and ${t.fromAyah} <= ${t.toAyah}`),
    check('recordings_duration_ck', sql`${t.durationMs} between 0 and 31000`),
    check('recordings_bytes_ck', sql`${t.bytes} <= 200000`),
    check('recordings_position_ck', sql`${t.position} between 1 and 3`),
  ],
);

/** One reaction per viewer per recording (contracts `REACTION_KINDS`). */
export const recordingReactions = pgTable(
  'recording_reactions',
  {
    recordingId: uuid('recording_id')
      .notNull()
      .references(() => recordings.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    kind: text('kind').notNull(),
    createdAt: createdAt(),
  },
  (t) => [
    primaryKey({ columns: [t.recordingId, t.userId] }),
    index('recording_reactions_user_idx').on(t.userId),
    check('recording_reactions_kind_ck', sql`${t.kind} in ('mashallah', 'barakallah', 'ahsant')`),
  ],
);

/** Comments. `hidden`: 3 reports (pending support); `removed`: author, owner or support (text wiped). */
export const recordingComments = pgTable(
  'recording_comments',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    recordingId: uuid('recording_id')
      .notNull()
      .references(() => recordings.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    text: text('text').notNull(),
    status: text('status').notNull().default('visible'),
    createdAt: createdAt(),
    removedAt: ts('removed_at'),
  },
  (t) => [
    index('recording_comments_list_idx').on(t.recordingId, t.createdAt.desc(), t.id),
    // Also serves the 5/min and 50/day rate limits, counted in the database.
    index('recording_comments_user_idx').on(t.userId, t.createdAt.desc()),
    check('recording_comments_status_ck', sql`${t.status} in ('visible', 'hidden', 'removed')`),
    check('recording_comments_text_ck', sql`char_length(${t.text}) <= 280`),
  ],
);

/** Reports of a recording or a comment; one report per reporter and target. */
export const recordingReports = pgTable(
  'recording_reports',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    target: text('target').notNull(),
    targetId: uuid('target_id').notNull(),
    reporterId: uuid('reporter_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    reason: text('reason').notNull(),
    createdAt: createdAt(),
    resolvedAt: ts('resolved_at'),
    resolvedBy: uuid('resolved_by').references(() => adminUsers.id),
    resolution: text('resolution'),
  },
  (t) => [
    uniqueIndex('recording_reports_uq').on(t.target, t.targetId, t.reporterId),
    index('recording_reports_open_idx').on(t.target, t.targetId).where(sql`${t.resolvedAt} is null`),
    index('recording_reports_reporter_idx').on(t.reporterId, t.createdAt.desc()),
    check('recording_reports_target_ck', sql`${t.target} in ('recording', 'comment')`),
    check('recording_reports_reason_ck', sql`${t.reason} in ('not_recitation', 'inappropriate', 'spam', 'other')`),
    check('recording_reports_resolution_ck', sql`${t.resolution} in ('dismissed', 'actioned')`),
  ],
);

/** Uploads + share-verifications per Africa/Cairo day (contracts `RECORDING_UPLOADS_PER_DAY`); survives deletes. */
export const recordingDaily = pgTable(
  'recording_daily',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    day: date('day', { mode: 'string' }).notNull(),
    count: smallint('count').notNull().default(0),
  },
  (t) => [primaryKey({ columns: [t.userId, t.day] })],
);
