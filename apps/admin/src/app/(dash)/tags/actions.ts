'use server';

import { revalidatePath } from 'next/cache';
import { AdminTagBatchRequest } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';

type S = { error: string | null; ok?: boolean };

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
