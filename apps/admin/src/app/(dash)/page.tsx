import Link from 'next/link';
import type { AdminOverview, HijriMonthResponse, OverviewAdherence, OverviewAlert, OverviewFunnel, OverviewRange, OverviewSeries } from '@yaqeen/contracts';
import { Bar, LineChart } from '@/components/charts';
import { Card, CardTitle, Kpi, Notice, PageHeader } from '@/components/ui';
import { api } from '@/lib/api';
import { longDate, num } from '@/lib/format';

const RANGES: { key: OverviewRange; label: string }[] = [
  { key: '7d', label: '7 أيام' },
  { key: '30d', label: '30 يوماً' },
  { key: '90d', label: '90 يوماً' },
];
const FUNNEL_LABEL: Record<number, string> = { 1: 'انضموا', 7: 'وصلوا اليوم 7', 30: 'وصلوا اليوم 30', 100: 'وصلوا اليوم 100' };

async function todayHijri() {
  const now = new Date();
  const iso = new Intl.DateTimeFormat('en-CA', { timeZone: 'Africa/Cairo' }).format(now);
  try {
    const m = await api<HijriMonthResponse>(`/v1/calendar/hijri?year=${iso.slice(0, 4)}&month=${Number(iso.slice(5, 7))}`);
    return m.days.find((d) => d.gregorian === iso) ?? null;
  } catch {
    return null;
  }
}

export default async function OverviewPage({ searchParams }: { searchParams: Promise<{ range?: string }> }) {
  const { range: raw } = await searchParams;
  const range: OverviewRange = RANGES.some((r) => r.key === raw) ? (raw as OverviewRange) : '30d';
  const [o, series, funnel, adherence, alerts, hijri] = await Promise.all([
    api<AdminOverview>('/admin/overview'),
    api<OverviewSeries>(`/admin/overview/series?metric=dau&range=${range}`),
    api<OverviewFunnel>('/admin/overview/funnel'),
    api<OverviewAdherence>('/admin/overview/adherence'),
    api<OverviewAlert[]>('/admin/overview/alerts'),
    todayHijri(),
  ]);
  const joined = funnel.steps[0]?.users ?? 0;

  return (
    <>
      <PageHeader title="نظرة عامة" subtitle={`${longDate(new Date(), hijri)} — مؤشرات مجمّعة، لا تُعرض بيانات عبادة لأي مستخدم بعينه`} />

      <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <Kpi label="مستخدمون نشطون اليوم" value={num(o.dau)} />
        <Kpi label="نشطون خلال 30 يوماً" value={num(o.mau)} />
        <Kpi label="مشاركون في تحدي اليقين" value={num(o.challengeParticipants)} />
        <Kpi label="نقاط مُنحت (30 يوماً)" value={num(o.pointsIssued30d)} hint={`استُبدل منها ${num(o.pointsRedeemed30d)}`} />
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-[2fr_1fr]">
        <Card>
          <CardTitle
            action={
              <div className="flex gap-1 rounded-full bg-white/60 p-1">
                {RANGES.map((r) => (
                  <Link
                    key={r.key}
                    href={`/?range=${r.key}`}
                    className={`rounded-full px-3 py-1 text-xs ${range === r.key ? 'bg-white text-lapis shadow-sm' : 'text-muted'}`}
                  >
                    {r.label}
                  </Link>
                ))}
              </div>
            }
          >
            المستخدمون النشطون يومياً
          </CardTitle>
          <LineChart points={series.points} />
          <p className="mt-2 text-xs text-muted">
            <span className="inline-block h-2 w-2 rounded-full bg-gold align-middle" /> أيام الجمعة — ذروة الاستخدام المعتادة. الأيام التي
            تقل عن 20 مستخدماً تظهر رمادية ولا تُعرض قيمتها.
          </p>
        </Card>

        <Card>
          <CardTitle>تنبيهات</CardTitle>
          <div className="space-y-3">
            {alerts.length === 0 && <Notice tone="blue">لا شيء يحتاج انتباهك اليوم</Notice>}
            {alerts.map((a) => (
              <Notice key={a.kind + a.messageAr} tone={a.severity === 'warning' ? 'gold' : 'blue'}>
                <Link href={a.href} className="underline-offset-4 hover:underline">
                  {a.messageAr}
                </Link>
              </Notice>
            ))}
          </div>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardTitle>رحلة التحدي</CardTitle>
          <div className="space-y-4">
            {funnel.steps.map((s) => (
              <Bar key={s.days} label={FUNNEL_LABEL[s.days] ?? `اليوم ${s.days}`} value={s.users} suffix="" max={joined || 1} tone="gold" />
            ))}
          </div>
        </Card>
        <Card>
          <CardTitle>التزام اليوم بين المشاركين</CardTitle>
          <div className="space-y-4">
            <Bar label="وِرد القرآن" value={adherence.wirdPct} />
            <Bar label="أذكار الصباح" value={adherence.morningAzkarPct} />
            <Bar label="سجّلوا الصلوات" value={adherence.prayersPct} />
          </div>
          <p className="mt-4 text-xs text-muted">
            نسب مجمّعة من <span className="num">{num(adherence.participants)}</span> مشاركاً. تُخفى أي نسبة إذا قل العدد عن 20 حفاظاً على
            الخصوصية.
          </p>
        </Card>
      </div>
    </>
  );
}
