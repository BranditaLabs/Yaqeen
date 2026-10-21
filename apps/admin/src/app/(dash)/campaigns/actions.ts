'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { CampaignCreate, CampaignTest } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';
import { zonedLocalToIso } from '@/lib/format';

type S = { error: string | null; ok?: boolean; reach?: number; issues?: string[]; testSent?: number };

function parse(form: FormData) {
  const scheduledAt = form.get('scheduledAt') as string;
  return CampaignCreate.safeParse({
    name: form.get('name'),
    kind: form.get('kind'),
    segment: form.get('segment'),
    titleAr: form.get('titleAr'),
    bodyAr: form.get('bodyAr'),
    titleEn: form.get('titleEn'),
    bodyEn: form.get('bodyEn'),
    deepLink: form.get('deepLink'),
    schedule: form.get('schedule'),
    // <input type="datetime-local"> is Cairo local time (Egypt observes DST).
    scheduledAt: scheduledAt ? zonedLocalToIso(scheduledAt, 'Africa/Cairo') : undefined,
  });
}

export async function saveCampaign(_prev: S, form: FormData): Promise<S> {
  if (form.get('intent') === 'test') {
    const test = CampaignTest.safeParse({
      titleAr: form.get('titleAr'),
      bodyAr: form.get('bodyAr'),
      titleEn: (form.get('titleEn') as string) || undefined,
      bodyEn: (form.get('bodyEn') as string) || undefined,
      deepLink: form.get('deepLink'),
    });
    if (!test.success) return { error: 'اكتب العنوان والنص أولاً' };
    const res = await tryApi<{ sent: number }>('/admin/campaigns/test', { method: 'POST', body: test.data });
    if (res.code === 'no_test_devices') return { error: 'أضف جهاز اختبار من الإعدادات أولاً' };
    if (res.code === 'push_not_configured') return { error: 'الإشعارات غير مهيأة على الخادم (Firebase)' };
    if (res.error || !res.data) return { error: res.error };
    return { error: null, testSent: res.data.sent };
  }
  const parsed = parse(form);
  if (!parsed.success) return { error: 'أكمل كل الحقول بالعربية والإنجليزية' };

  if (form.get('intent') === 'preview') {
    const res = await tryApi<{ estimatedReach: number; issues: string[] }>('/admin/campaigns/preview', { method: 'POST', body: parsed.data });
    if (res.error || !res.data) return { error: res.error };
    return { error: null, reach: res.data.estimatedReach, issues: res.data.issues };
  }

  const res = await tryApi('/admin/campaigns', { method: 'POST', body: parsed.data });
  if (res.error) return { error: res.error };
  revalidatePath('/campaigns');
  redirect('/campaigns');
}

export async function cancelCampaign(id: string) {
  await tryApi(`/admin/campaigns/${id}/cancel`, { method: 'POST' });
  revalidatePath('/campaigns');
}
