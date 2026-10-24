'use server';

import { revalidatePath } from 'next/cache';
import { AdminRole, HijriAdjustRequest, SplashVerseUpdate, TestDevicesUpdate } from '@yaqeen/contracts';
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
  const pctOf = (k: string) => Math.min(100, Math.max(0, Math.round(Number(form.get(`rollout_${k}`) ?? 100))));
  const featureRollout = Object.fromEntries(ROLLOUT_FLAGS.map((k) => [k, pctOf(k)]));
  const { error } = await tryApi('/admin/settings/config', { method: 'PATCH', body: { features, featureRollout, maintenance, minVersion } });
  if (error) return { error };
  revalidatePath('/settings');
  return { error: null, ok: true };
}

/** Flags rolled out gradually (stable bucketing by user id — see packages/contracts/src/rollout.ts). */
const ROLLOUT_FLAGS = ['recite'];

export async function proposeSplashVerse(_prev: S, form: FormData): Promise<S> {
  const parsed = SplashVerseUpdate.safeParse({ textAr: String(form.get('textAr') ?? '').trim(), reference: String(form.get('reference') ?? '').trim() });
  if (!parsed.success) return { error: 'اكتب الآية ومرجعها (السورة: رقم الآية)' };
  const { error } = await tryApi('/admin/settings/splash-verse', { method: 'PUT', body: parsed.data });
  if (error) return { error };
  revalidatePath('/settings');
  return { error: null, ok: true };
}

export async function saveTestDevices(_prev: S, form: FormData): Promise<S> {
  const tokens = String(form.get('tokens') ?? '')
    .split(/\s+/)
    .map((t) => t.trim())
    .filter(Boolean);
  const parsed = TestDevicesUpdate.safeParse({ tokens });
  if (!parsed.success) return { error: 'حتى 5 رموز FCM، كل رمز في سطر' };
  const { error } = await tryApi('/admin/auth/me/test-devices', { method: 'PUT', body: parsed.data });
  if (error) return { error };
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
