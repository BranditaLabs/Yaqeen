'use server';

import { revalidatePath } from 'next/cache';
import { cookies } from 'next/headers';
import { AdminRole, DailyTaskUpsert, ReviewDecision, UpsertContentRequest } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';

type S = { error: string | null; ok?: boolean };

export async function createContent(_prev: S, form: FormData): Promise<S> {
  const parsed = UpsertContentRequest.safeParse({
    type: form.get('type'),
    category: form.get('category'),
    title: form.get('title'),
    textAr: form.get('textAr'),
    translationEn: (form.get('translationEn') as string) || null,
    source: form.get('source'),
    repeatCount: Number(form.get('repeatCount') || 1),
  });
  if (!parsed.success) return { error: 'أكمل الحقول المطلوبة — المصدر إلزامي' };
  const created = await tryApi<{ id: string }>('/admin/content', { method: 'POST', body: parsed.data });
  if (created.error || !created.data) return { error: created.error };
  if (form.get('submit') === '1') {
    const sub = await tryApi(`/admin/content/${created.data.id}/submit`, { method: 'POST' });
    if (sub.error) return { error: sub.error };
  }
  revalidatePath('/content');
  return { error: null, ok: true };
}

export async function submitForReview(id: string) {
  await tryApi(`/admin/content/${id}/submit`, { method: 'POST' });
  revalidatePath('/content');
}

export async function review(id: string, _prev: S, form: FormData): Promise<S> {
  const parsed = ReviewDecision.safeParse({ decision: form.get('decision'), note: (form.get('note') as string) || undefined });
  if (!parsed.success) return { error: 'قرار غير صالح' };
  if (parsed.data.decision === 'request_changes' && !parsed.data.note) return { error: 'اكتب ملاحظة توضح التعديل المطلوب' };
  const { error } = await tryApi(`/admin/content/${id}/review`, { method: 'POST', body: parsed.data });
  if (error) return { error };
  revalidatePath('/content');
  return { error: null, ok: true };
}

export async function upsertDailyTask(_prev: S, form: FormData): Promise<S> {
  const parsed = DailyTaskUpsert.safeParse({ date: form.get('date'), taskAr: form.get('taskAr'), taskEn: form.get('taskEn') });
  if (!parsed.success) return { error: 'التاريخ والمهمة بالعربية والإنجليزية مطلوبة' };
  const { error } = await tryApi('/admin/content/daily-tasks', { method: 'PUT', body: parsed.data });
  if (error) return { error };
  revalidatePath('/content');
  return { error: null, ok: true };
}

/** Dev-only «تعرض كـ» toggle (ignored in production builds). */
export async function setPreviewRole(form: FormData) {
  if (process.env.NODE_ENV === 'production') return;
  const role = AdminRole.safeParse(form.get('role'));
  const jar = await cookies();
  if (role.success) jar.set('yq_preview_role', role.data, { httpOnly: true, sameSite: 'strict', path: '/content' });
  revalidatePath('/content');
}
