'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { CampaignCreate } from '@yaqeen/contracts';
import { tryApi } from '@/lib/api';
import { zonedLocalToIso } from '@/lib/format';

type S = { error: string | null; ok?: boolean; reach?: number; issues?: string[] };

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
