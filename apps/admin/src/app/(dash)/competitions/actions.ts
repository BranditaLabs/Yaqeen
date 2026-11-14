'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { AdminTournamentBase, AdminTournamentCreate, AdminTournamentPatch, CompetitorAction, LeagueSettings, ResolveReport, type AdminTournamentRow } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';
import { COMPETITION_ERROR } from '@/lib/labels';

export type S = { error: string | null; ok?: boolean };

const CODE = COMPETITION_ERROR;

const fail = (r: { error: string | null; code: string | null }): S => ({ error: (r.code && CODE[r.code]) || r.error || 'تعذّر الحفظ' });

/** The audit reason every write carries (AdminReason: 3–500 characters). */
function reasonOf(form: FormData): { success: true; data: string } | { success: false } {
  const reason = String(form.get('reason') ?? '').trim();
  return reason.length >= 3 && reason.length <= 500 ? { success: true, data: reason } : { success: false };
}

/** POST {reason} to an audited admin endpoint (the cards/actions.ts pattern). */
async function act(path: string, form: FormData, revalidate: string[]): Promise<S> {
  const reason = reasonOf(form);
  if (!reason.success) return { error: CODE.reason_required! };
  const r = await tryApi(path, { method: 'POST', body: { reason: reason.data } });
  if (r.error) return fail(r);
  for (const p of revalidate) revalidatePath(p);
  return { error: null, ok: true };
}

/* ------------------------------------------------------------ tournaments */

const text = (form: FormData, k: string) => String(form.get(k) ?? '').trim();

function tournamentFields(form: FormData) {
  return {
    slug: text(form, 'slug'),
    titleAr: text(form, 'titleAr'),
    titleEn: text(form, 'titleEn'),
    bodyAr: text(form, 'bodyAr'),
    bodyEn: text(form, 'bodyEn'),
    startsOn: text(form, 'startsOn'),
    lastDay: text(form, 'lastDay'),
    joinLastDay: text(form, 'joinLastDay') || undefined,
    badgeAr: text(form, 'badgeAr'),
    badgeEn: text(form, 'badgeEn'),
    minPoints: Number(text(form, 'minPoints') || '1'),
  };
}

function fieldError(issues: readonly { path: readonly PropertyKey[] }[]): string {
  const where = String(issues[0]?.path[0] ?? '');
  if (where === 'slug') return 'المعرّف: حروف لاتينية صغيرة وأرقام و - (3–40)';
  if (['startsOn', 'lastDay', 'joinLastDay'].includes(where)) return CODE.tournament_dates!;
  if (where === 'minPoints') return 'الحد الأدنى للنقاط من 1 إلى 100,000';
  return 'أكمل العنوان والشارة بالعربية والإنجليزية';
}

/** New tournament: save as a draft, or save and publish (intent). */
export async function createTournament(_prev: S, form: FormData): Promise<S> {
  const parsed = AdminTournamentCreate.safeParse(tournamentFields(form));
  if (!parsed.success) return { error: fieldError(parsed.error.issues) };
  const created = await tryApi<AdminTournamentRow>('/admin/competitions/tournaments', { method: 'POST', body: parsed.data });
  if (created.error || !created.data) return fail(created);
  if (form.get('intent') === 'publish') {
    const pub = await tryApi(`/admin/competitions/tournaments/${created.data.id}/publish`, { method: 'POST' });
    if (pub.error) {
      // The draft exists now: continue from it (a second press here would only hit slug_taken).
      revalidatePath('/competitions');
      redirect(`/competitions/tournaments/${created.data.id}?publishError=${encodeURIComponent(pub.code ?? 'error')}`);
    }
  }
  revalidatePath('/competitions');
  redirect(`/competitions/tournaments/${created.data.id}`);
}

/**
 * Edit: a draft changes any field; a published one before its start any field but the slug; a live
 * one only a later last day, with a reason (the API enforces all three). `mode` says which.
 */
export async function updateTournament(id: string, mode: 'draft' | 'scheduled' | 'live', _prev: S, form: FormData): Promise<S> {
  let body: AdminTournamentPatch;
  if (mode === 'live') {
    const lastDay = AdminTournamentBase.shape.lastDay.safeParse(text(form, 'lastDay'));
    if (!lastDay.success) return { error: CODE.tournament_dates! };
    const reason = reasonOf(form);
    if (!reason.success) return { error: CODE.reason_required! };
    body = { lastDay: lastDay.data, reason: reason.data };
  } else {
    const parsed = AdminTournamentCreate.safeParse(tournamentFields(form));
    if (!parsed.success) return { error: fieldError(parsed.error.issues) };
    // A blank «آخر يوم للانضمام» means «until the last day»: send it, or the API keeps an old cutoff.
    const fields = { ...parsed.data, joinLastDay: parsed.data.joinLastDay ?? parsed.data.lastDay };
    const { slug, ...rest } = fields;
    body = mode === 'draft' ? fields : rest;
  }
  const r = await tryApi(`/admin/competitions/tournaments/${id}`, { method: 'PATCH', body: AdminTournamentPatch.parse(body) });
  if (r.error) return fail(r);
  if (mode === 'draft' && form.get('intent') === 'publish') {
    const pub = await tryApi(`/admin/competitions/tournaments/${id}/publish`, { method: 'POST' });
    if (pub.error) return fail(pub);
  }
  revalidatePath('/competitions');
  revalidatePath(`/competitions/tournaments/${id}`);
  return { error: null, ok: true };
}

export async function publishTournament(id: string, _prev: S, _form: FormData): Promise<S> {
  const r = await tryApi(`/admin/competitions/tournaments/${id}/publish`, { method: 'POST' });
  if (r.error) return fail(r);
  revalidatePath('/competitions');
  revalidatePath(`/competitions/tournaments/${id}`);
  return { error: null, ok: true };
}

/** Early close: the window ends at the next Cairo midnight (today still counts). */
export async function closeTournament(id: string, _prev: S, form: FormData): Promise<S> {
  return act(`/admin/competitions/tournaments/${id}/close`, form, ['/competitions', `/competitions/tournaments/${id}`]);
}

/** Cancel: no badges. */
export async function cancelTournament(id: string, _prev: S, form: FormData): Promise<S> {
  return act(`/admin/competitions/tournaments/${id}/cancel`, form, ['/competitions', `/competitions/tournaments/${id}`]);
}

/* ---------------------------------------------------------------- leagues */

export async function saveLeagueSettings(_prev: S, form: FormData): Promise<S> {
  const names = Array.from({ length: 6 }, (_, i) => ({ ar: text(form, `nameAr${i + 1}`), en: text(form, `nameEn${i + 1}`) }));
  const anyName = names.some((n) => n.ar || n.en);
  if (anyName && names.some((n) => !n.ar || !n.en)) return { error: 'أكمل أسماء الأقسام الستة بالعربية والإنجليزية، أو اتركها كلها فارغة' };
  const parsed = LeagueSettings.safeParse({
    groupSize: Number(text(form, 'groupSize')),
    promote: Number(text(form, 'promote')),
    demote: Number(text(form, 'demote')),
    divisionNames: anyName ? names : undefined,
  });
  if (!parsed.success) {
    const where = String(parsed.error.issues[0]?.path[0] ?? '');
    if (where === 'groupSize') return { error: 'حجم المجموعة من 10 إلى 50' };
    if (where === 'promote' || where === 'demote') return { error: 'الصعود والهبوط من 0 إلى 10 (الصعود 1 على الأقل)' };
    if (where === 'divisionNames') return { error: 'اسم القسم حتى 24 حرفاً' };
    return { error: `${CODE.settings_invalid}: مجموع الصعود والهبوط أقل من حجم المجموعة` };
  }
  const r = await tryApi('/admin/competitions/leagues/settings', { method: 'PUT', body: parsed.data });
  if (r.error) return fail(r);
  revalidatePath('/competitions');
  return { error: null, ok: true };
}

/** Runs the community job body now (super admin only). */
export async function runRollover(_prev: S, form: FormData): Promise<S> {
  return act('/admin/competitions/leagues/rollover', form, ['/competitions']);
}

/* ------------------------------------------------------------- moderation */

/** Support actions on a competitor; every one is audited with its reason by the API. */
export async function competitorAction(userId: string, action: string, _prev: S, form: FormData): Promise<S> {
  const a = CompetitorAction.safeParse(action);
  if (!a.success) return { error: 'إجراء غير معروف' };
  return act(`/admin/competitions/competitors/${userId}/${a.data}`, form, ['/competitions', `/users/${userId}`, '/cards']);
}

export async function resolveReport(id: string, _prev: S, form: FormData): Promise<S> {
  const parsed = ResolveReport.safeParse({ resolution: form.get('resolution'), reason: String(form.get('reason') ?? '') });
  if (!parsed.success) return { error: parsed.error.issues[0]?.path[0] === 'reason' ? CODE.reason_required! : 'اختر «تجاهل» أو «تم الإجراء»' };
  const r = await tryApi(`/admin/competitions/reports/${id}/resolve`, { method: 'POST', body: parsed.data });
  if (r.error) return fail(r);
  revalidatePath('/competitions');
  return { error: null, ok: true };
}
