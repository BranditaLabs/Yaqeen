'use server';

import { revalidatePath } from 'next/cache';
import { tryApi } from '@/lib/api';

type S = { error: string | null; ok?: boolean };

const ERRORS: Record<string, string> = {
  role_not_allowed: 'هذا الإجراء لدور آخر',
  not_in_review: 'لم تعد التلاوة في انتظار المراجعة',
  nothing_to_dismiss: 'لا شيء لإسقاطه',
  nothing_to_restore: 'لا شيء لاستعادته (أو انقضت مهلة الأيام السبعة)',
  already_removed: 'أُزيلت من قبل',
  not_found: 'لم تعد في قائمة المراجعة',
};

function reasonOf(form: FormData): string | null {
  const reason = String(form.get('reason') ?? '').trim();
  return reason.length >= 3 ? reason : null;
}

/** approve | reject (with a reject reason) | dismiss | remove | restore — audited by the API. */
export async function decideRecording(id: string, _prev: S, form: FormData): Promise<S> {
  const reason = reasonOf(form);
  if (!reason) return { error: 'اكتب السبب (يُسجَّل في سجل التدقيق)' };
  const action = String(form.get('action') ?? '');
  const rejectReason = String(form.get('rejectReason') ?? '') || undefined;
  if (action === 'reject' && !rejectReason) return { error: 'اختر سبب الرفض' };
  const { error, code } = await tryApi(`/admin/recordings/${id}/decision`, { method: 'POST', body: { action, reason, rejectReason } });
  if (error) return { error: (code && ERRORS[code]) || error };
  revalidatePath('/recitations');
  return { error: null, ok: true };
}

/** remove | restore | dismiss on a reported comment (support). */
export async function decideComment(id: string, _prev: S, form: FormData): Promise<S> {
  const reason = reasonOf(form);
  if (!reason) return { error: 'اكتب السبب (يُسجَّل في سجل التدقيق)' };
  const action = String(form.get('action') ?? '');
  const { error, code } = await tryApi(`/admin/recordings/comments/${id}/decision`, { method: 'POST', body: { action, reason } });
  if (error) return { error: (code && ERRORS[code]) || error };
  revalidatePath('/recitations');
  return { error: null, ok: true };
}
