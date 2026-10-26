import { z } from 'zod';

/**
 * Public profile («بطاقة يقين») — an opt-in card a user can put on an NFC tag or a QR code.
 *
 * Privacy (CLAUDE.md non-negotiables 1–2): it is off until the user publishes it, shows only the
 * fields they switch on, and never carries worship detail — no prayers, azkar, pages or tasks.
 * Activity is limited to the level (from lifetime points), the streak length, the challenge day
 * and streak-milestone badges.
 */

/** Lower-case latin letters, digits, `_` and `.`, 3–24 chars, starting with a letter. */
export const PROFILE_HANDLE = /^[a-z][a-z0-9_.]{2,23}$/;
export const Handle = z
  .string()
  .transform((s) => s.trim().toLowerCase())
  .pipe(z.string().regex(PROFILE_HANDLE));

/** Handles that would read as official or collide with routes. */
export const RESERVED_HANDLES = new Set([
  'admin', 'api', 'app', 'apps', 'assets', 'help', 'support', 'yaqeen', 'yaqin', 'yaqinbrand', 'official', 'store', 'shop',
  'login', 'signup', 'settings', 'profile', 'me', 'u', 'www', 'about', 'privacy', 'terms', 'null', 'undefined',
]);

export const SOCIAL_KINDS = ['instagram', 'x', 'tiktok', 'facebook', 'youtube', 'snapchat', 'linkedin', 'whatsapp', 'website'] as const;
export const SocialKind = z.enum(SOCIAL_KINDS);
export type SocialKind = z.infer<typeof SocialKind>;

/** A username for the platform (or a full https URL; a phone number for WhatsApp). */
export const SocialLink = z.object({
  kind: SocialKind,
  value: z.string().trim().min(1).max(120),
});
export type SocialLink = z.infer<typeof SocialLink>;

export const ProfileTheme = z.enum(['sky', 'gold', 'night']);
export type ProfileTheme = z.infer<typeof ProfileTheme>;

/** What the owner chose to show. Everything starts off except the name. */
export const ProfileVisibility = z.object({
  level: z.boolean().default(true),
  streak: z.boolean().default(false),
  challengeDay: z.boolean().default(false),
  badges: z.boolean().default(false),
  memberSince: z.boolean().default(false),
  /** The dated journey: joined, levels reached, streak badges, challenge milestones. */
  timeline: z.boolean().default(false),
});
export type ProfileVisibility = z.infer<typeof ProfileVisibility>;

/** PUT /v1/me/public-profile. */
export const PublicProfileUpdate = z.object({
  published: z.boolean(),
  handle: Handle,
  displayName: z.string().trim().min(1).max(40),
  bio: z.string().trim().max(160).default(''),
  links: z.array(SocialLink).max(8).default([]),
  show: ProfileVisibility.default({ level: true, streak: false, challengeDay: false, badges: false, memberSince: false, timeline: false }),
  theme: ProfileTheme.default('sky'),
});
export type PublicProfileUpdate = z.infer<typeof PublicProfileUpdate>;

/** GET /v1/me/public-profile — the owner's settings plus the shareable URL and scan count. */
export const PublicProfileSettings = PublicProfileUpdate.extend({
  url: z.string().url(),
  views: z.number().int(),
  /** Hidden by Yaqeen support (audited); the owner can't publish until it is restored. */
  moderated: z.boolean().default(false),
});
export type PublicProfileSettings = z.infer<typeof PublicProfileSettings>;

/* ------------------------------------------------------------------ levels */

/**
 * Levels earned from **lifetime** points (sum of positive ledger rows), so spending points on a
 * reward never lowers a level. Names describe the journey, not anyone's faith.
 */
export const LEVELS = [
  { min: 0, ar: 'بداية الطريق', en: 'Setting out' },
  { min: 500, ar: 'على الطريق', en: 'On the path' },
  { min: 2000, ar: 'مواظب', en: 'Steadfast' },
  { min: 5000, ar: 'ثابت', en: 'Unwavering' },
  { min: 12000, ar: 'راسخ', en: 'Rooted' },
  { min: 25000, ar: 'منارة', en: 'Beacon' },
] as const;

export interface LevelInfo {
  /** 1-based. */
  level: number;
  nameAr: string;
  nameEn: string;
  /** 0…1 toward the next level (1 at the top level). */
  progress: number;
  /** Lifetime points needed for the next level; null at the top. */
  nextAt: number | null;
}

export function levelFor(lifetimePoints: number): LevelInfo {
  const pts = Math.max(0, Math.floor(lifetimePoints));
  let i = 0;
  while (i + 1 < LEVELS.length && pts >= LEVELS[i + 1]!.min) i++;
  const cur = LEVELS[i]!;
  const next = LEVELS[i + 1];
  return {
    level: i + 1,
    nameAr: cur.ar,
    nameEn: cur.en,
    progress: next ? (pts - cur.min) / (next.min - cur.min) : 1,
    nextAt: next ? next.min : null,
  };
}

export const PublicLevel = z.object({
  level: z.number().int(),
  nameAr: z.string(),
  nameEn: z.string(),
  progress: z.number(),
});

/** GET /v1/public/profiles/:handle — exactly what a scanner may see. */
export const PublicProfileView = z.object({
  handle: z.string(),
  displayName: z.string(),
  bio: z.string(),
  links: z.array(SocialLink),
  theme: ProfileTheme,
  level: PublicLevel.nullable(),
  streak: z.number().int().nullable(),
  challengeDay: z.object({ day: z.number().int(), of: z.number().int() }).nullable(),
  /** Streak milestones reached, in days (e.g. [7, 30]). */
  badges: z.array(z.number().int()).nullable(),
  memberSince: z.string().nullable(),
  /** Newest first, at most 12 — only when the owner switched it on. */
  timeline: z.array(z.lazy(() => JourneyEvent)).nullable(),
});
export type PublicProfileView = z.infer<typeof PublicProfileView>;

/** The link a social kind opens; `value` may be a username or a full URL. */
export function socialUrl(link: SocialLink): string | null {
  const v = link.value.trim();
  if (/^https:\/\//i.test(v)) return v;
  if (/^[a-z][a-z0-9+.-]*:/i.test(v)) return null; // http:, javascript:, data: … never
  const user = v.replace(/^@/, '').replace(/[^\w.\-]/g, '');
  switch (link.kind) {
    case 'instagram':
      return user ? `https://instagram.com/${user}` : null;
    case 'x':
      return user ? `https://x.com/${user}` : null;
    case 'tiktok':
      return user ? `https://www.tiktok.com/@${user}` : null;
    case 'facebook':
      return user ? `https://facebook.com/${user}` : null;
    case 'youtube':
      return user ? `https://www.youtube.com/@${user}` : null;
    case 'snapchat':
      return user ? `https://www.snapchat.com/add/${user}` : null;
    case 'linkedin':
      return user ? `https://www.linkedin.com/in/${user}` : null;
    case 'whatsapp': {
      const phone = v.replace(/[^\d]/g, '');
      return phone.length >= 8 ? `https://wa.me/${phone}` : null;
    }
    case 'website':
      return /^[\w.-]+\.[a-z]{2,}(\/.*)?$/i.test(v) ? `https://${v}` : null;
  }
}

/* ---------------------------------------------------------------- journey */

/**
 * One milestone of the user's Yaqeen journey. Never a worship act: joining, levels (from points),
 * streak badges and challenge days — the same facts the card can already show, with their dates.
 */
export const JourneyEventKind = z.enum(['joined', 'challenge_start', 'challenge_day', 'level', 'badge']);
export type JourneyEventKind = z.infer<typeof JourneyEventKind>;

export const JourneyEvent = z.object({
  kind: JourneyEventKind,
  /** YYYY-MM-DD. */
  date: z.string(),
  /** Level number, badge days or challenge day; null for joined / challenge_start. */
  value: z.number().int().nullable(),
});
export type JourneyEvent = z.infer<typeof JourneyEvent>;

/** GET /v1/me/journey — the owner's own journey (Profile tab). */
export const MyJourney = z.object({
  lifetimePoints: z.number().int(),
  level: PublicLevel.extend({ nextAt: z.number().int().nullable() }),
  streak: z.number().int(),
  challengeDay: z.number().int().nullable(),
  challengeOf: z.number().int(),
  events: z.array(JourneyEvent),
});
export type MyJourney = z.infer<typeof MyJourney>;

/** Challenge days that become journey milestones. */
export const JOURNEY_DAYS = [30, 100, 200, 300, 365] as const;

/* ------------------------------------------------------------ medal / card tags */

/**
 * Physical «بطاقة يقين» tags (key medals, cards) carry a permanent code link `/t/<code>` in their
 * NFC chip and printed QR. The owner activates the code in the app; handle changes never break it,
 * and a lost tag can be switched off. Codes avoid look-alikes (no 0/O, 1/I).
 */
export const TAG_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
export const TAG_CODE_LENGTH = 8;
export const TAG_LIMIT_PER_USER = 10;

/** "ab12-cd34 " → "AB12CD34" (what users type from the print, or a scanned URL). */
export function normalizeTagCode(raw: string): string {
  const s = raw.trim();
  const fromUrl = /\/t\/([^/?#]+)/i.exec(s)?.[1] ?? s;
  return fromUrl.toUpperCase().replace(/[^0-9A-Z]/g, '');
}

/** "AB12CD34" → "AB12-CD34" for print and display. */
export const formatTagCode = (code: string) => `${code.slice(0, 4)}-${code.slice(4)}`;

export const TagCode = z
  .string()
  .max(200)
  .transform(normalizeTagCode)
  .pipe(z.string().regex(new RegExp(`^[${TAG_ALPHABET}]{${TAG_CODE_LENGTH}}$`), 'invalid tag code'));

export const TagKind = z.enum(['medal', 'card']);
export type TagKind = z.infer<typeof TagKind>;

/** GET /v1/me/tags — the owner's active tags. */
export const ProfileTag = z.object({
  code: z.string(),
  kind: TagKind,
  url: z.string(),
  linkedAt: z.string(),
  scans: z.number().int(),
});
export type ProfileTag = z.infer<typeof ProfileTag>;

/** POST /v1/me/tags */
export const ClaimTagRequest = z.object({ code: TagCode });

/** POST /admin/tags/batches — mint codes for the manufacturer. */
export const AdminTagBatchRequest = z.object({
  batch: z
    .string()
    .trim()
    .regex(/^[A-Za-z0-9_-]{1,40}$/, 'letters, digits, - and _'),
  kind: TagKind,
  count: z.number().int().min(1).max(5000),
});

export const TagStatus = z.enum(['unclaimed', 'active', 'disabled']);
export type TagStatus = z.infer<typeof TagStatus>;

export const AdminTagRow = z.object({
  code: z.string(),
  kind: TagKind,
  batch: z.string(),
  status: TagStatus,
  /** The linked card's handle (never worship data). */
  handle: z.string().nullable(),
  userId: z.string().nullable(),
  scans: z.number().int(),
  createdAt: z.string(),
  linkedAt: z.string().nullable(),
});
export type AdminTagRow = z.infer<typeof AdminTagRow>;

export const TagBatchStatus = z.enum(['ordered', 'received', 'on_sale', 'void']);
export type TagBatchStatus = z.infer<typeof TagBatchStatus>;

export const AdminTagBatch = z.object({
  batch: z.string(),
  kind: TagKind,
  status: TagBatchStatus,
  note: z.string(),
  total: z.number().int(),
  active: z.number().int(),
  disabled: z.number().int(),
  createdAt: z.string(),
});
export type AdminTagBatch = z.infer<typeof AdminTagBatch>;

/** PATCH /admin/tags/batches/:batch — production status and a note (void has its own route). */
export const AdminTagBatchPatch = z.object({
  status: TagBatchStatus.exclude(['void']).optional(),
  note: z.string().trim().max(500).optional(),
});

/** POST /admin/tags/:code/assign — support links a blank tag for a customer. */
export const AdminAssignTag = z.object({
  userId: z.string().uuid(),
  reason: z.string().trim().min(3).max(500),
});

/* ------------------------------------------------------------ admin: cards programme */

const httpsOrEmpty = z
  .string()
  .trim()
  .max(500)
  .refine((v) => v === '' || /^https:\/\/[^\s]+$/i.test(v), 'https link');

/** Admin-editable settings for public cards and medals (`app_config` key `cards`). Empty = default. */
export const CardsSettings = z.object({
  /** The medal / card product in the Yaqeen store (the app's «get a medal» link). */
  medalProductUrl: httpsOrEmpty.default(''),
  /** Where the card page's «shop» button goes. */
  storeUrl: httpsOrEmpty.default(''),
  ctaTitleAr: z.string().trim().max(80).default(''),
  ctaTitleEn: z.string().trim().max(80).default(''),
  ctaBodyAr: z.string().trim().max(300).default(''),
  ctaBodyEn: z.string().trim().max(300).default(''),
  /** Handles nobody may take, on top of `RESERVED_HANDLES` (brands, staff, look-alikes). */
  reservedHandles: z
    .array(z.string().trim().toLowerCase().regex(PROFILE_HANDLE, 'handle format'))
    .max(500)
    .default([]),
});
export type CardsSettings = z.infer<typeof CardsSettings>;

export const AdminCardRow = z.object({
  userId: z.string(),
  handle: z.string(),
  displayName: z.string(),
  bio: z.string(),
  url: z.string(),
  published: z.boolean(),
  moderated: z.boolean(),
  moderationReason: z.string().nullable(),
  views: z.number().int(),
  tags: z.number().int(),
  updatedAt: z.string(),
});
export type AdminCardRow = z.infer<typeof AdminCardRow>;

export const AdminReason = z.object({ reason: z.string().trim().min(3).max(500) });

/** Daily counters only — no visitor, user or handle data. */
export const CARD_METRICS = ['page_open', 'tag_scan', 'activation_open', 'get_app', 'store_click', 'card_published', 'tag_activated'] as const;
export const CardMetric = z.enum(CARD_METRICS);
export type CardMetric = z.infer<typeof CardMetric>;

export const CardsStats = z.object({
  days: z.number().int(),
  /** Last day of the range (today in Africa/Cairo); the series runs `days` days up to it. */
  to: z.string(),
  totals: z.record(CardMetric, z.number().int()),
  publishedCards: z.number().int(),
  activeTags: z.number().int(),
  series: z.array(z.object({ date: z.string(), metric: CardMetric, value: z.number().int() })),
  activationsByBatch: z.array(z.object({ batch: z.string(), total: z.number().int(), active: z.number().int() })),
});
export type CardsStats = z.infer<typeof CardsStats>;
