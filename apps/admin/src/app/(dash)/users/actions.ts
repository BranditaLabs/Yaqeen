'use server';

import { revalidatePath } from 'next/cache';
import { AdjustPointsRequest, UserStatus } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';

export type FormState = { error: string | null; ok?: boolean };

export async function adjustPoints(userId: string, _prev: FormState, form: FormData): Promise<FormState> {
  const parsed = AdjustPointsRequest.safeParse({
    delta: Number(form.get('delta')),
    reason: form.get('reason'),
    note: (form.get('note') as string) || undefined,
  });
  if (!parsed.success) return { error: 'أدخل قيمة صحيحة غير صفرية واختر السبب' };
  const { error } = await tryApi(`/admin/users/${userId}/points`, { method: 'POST', body: parsed.data });
  if (error) return { error };
  revalidatePath(`/users/${userId}`);
  return { error: null, ok: true };
}

export async function setStatus(userId: string, _prev: FormState, form: FormData): Promise<FormState> {
  const status = UserStatus.safeParse(form.get('status'));
  const reason = String(form.get('reason') ?? '').trim();
  if (!status.success || reason.length < 3) return { error: 'اختر الحالة واكتب السبب' };
  const { error } = await tryApi(`/admin/users/${userId}/status`, { method: 'POST', body: { status: status.data, reason } });
  if (error) return { error };
  revalidatePath(`/users/${userId}`);
  return { error: null, ok: true };
}

/** Moderation: hide a user's public card (audited server-side). */
export async function unpublishCard(userId: string, _prev: FormState, form: FormData): Promise<FormState> {
  const reason = String(form.get('reason') ?? '').trim();
  if (reason.length < 3) return { error: 'اكتب سبب الإخفاء' };
  const { error } = await tryApi(`/admin/users/${userId}/public-profile/unpublish`, { method: 'POST', body: { reason } });
  if (error) return { error };
  revalidatePath(`/users/${userId}`);
  return { error: null, ok: true };
}
