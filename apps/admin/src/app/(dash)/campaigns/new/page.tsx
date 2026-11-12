'use client';

import { useActionState, useState } from 'react';
import { Button, Card, CardTitle, Notice, PageHeader } from '@/components/ui';
import { saveCampaign } from '../actions';

const SEGMENTS = {
  all: 'كل من وافق على هذا النوع',
  balance_gte_1000: 'رصيد 1,000 نقطة أو أكثر',
  missed_yesterday: 'فاتته مهام الأمس',
  streak_gte_7: 'مواظب 7 أيام',
  inactive_7d: 'غير نشط منذ 7 أيام',
};

const LINKS = {
  redeem: 'المكافآت',
  challenge: 'التحدي',
  calendar: 'التقويم',
  store: 'المتجر',
  home: 'الرئيسية',
  quran: 'المصحف',
  azkar: 'الأذكار',
  hifz: 'الحفظ',
  prayer: 'الصلاة',
  ramadan: 'رمضان (الإمساكية)',
};

export default function NewCampaignPage() {
  const [state, action, pending] = useActionState(saveCampaign, { error: null });
  const [title, setTitle] = useState('هديتك من يقين تنتظرك');
  const [body, setBody] = useState('رصيدك يكفي لخصم 50 جنيهاً على متجر يقين.');
  const [schedule, setSchedule] = useState('smart');
  // Controlled so values survive the "preview" server action (React resets uncontrolled forms).
  const [v, setV] = useState({
    name: '',
    kind: 'rewards',
    segment: 'balance_gte_1000',
    titleEn: 'Your Yaqeen gift is waiting',
    bodyEn: 'Your balance covers 50 EGP off at the Yaqeen store.',
    deepLink: 'redeem',
    scheduledAt: '',
  });
  const bind = (k: keyof typeof v) => ({ value: v[k], onChange: (e: { target: { value: string } }) => setV({ ...v, [k]: e.target.value }) });

  return (
    <>
      <PageHeader title="حملة جديدة" subtitle="اكتب بهدوء ولطف — بلا استعجال ولا تهويل." />
      <form action={action} className="grid gap-4 xl:grid-cols-[3fr_2fr]">
        <Card>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="md:col-span-2">
              <label className="label">اسم داخلي</label>
              <input name="name" required className="field" placeholder="تذكير الرصيد — أكتوبر" {...bind('name')} />
            </div>
            <div>
              <label className="label">النوع (يحدد الموافقة المطلوبة)</label>
              <select name="kind" className="field" {...bind('kind')}>
                <option value="challenge">التحدي — موافقة التحدي والمكافآت</option>
                <option value="rewards">المكافآت — موافقة التحدي والمكافآت</option>
                <option value="offers">عروض المتجر — موافقة العروض</option>
              </select>
            </div>
            <div>
              <label className="label">الشريحة</label>
              <select name="segment" className="field" {...bind('segment')}>
                {Object.entries(SEGMENTS).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="label">العنوان بالعربية</label>
              <input name="titleAr" required maxLength={60} value={title} onChange={(e) => setTitle(e.target.value)} className="field" />
            </div>
            <div>
              <label className="label">Title (English)</label>
              <input name="titleEn" required maxLength={60} dir="ltr" className="field text-left" {...bind('titleEn')} />
            </div>
            <div>
              <label className="label">النص بالعربية</label>
              <textarea name="bodyAr" required maxLength={140} rows={3} value={body} onChange={(e) => setBody(e.target.value)} className="field" />
            </div>
            <div>
              <label className="label">Body (English)</label>
              <textarea name="bodyEn" required maxLength={140} rows={3} dir="ltr" className="field text-left" {...bind('bodyEn')} />
            </div>
            <div>
              <label className="label">يفتح على</label>
              <select name="deepLink" className="field" {...bind('deepLink')}>
                {Object.entries(LINKS).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="label">التوقيت</label>
              <select name="schedule" className="field" value={schedule} onChange={(e) => setSchedule(e.target.value)}>
                <option value="smart">ذكي — أول وقت مسموح لكل مستخدم</option>
                <option value="now">الآن (مع الضوابط)</option>
                <option value="scheduled">موعد محدد</option>
              </select>
            </div>
            {schedule === 'scheduled' && (
              <div>
                <label className="label">الموعد (بتوقيت القاهرة)</label>
                <input name="scheduledAt" type="datetime-local" required className="field num" {...bind('scheduledAt')} />
              </div>
            )}
          </div>

          {state.error && <p className="mt-4 text-sm text-error">{state.error}</p>}
          {state.issues && state.issues.length > 0 && (
            <div className="mt-4"><Notice>{state.issues.join(' · ')}</Notice></div>
          )}
          {state.testSent !== undefined && !state.error && (
            <p className="mt-4 text-sm text-success">
              أُرسلت التجربة إلى <span className="num">{state.testSent}</span> من أجهزتك
            </p>
          )}
          {state.reach !== undefined && !state.error && (
            <p className="mt-4 text-sm text-lapis">
              الوصول المتوقع: <span className="num">{new Intl.NumberFormat('en-US').format(state.reach)}</span> مستخدم
            </p>
          )}

          <div className="mt-6 flex flex-wrap gap-2">
            <Button name="intent" value="preview" variant="ghost" disabled={pending}>تقدير الوصول ومراجعة النص</Button>
            <Button name="intent" value="test" variant="ghost" disabled={pending}>إرسال تجريبي لجهازي</Button>
            <Button name="intent" value="save" disabled={pending}>جدولة الحملة</Button>
          </div>
        </Card>

        <Card className="h-fit">
          <CardTitle>معاينة شاشة القفل</CardTitle>
          <div className="rounded-[28px] bg-gradient-to-b from-[#DCE4F2] to-[#F3F6FB] p-4">
            <p className="num mb-6 mt-4 text-center text-5xl font-light text-ink/80">9:41</p>
            <div className="glass rounded-[20px] p-3">
              <div className="mb-1 flex items-center justify-between text-[11px] text-muted">
                <span className="flex items-center gap-1.5">
                  <span className="grid h-5 w-5 place-items-center rounded-md bg-[image:var(--yq-gradient-brand)]">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src="/brand/mark-white.png" alt="" className="h-3 w-auto" />
                  </span>
                  يقين
                </span>
                <span>الآن</span>
              </div>
              <p className="text-sm font-bold">{title || 'العنوان'}</p>
              <p className="text-sm text-ink/80">{body || 'النص'}</p>
            </div>
          </div>
          <p className="mt-3 text-xs text-muted">
            العنوان <span className="num">{title.length}</span>/40 · النص <span className="num">{body.length}</span>/110 حرفاً قبل القص المحتمل
          </p>
        </Card>
      </form>
    </>
  );
}
