import { z } from 'zod';

/** Admin roles. Every admin endpoint declares which of these may call it. */
export const AdminRole = z.enum(['super_admin', 'content_editor', 'religious_reviewer', 'marketing', 'support']);
export type AdminRole = z.infer<typeof AdminRole>;

export const AuthProvider = z.enum(['google', 'apple', 'guest']);
export type AuthProvider = z.infer<typeof AuthProvider>;

export const UserStatus = z.enum(['active', 'suspended', 'under_review', 'deletion_requested', 'deleted']);
export type UserStatus = z.infer<typeof UserStatus>;

/**
 * Consent buckets, recorded separately (Egypt PDPL 151/2020 requires explicit,
 * specific, revocable consent with records).
 */
export const ConsentKind = z.enum(['worship_reminders', 'challenge_rewards', 'store_offers', 'ads_measurement']);
export type ConsentKind = z.infer<typeof ConsentKind>;

/** The six daily challenge tasks. Point values live in the database (admin-editable). */
export const TaskKey = z.enum(['wird', 'morning_azkar', 'five_prayers', 'evening_azkar', 'listen', 'daily_task']);
export type TaskKey = z.infer<typeof TaskKey>;

export const BonusKind = z.enum(['white_days_fast', 'mon_thu_fast', 'friday_kahf']);
export type BonusKind = z.infer<typeof BonusKind>;

export const DayStatus = z.enum(['done', 'partial', 'qada', 'missed', 'today', 'future']);
export type DayStatus = z.infer<typeof DayStatus>;

export const LedgerReason = z.enum(['task', 'bonus', 'milestone', 'grant', 'qada', 'redemption', 'admin_adjustment', 'reversal']);
export type LedgerReason = z.infer<typeof LedgerReason>;

/** `splash_verse` goes through the same review workflow but is served via /v1/config, not /v1/content. */
export const ContentType = z.enum(['dua', 'zikr', 'splash_verse']);
export type ContentType = z.infer<typeof ContentType>;

export const ContentStatus = z.enum(['draft', 'pending_review', 'changes_requested', 'published']);
export type ContentStatus = z.infer<typeof ContentStatus>;

export const RewardKind = z.enum(['fixed_amount', 'percentage', 'free_shipping']);
export type RewardKind = z.infer<typeof RewardKind>;

export const RedemptionStatus = z.enum(['issued', 'used', 'expired', 'void']);
export type RedemptionStatus = z.infer<typeof RedemptionStatus>;

export const CampaignKind = z.enum(['challenge', 'rewards', 'offers']);
export type CampaignKind = z.infer<typeof CampaignKind>;

export const CampaignSegment = z.enum(['all', 'balance_gte_1000', 'missed_yesterday', 'streak_gte_7', 'inactive_7d']);
export type CampaignSegment = z.infer<typeof CampaignSegment>;

export const CampaignSchedule = z.enum(['now', 'smart', 'scheduled']);
export type CampaignSchedule = z.infer<typeof CampaignSchedule>;

export const DeepLink = z.enum(['home', 'challenge', 'calendar', 'redeem', 'store', 'quran', 'prayer', 'azkar', 'hifz']);
export type DeepLink = z.infer<typeof DeepLink>;

export const Platform = z.enum(['ios', 'android']);
export type Platform = z.infer<typeof Platform>;

export const PrayerMethod = z.enum(['egypt', 'mwl', 'umm_al_qura']);
export type PrayerMethod = z.infer<typeof PrayerMethod>;

export const AsrSchool = z.enum(['standard', 'hanafi']);
export type AsrSchool = z.infer<typeof AsrSchool>;

export const PackKind = z.enum(['tafsir', 'font', 'audio', 'translation']);
export type PackKind = z.infer<typeof PackKind>;

/** Feature flags the app reads from /v1/config. Unknown keys are ignored by the app. */
export const FEATURE_FLAGS = ['challenge', 'rewards', 'hifz', 'listen', 'bonuses', 'recite', 'ramadan', 'tafsirFull'] as const;
export type FeatureFlag = (typeof FEATURE_FLAGS)[number];
