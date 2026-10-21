'use server';

import { revalidatePath } from 'next/cache';
import { AdminRole, HijriAdjustRequest } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';

type S = { error: string | null; ok?: boolean; preview?: { firstOfMonths: { gregorian: string; hijriMonthNameAr: string; hijriYear: number }[]; warnings: string[] }; secret?: string };

export async function saveFlags(current: Record<string, boolean>, _prev: S, form: FormData): Promise<S> {
  const features = Object.fromEntries(Object.keys(current).map((k) => [k, form.get(k) === 'on']));
  const maintenance = {
    enabled: form.get('maintenance') === 'on',
    messageAr: String(form.get('maintenanceAr') ?? ''),
    messageEn: String(form.get('maintenanceEn') ?? ''),
  };
  const minVersion = { ios: String(form.get('minIos')), android: String(form.get('minAndroid')) };
  const { error } = await tryApi('/admin/settings/config', { method: 'PATCH', body: { features, maintenance, minVersion } });
  if (error) return { error };
  revalidatePath('/settings');
  return { error: null, ok: true };
}

export async function hijri(_prev: S, form: FormData): Promise<S> {
  const parsed = HijriAdjustRequest.safeParse({
    region: 'EG',
    offsetDays: Number(form.get('offsetDays')),
    effectiveHijriMonth: Number(form.get('month')),
    effectiveHijriYear: Number(form.get('year')),
  });
  if (!parsed.success) return { error: 'قيم غير صالحة' };
  const intent = form.get('intent');
  const res = await tryApi<NonNullable<S['preview']>>(intent === 'save' ? '/admin/settings/hijri' : '/admin/settings/hijri/preview', {
    method: 'POST',
    body: parsed.data,
  });
  if (res.error) return { error: res.error };
  if (intent === 'save') revalidatePath('/settings');
  return { error: null, ok: intent === 'save', preview: { firstOfMonths: res.data?.firstOfMonths ?? [], warnings: res.data?.warnings ?? [] } };
}

export async function addAdmin(_prev: S, form: FormData): Promise<S> {
  const role = AdminRole.safeParse(form.get('role'));
  if (!role.success) return { error: 'اختر الدور' };
  const res = await tryApi<{ totpSecret: string; otpauthUrl: string }>('/admin/settings/team', {
    method: 'POST',
    body: { name: form.get('name'), email: form.get('email'), role: role.data, password: form.get('password') },
  });
  if (res.error) return { error: res.error };
  revalidatePath('/settings');
  return { error: null, ok: true, secret: res.data?.otpauthUrl };
}
