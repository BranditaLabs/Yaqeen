import type { ProductAnalyticsReport } from '@yaqeen/contracts';
import { Bar, LineChart } from '@/components/charts';
import { Card, CardTitle, Kpi, Notice, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { num } from '@/lib/format';

const EVENT: Record<string, string> = {
  app_open: 'فتح التطبيق',
  onboarding_step: 'خطوة في التعريف',
  onboarding_complete: 'إتمام التعريف',
  sign_in: 'تسجيل الدخول',
  tab_view: 'التنقل بين الأقسام',
  card_published: 'نشر بطاقة',
  card_shared: 'مشاركة بطاقة',
  medal_activated: 'تفعيل ميدالية',
  redeem_view: 'فتح صفحة الاستبدال',
  reward_redeem: 'استبدال مكافأة',
  store_click: 'الانتقال للمتجر',
  notification_open: 'فتح إشعار',
  settings_change: 'تغيير الإعدادات',
  update_prompt: 'طلب التحديث',
};
const STEP: Record<string, string> = {
  welcome: 'الترحيب',
  language: 'اللغة',
  prayer: 'المواقيت',
  consent: 'الموافقات',
  goal: 'الهدف',
  routine: 'الروتين',
  download: 'التنزيلات',
  complete: 'اكتمل',
};
const hidden = 'أقل من 20';
const show = (v: number | null) => (v === null ? hidden : num(v));

/** Product analytics (consented installs only, aggregates; spec §6 analytics). */
export default async function AnalyticsPage({ searchParams }: { searchParams: Promise<{ days?: string }> }) {
  const { days: raw } = await searchParams;
  const days = [7, 30, 90].includes(Number(raw)) ? Number(raw) : 30;
  const r = await api<ProductAnalyticsReport>(`/admin/analytics?days=${days}`);
  const last = r.activeInstalls.at(-1)?.value ?? null;
  const known = r.activeInstalls.map((d) => d.value).filter((v): v is number => v !== null);
  const avg = known.length ? Math.round(known.reduce((a, b) => a + b, 0) / known.length) : null;
  const funnelTop = r.onboardingFunnel[0]?.installs ?? null;

  return (
    <div className="space-y-6">
      <PageHeader
        title="التحليلات"
        subtitle="من وافقوا على «تحسين التطبيق» فقط — أرقام مجمّعة، بلا حسابات ولا أي بيانات عبادة"
        action={
          <div className="flex gap-2">
            {[7, 30, 90].map((d) => (
              <a key={d} href={`/analytics?days=${d}`} className={`rounded-full px-4 py-2 text-sm ${d === days ? 'bg-lapis text-white' : 'bg-white/70 text-muted'}`}>
                {num(d)} يوماً
              </a>
            ))}
          </div>
        }
      />
      <div className="grid gap-4 md:grid-cols-3">
        <Kpi label="أجهزة نشطة اليوم" value={show(last)} />
        <Kpi label={`متوسط يومي · ${num(days)} يوماً`} value={show(avg)} />
        <Kpi label="بدأوا التعريف" value={show(funnelTop)} hint="أجهزة وافقت على تحسين التطبيق" />
      </div>
      <Card>
        <CardTitle>الأجهزة النشطة يومياً</CardTitle>
        <LineChart points={r.activeInstalls} label="الأجهزة النشطة يومياً" />
      </Card>
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardTitle>رحلة التعريف</CardTitle>
          <div className="space-y-4">
            {r.onboardingFunnel.map((s) => (
              <Bar
                key={s.step}
                label={STEP[s.step] ?? s.step}
                value={s.installs === null || !funnelTop ? null : Math.round((s.installs / funnelTop) * 100)}
                tone={s.step === 'complete' ? 'gold' : 'lapis'}
              />
            ))}
          </div>
        </Card>
        <Card>
          <CardTitle>الأحداث</CardTitle>
          <Table head={['الحدث', 'المرات', 'الأجهزة']}>
            {r.events.map((e) => (
              <tr key={e.name}>
                <Td>{EVENT[e.name] ?? e.name}</Td>
                <Td className="num">{show(e.total)}</Td>
                <Td className="num">{show(e.installs)}</Td>
              </tr>
            ))}
          </Table>
        </Card>
      </div>
      <Card>
        <CardTitle>الاحتفاظ الأسبوعي (نسبة من عادوا)</CardTitle>
        <Table head={['أسبوع البداية', 'الأجهزة', 'الأسبوع 1', 'الأسبوع 2', 'الأسبوع 3', 'الأسبوع 4']}>
          {r.retention.map((c) => (
            <tr key={c.cohort}>
              <Td className="num">{c.cohort}</Td>
              <Td className="num">{show(c.size)}</Td>
              {c.weeks.map((w, i) => (
                <Td key={i} className="num">
                  {w === null ? '—' : `${w}%`}
                </Td>
              ))}
            </tr>
          ))}
        </Table>
      </Card>
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardTitle>المنصات</CardTitle>
          <Table head={['المنصة', 'الأجهزة']}>
            {r.platforms.map((p) => (
              <tr key={p.platform}>
                <Td>{p.platform === 'ios' ? 'iOS' : 'Android'}</Td>
                <Td className="num">{show(p.installs)}</Td>
              </tr>
            ))}
          </Table>
        </Card>
        <Card>
          <CardTitle>إصدارات التطبيق</CardTitle>
          <Table head={['الإصدار', 'الأجهزة']}>
            {r.versions.map((v) => (
              <tr key={v.version}>
                <Td className="num" >{v.version}</Td>
                <Td className="num">{show(v.installs)}</Td>
              </tr>
            ))}
          </Table>
        </Card>
      </div>
      <Notice tone="blue">
        تُحذف الأحداث بعد 180 يوماً. الأرقام الأقل من 20 جهازاً لا تُعرض. أخطاء التطبيق والأعطال تُتابع في Sentry، وصحة الخوادم في Grafana.
      </Notice>
    </div>
  );
}
