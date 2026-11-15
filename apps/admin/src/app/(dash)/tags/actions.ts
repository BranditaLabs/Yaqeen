'use server';

import { revalidatePath } from 'next/cache';
import QRCode from 'qrcode';
import { AdminAssignTag, type AdminEncodeSessionCreated, AdminTagBatchPatch, AdminTagBatchRequest } from '@yaqeen/contracts';
import tokens from '@yaqeen/design-tokens/tokens.json';
import { tryApi } from '@/lib/api';

type S = { error: string | null; ok?: boolean };

/** A just-opened staff encoding session: the link is shown once (QR + text) and never stored here. */
export type EncodeState = { error: string | null; ok?: boolean; session?: { id: string; url: string; expiresAt: string; qrSvg: string } };

export async function openEncodeSession(batch: string, _prev: EncodeState, _form: FormData): Promise<EncodeState> {
  const { data, error, code } = await tryApi<AdminEncodeSessionCreated>(`/admin/tags/batches/${encodeURIComponent(batch)}/encode-sessions`, { method: 'POST' });
  if (code === 'batch_void') return { error: 'الدفعة ملغاة ولا يمكن ترميزها' };
  if (error || !data) return { error: error ?? 'تعذّر فتح جلسة الترميز' };
  const qrSvg = await QRCode.toString(data.url, {
    type: 'svg',
    margin: 1,
    errorCorrectionLevel: 'M',
    color: { dark: tokens.color.ink, light: tokens.color.white },
  });
  revalidatePath('/tags');
  return { error: null, ok: true, session: { id: data.id, url: data.url, expiresAt: data.expiresAt, qrSvg } };
}

export async function revokeEncodeSession(batch: string, id: string, _prev: S, _form: FormData): Promise<S> {
  const { error } = await tryApi(`/admin/tags/batches/${encodeURIComponent(batch)}/encode-sessions/${encodeURIComponent(id)}`, { method: 'DELETE' });
  if (error) return { error };
  revalidatePath('/tags');
  return { error: null, ok: true };
}

export async function mintBatch(_prev: S, form: FormData): Promise<S> {
  const parsed = AdminTagBatchRequest.safeParse({
    batch: String(form.get('batch') ?? ''),
    kind: String(form.get('kind') ?? 'medal'),
    count: Number(form.get('count')),
  });
  if (!parsed.success) return { error: parsed.error.issues[0]?.message ?? 'تحقق من القيم' };
  const { error, code } = await tryApi('/admin/tags/batches', { method: 'POST', body: parsed.data });
  if (code === 'batch_exists') return { error: 'اسم الدفعة مستخدم، اختر اسماً جديداً' };
  if (error) return { error };
  revalidatePath('/tags');
  return { error: null, ok: true };
}

async function act(path: string, form: FormData): Promise<S> {
  const reason = String(form.get('reason') ?? '').trim();
  if (reason.length < 3) return { error: 'اكتب السبب (يُسجَّل في سجل التدقيق)' };
  const { error } = await tryApi(path, { method: 'POST', body: { reason } });
  if (error) return { error };
  revalidatePath('/tags');
  return { error: null, ok: true };
}

export async function disableTag(code: string, _prev: S, form: FormData) {
  return act(`/admin/tags/${code}/disable`, form);
}

export async function releaseTag(code: string, _prev: S, form: FormData) {
  return act(`/admin/tags/${code}/release`, form);
}

export async function updateBatch(batch: string, _prev: S, form: FormData): Promise<S> {
  const parsed = AdminTagBatchPatch.safeParse({ status: String(form.get('status') ?? '') || undefined, note: String(form.get('note') ?? '') });
  if (!parsed.success) return { error: 'تحقق من القيم' };
  const { error } = await tryApi(`/admin/tags/batches/${encodeURIComponent(batch)}`, { method: 'PATCH', body: parsed.data });
  if (error) return { error };
  revalidatePath('/tags');
  return { error: null, ok: true };
}

export async function voidBatch(batch: string, _prev: S, form: FormData) {
  return act(`/admin/tags/batches/${encodeURIComponent(batch)}/void`, form);
}

export async function assignTag(code: string, _prev: S, form: FormData): Promise<S> {
  const parsed = AdminAssignTag.safeParse({ userId: String(form.get('userId') ?? '').trim(), reason: String(form.get('reason') ?? '').trim() });
  if (!parsed.success) return { error: parsed.error.issues[0]?.path[0] === 'userId' ? 'معرّف الحساب غير صالح' : 'اكتب السبب' };
  const { error, code: err } = await tryApi(`/admin/tags/${code}/assign`, { method: 'POST', body: parsed.data });
  if (err === 'user_not_eligible') return { error: 'الحساب يجب أن يكون مسجلاً ونشطاً (ليس ضيفاً)' };
  if (err === 'tag_limit') return { error: 'لدى هذا الحساب الحد الأقصى من الميداليات (10)' };
  if (err === 'not_found') return { error: 'القطعة غير متاحة للربط' };
  if (error) return { error };
  revalidatePath('/tags');
  return { error: null, ok: true };
}
