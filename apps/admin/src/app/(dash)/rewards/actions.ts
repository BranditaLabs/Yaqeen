'use server';

import { revalidatePath } from 'next/cache';
import { BonusRuleUpdate, GrantCreate, MilestonesUpdate, ProgramUpdate, RewardUpsert } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';

export type S = { error: string | null; ok?: boolean; recipients?: number; totalPoints?: number; previewKey?: string };

function json(form: FormData): unknown {
  try {
    return JSON.parse(String(form.get('payload') ?? 'null'));
  } catch {
    return null;
  }
}

/* ------------------------------------------------------------ program */

export async function saveProgram(_prev: S, form: FormData): Promise<S> {
  const parsed = ProgramUpdate.safeParse(json(form));
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'تحقق من القيم' };
  const { error } = await tryApi('/admin/rewards/program', { method: 'PUT', body: parsed.data });
  if (error) return { error };
  revalidatePath('/rewards');
  return { error: null, ok: true };
}

/* --------------------------------------------------------- milestones */

export async function saveMilestones(_prev: S, form: FormData): Promise<S> {
  const parsed = MilestonesUpdate.safeParse(json(form));
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'تحقق من القيم' };
  const { error } = await tryApi('/admin/rewards/milestones', { method: 'PUT', body: parsed.data });
  if (error) return { error };
  revalidatePath('/rewards');
  return { error: null, ok: true };
}

export async function saveBonus(kind: string, _prev: S, form: FormData): Promise<S> {
  const parsed = BonusRuleUpdate.safeParse({ points: Number(form.get('points')), enabled: form.get('enabled') === 'on' });
  if (!parsed.success) return { error: 'قيمة غير صالحة' };
  const { error } = await tryApi(`/admin/rewards/bonus-rules/${kind}`, { method: 'PUT', body: parsed.data });
  if (error) return { error };
  revalidatePath('/rewards');
  return { error: null, ok: true };
}

/* -------------------------------------------------------------- grants */

export async function grant(_prev: S, form: FormData): Promise<S> {
  const parsed = GrantCreate.safeParse({
    segment: form.get('segment'),
    points: Number(form.get('points')),
    reasonAr: form.get('reasonAr'),
  });
  if (!parsed.success) return { error: 'اختر الشريحة واكتب عدد النقاط والسبب' };

  if (form.get('intent') === 'preview') {
    const res = await tryApi<{ recipients: number; totalPoints: number }>('/admin/rewards/grants/preview', { method: 'POST', body: parsed.data });
    if (res.error || !res.data) return { error: res.error };
    return { error: null, recipients: res.data.recipients, totalPoints: res.data.totalPoints, previewKey: JSON.stringify(parsed.data) };
  }
  const res = await tryApi<{ recipients: number }>('/admin/rewards/grants', { method: 'POST', body: parsed.data });
  if (res.error || !res.data) return { error: res.error };
  revalidatePath('/rewards');
  return { error: null, ok: true, recipients: res.data.recipients };
}

/* ----------------------------------------------------------- catalogue */

export async function saveReward(id: string | null, _prev: S, form: FormData): Promise<S> {
  const n = (k: string) => (form.get(k) ? Number(form.get(k)) : null);
  const parsed = RewardUpsert.safeParse({
    titleAr: form.get('titleAr'),
    titleEn: form.get('titleEn'),
    kind: form.get('kind'),
    value: Number(form.get('value') || 0) || 0.01,
    costPoints: Number(form.get('costPoints')),
    monthlyCap: n('monthlyCap'),
    perUserMonthlyLimit: n('perUserMonthlyLimit'),
    validityDays: Number(form.get('validityDays') || 30),
    shopifyCollectionIds: String(form.get('collections') ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    active: form.get('active') === 'on',
  });
  if (!parsed.success) return { error: 'تحقق من الحقول (الاسم، التكلفة، القيمة، مدة الصلاحية)' };
  const { error } = await tryApi(id ? `/admin/rewards/${id}` : '/admin/rewards', { method: id ? 'PUT' : 'POST', body: parsed.data });
  if (error) return { error };
  revalidatePath('/rewards');
  return { error: null, ok: true };
}
