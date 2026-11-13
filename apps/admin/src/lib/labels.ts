import type { AdminUserRow, ContentStatus } from '@yaqeen/contracts';

export const USER_STATUS: Record<AdminUserRow['status'], { label: string; tone: 'green' | 'red' | 'gold' | 'gray' }> = {
  active: { label: 'نشط', tone: 'green' },
  suspended: { label: 'موقوف', tone: 'red' },
  under_review: { label: 'قيد المراجعة', tone: 'gold' },
  deletion_requested: { label: 'طلب حذف', tone: 'gray' },
  deleted: { label: 'محذوف', tone: 'gray' },
};

export const CONTENT_STATUS: Record<ContentStatus, { label: string; tone: 'green' | 'red' | 'gold' | 'gray' | 'blue' }> = {
  draft: { label: 'مسودة', tone: 'gray' },
  pending_review: { label: 'بانتظار المراجعة', tone: 'gold' },
  changes_requested: { label: 'مطلوب تعديل', tone: 'red' },
  published: { label: 'منشور', tone: 'green' },
};

/* -------------------------------------------------------------- competitions */

/** Stable API codes of the competitions endpoints → what the admin reads (design §3.4). */
export const COMPETITION_ERROR: Record<string, string> = {
  tournament_dates: 'تواريخ غير صالحة — الأيام كاملة بتوقيت القاهرة',
  slug_taken: 'المعرّف مستخدم',
  tournament_not_editable: 'لا يمكن تعديل هذه البطولة الآن',
  tournament_closed: 'انتهت البطولة',
  settings_invalid: 'إعدادات غير صالحة',
  nothing_to_restore: 'لا شيء لاستعادته',
  reason_required: 'اكتب السبب',
  report_resolved: 'عولج هذا البلاغ من قبل',
  role_not_allowed: 'لا تملك صلاحية هذا الإجراء',
  validation: 'تحقق من الحقول',
  not_found: 'غير موجود',
};

/** What the admin sees for a tournament: its stored status, or the phase of a published one. */
export type TournamentDisplay = 'draft' | 'upcoming' | 'live' | 'ended' | 'cancelled';

export const TOURNAMENT_STATUS: Record<TournamentDisplay, { label: string; tone: 'green' | 'red' | 'gray' | 'blue' }> = {
  draft: { label: 'مسودة', tone: 'gray' },
  upcoming: { label: 'مجدولة', tone: 'blue' },
  live: { label: 'جارية', tone: 'green' },
  ended: { label: 'منتهية', tone: 'gray' },
  cancelled: { label: 'ملغاة', tone: 'red' },
};

export function tournamentDisplay(t: { status: 'draft' | 'published' | 'cancelled'; phase: 'upcoming' | 'live' | 'ended'; closed: boolean }): TournamentDisplay {
  if (t.status === 'cancelled') return 'cancelled';
  if (t.status === 'draft') return 'draft';
  return t.closed ? 'ended' : t.phase;
}

/**
 * Division names when the league settings carry none. Division marks stay monochrome: «ذهب» is a
 * name, never gold styling (gold is for achievement only).
 */
export const DIVISION: Record<number, string> = { 1: 'برونز', 2: 'فضة', 3: 'ذهب', 4: 'زمرّد', 5: 'ياقوت', 6: 'ألماس' };

export const divisionName = (id: number, names?: { ar: string }[] | null) => names?.[id - 1]?.ar || DIVISION[id] || String(id);

export const BADGE_LABEL: Record<string, { label: string; hint: string }> = {
  streak: { label: 'مواظبة', hint: 'أيام متتالية في التحدي (من سجل النقاط)' },
  level: { label: 'مستوى جديد', hint: 'بلوغ مستوى أعلى من النقاط المكتسبة' },
  league_first: { label: 'الأول في المجموعة', hint: 'المركز الأول في أسبوع الدوري (5 أعضاء فأكثر)' },
  league_top3: { label: 'من الثلاثة الأوائل', hint: 'المراكز 1–3 في أسبوع الدوري' },
  league_promoted: { label: 'صعود', hint: 'الصعود إلى قسم أعلى في نهاية الأسبوع' },
  division_reached: { label: 'بلوغ قسم', hint: 'أول وصول إلى قسم (من الفضة فما فوق)' },
  tournament_podium: { label: 'منصة البطولة', hint: 'المراكز 1–3 في بطولة من 10 مشاركين فأكثر' },
  tournament_top10: { label: 'العُشر الأول', hint: 'أعلى 10% في بطولة من 10 مشاركين فأكثر' },
  tournament_finisher: { label: 'أتمّ البطولة', hint: 'بلغ الحد الأدنى من النقاط في البطولة' },
};

export const REPORT_REASON: Record<'name' | 'photo' | 'other', string> = { name: 'الاسم', photo: 'الصورة', other: 'سبب آخر' };
