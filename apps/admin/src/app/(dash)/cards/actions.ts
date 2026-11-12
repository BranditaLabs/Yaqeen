'use server';

import { revalidatePath } from 'next/cache';
import { CardsSettings } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';

type S = { error: string | null; ok?: boolean };

async function act(path: string, form: FormData): Promise<S> {
  const reason = String(form.get('reason') ?? '').trim();
  if (reason.length < 3) return { error: 'اكتب السبب (يُسجَّل في سجل التدقيق)' };
  const { error } = await tryApi(path, { method: 'POST', body: { reason } });
  if (error) return { error };
  revalidatePath('/cards');
  return { error: null, ok: true };
}

export async function moderateCard(userId: string, _prev: S, form: FormData) {
  return act(`/admin/cards/${userId}/moderate`, form);
}

export async function restoreCard(userId: string, _prev: S, form: FormData) {
  const r = await act(`/admin/cards/${userId}/restore`, form);
  revalidatePath(`/users/${userId}`);
  return r;
}

export async function releaseHandle(userId: string, _prev: S, form: FormData) {
  return act(`/admin/cards/${userId}/release-handle`, form);
}

export async function saveCardSettings(_prev: S, form: FormData): Promise<S> {
  const text = (k: string) => String(form.get(k) ?? '').trim();
  const parsed = CardsSettings.safeParse({
    medalProductUrl: text('medalProductUrl'),
    storeUrl: text('storeUrl'),
    ctaTitleAr: text('ctaTitleAr'),
    ctaTitleEn: text('ctaTitleEn'),
    ctaBodyAr: text('ctaBodyAr'),
    ctaBodyEn: text('ctaBodyEn'),
    reservedHandles: text('reservedHandles')
      .split(/[\s,،]+/)
      .map((h) => h.replace(/^@/, ''))
      .filter(Boolean),
  });
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    const where = String(issue?.path[0] ?? '');
    return { error: where === 'reservedHandles' ? 'اسم محجوز غير صالح: حروف لاتينية وأرقام و _ . فقط' : where.endsWith('Url') ? 'الروابط تبدأ بـ https://' : 'تحقق من القيم' };
  }
  const { error } = await tryApi('/admin/cards/settings', { method: 'PUT', body: parsed.data });
  if (error) return { error };
  revalidatePath('/cards');
  return { error: null, ok: true };
}
