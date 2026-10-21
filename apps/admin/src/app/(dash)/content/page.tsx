import Link from 'next/link';
import { cookies } from 'next/headers';
import type { AdminMe, AdminRole, ContentAdminRow, ContentStatus } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Badge, Button, Card, CardTitle, Notice, PageHeader } from '@/components/ui';
import { api } from '@/lib/api';
import { date, dateTime } from '@/lib/format';
import { ROLE_LABEL } from '@/lib/session';
import { CONTENT_STATUS } from '@/lib/labels';
import { createContent, review, setPreviewRole, submitForReview, upsertDailyTask } from './actions';

const TYPE_LABEL = { dua: 'دعاء', zikr: 'ذِكر', splash_verse: 'آية البداية' } as const;
/** «تعرض كـ» — dev only: previews the page as another role. The API still enforces the real role. */
const PREVIEW_ENABLED = process.env.NODE_ENV !== 'production';

const TABS: { key: ContentStatus | 'all'; label: string }[] = [
  { key: 'all', label: 'الكل' },
  { key: 'pending_review', label: 'بانتظار المراجعة' },
  { key: 'changes_requested', label: 'مطلوب تعديل' },
  { key: 'draft', label: 'مسودات' },
  { key: 'published', label: 'منشور' },
];

export default async function ContentPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status } = await searchParams;
  const me = await api<AdminMe>('/admin/auth/me');
  const items = await api<ContentAdminRow[]>(`/admin/content${status ? `?status=${status}` : ''}`);
  const tasks = await api<{ date: string; taskAr: string }[]>('/admin/content/daily-tasks');
  const preview = PREVIEW_ENABLED ? ((await cookies()).get('yq_preview_role')?.value as AdminRole | undefined) : undefined;
  const role: AdminRole = preview && preview in ROLE_LABEL ? preview : me.role;
  const canEdit = role === 'content_editor' || role === 'super_admin';
  const canReview = role === 'religious_reviewer' || role === 'super_admin';

  return (
    <>
      <PageHeader
        title="المحتوى"
        subtitle="الأدعية والأذكار ومهمة اليوم. لا يُنشر نص قبل مراجعة شرعية من شخص غير كاتبه."
        action={
          PREVIEW_ENABLED && (
            <form action={setPreviewRole} className="flex items-center gap-2 text-xs text-muted">
              تعرض كـ
              <select name="role" defaultValue={role} className="field w-auto py-1.5 text-xs">
                {Object.entries(ROLE_LABEL).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
              <button className="rounded-full border border-line bg-white/70 px-3 py-1.5">عرض</button>
            </form>
          )
        }
      />

      <div className="mb-4 flex flex-wrap gap-2">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={t.key === 'all' ? '/content' : `/content?status=${t.key}`}
            className={`min-h-10 rounded-full px-4 py-2 text-sm ${
              (status ?? 'all') === t.key ? 'bg-lapis text-white' : 'glass text-muted'
            }`}
          >
            {t.label}
          </Link>
        ))}
      </div>

      <div className="grid gap-4 xl:grid-cols-[3fr_2fr]">
        <div className="space-y-3">
          {items.length === 0 && <Card><p className="py-8 text-center text-sm text-muted">لا يوجد محتوى هنا</p></Card>}
          {items.map((c) => (
            <Card key={c.id}>
              <div className="mb-3 flex flex-wrap items-center gap-2">
                <Badge tone={CONTENT_STATUS[c.status].tone}>{CONTENT_STATUS[c.status].label}</Badge>
                <Badge tone="blue">{TYPE_LABEL[c.type]}</Badge>
                <span className="text-xs text-muted">{c.category} · نسخة <span className="num">{c.version}</span></span>
              </div>
              <h3 className="font-bold">{c.title}</h3>
              <p className="mt-2 font-[family-name:var(--font-naskh)] text-xl leading-loose text-ink">{c.textAr}</p>
              {c.translationEn && <p dir="ltr" className="mt-1 text-left text-sm text-muted">{c.translationEn}</p>}
              <p className="mt-2 text-xs text-gold-text">المصدر: {c.source}{c.repeatCount > 1 ? ` · يُكرَّر ${c.repeatCount} مرات` : ''}</p>
              <p className="mt-1 text-xs text-muted">
                آخر تعديل: {c.editorName ?? '—'} · {dateTime(c.updatedAt)}
              </p>
              {c.reviewNote && <Notice tone="red">ملاحظة المراجع: {c.reviewNote}</Notice>}

              <div className="mt-4 flex flex-wrap gap-2">
                {canEdit && (c.status === 'draft' || c.status === 'changes_requested') && (
                  <form action={submitForReview.bind(null, c.id)}>
                    <Button variant="ghost">إرسال للمراجعة</Button>
                  </form>
                )}
                {canReview && c.status === 'pending_review' && (
                  <ActionForm action={review.bind(null, c.id)} className="flex w-full flex-wrap items-center gap-2" success="تم تسجيل القرار">
                    <input name="note" placeholder="ملاحظة (إلزامية عند طلب التعديل)" className="field min-w-0 flex-1" />
                    <Button name="decision" value="approve">اعتماد ونشر</Button>
                    <Button name="decision" value="request_changes" variant="danger">طلب تعديل</Button>
                  </ActionForm>
                )}
              </div>
            </Card>
          ))}
        </div>

        <div className="space-y-4">
          {canEdit && (
            <Card>
              <CardTitle>إضافة دعاء أو ذِكر</CardTitle>
              <ActionForm action={createContent} className="space-y-3" success="تم الحفظ">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="label">النوع</label>
                    <select name="type" className="field">
                      <option value="dua">دعاء</option>
                      <option value="zikr">ذِكر</option>
                    </select>
                  </div>
                  <div>
                    <label className="label">التكرار</label>
                    <input name="repeatCount" type="number" min={1} defaultValue={1} className="field num" />
                  </div>
                </div>
                <div>
                  <label className="label">التصنيف</label>
                  <input name="category" required placeholder="أذكار الصباح، أدعية السفر…" className="field" />
                </div>
                <div>
                  <label className="label">العنوان</label>
                  <input name="title" required className="field" />
                </div>
                <div>
                  <label className="label">النص (بالتشكيل)</label>
                  <textarea name="textAr" required rows={4} className="field font-[family-name:var(--font-naskh)] text-lg leading-loose" />
                </div>
                <div>
                  <label className="label">الترجمة الإنجليزية (اختياري)</label>
                  <textarea name="translationEn" rows={2} dir="ltr" className="field text-left" />
                </div>
                <div>
                  <label className="label">المصدر والتخريج</label>
                  <input name="source" required placeholder="صحيح البخاري 6306" className="field" />
                </div>
                <div className="flex gap-2">
                  <Button name="submit" value="1">حفظ وإرسال للمراجعة</Button>
                  <Button variant="ghost" name="submit" value="0">حفظ كمسودة</Button>
                </div>
              </ActionForm>
            </Card>
          )}

          <Card>
            <CardTitle>جدول مهمة اليوم</CardTitle>
            <ul className="mb-4 space-y-2 text-sm">
              {tasks.length === 0 && <li className="text-muted">لا توجد مهام مجدولة</li>}
              {tasks.map((t) => (
                <li key={t.date} className="flex gap-3">
                  <span className="num w-24 shrink-0 text-muted">{t.date}</span>
                  <span>{t.taskAr}</span>
                </li>
              ))}
            </ul>
            {canEdit && (
              <ActionForm action={upsertDailyTask} className="space-y-3">
                <input name="date" type="date" required className="field num" />
                <input name="taskAr" required placeholder="المهمة بالعربية" className="field" />
                <input name="taskEn" required placeholder="Task in English" dir="ltr" className="field text-left" />
                <Button variant="ghost">جدولة</Button>
              </ActionForm>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
