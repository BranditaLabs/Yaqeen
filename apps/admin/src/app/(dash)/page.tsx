import Link from 'next/link';
import type { AdminOverview } from '@yaqeen/contracts';
import { Card, CardTitle, Kpi, Notice, PageHeader } from '@/components/ui';
import { api } from '@/lib/api';
import { num, pct } from '@/lib/format';

export default async function OverviewPage() {
  const o = await api<AdminOverview>('/admin/overview');

  const habits = [
    { label: 'وِرد القرآن', value: o.habitsToday.wirdPct },
    { label: 'أذكار الصباح', value: o.habitsToday.morningAzkarPct },
    { label: 'الصلوات الخمس', value: o.habitsToday.prayersPct },
  ];

  return (
    <>
      <PageHeader title="نظرة عامة" subtitle="مؤشرات مجمّعة — لا تُعرض بيانات عبادة لأي مستخدم بعينه" />

      <div className="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <Kpi label="مستخدمون نشطون اليوم" value={num(o.dau)} />
        <Kpi label="نشطون خلال 30 يوماً" value={num(o.mau)} />
        <Kpi label="مشاركون في تحدي اليقين" value={num(o.challengeParticipants)} />
        <Kpi
          label="نقاط مُنحت / استُبدلت (30 يوماً)"
          value={`${num(o.pointsIssued30d)}`}
          hint={`استُبدل منها ${num(o.pointsRedeemed30d)}`}
        />
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-[2fr_1fr]">
        <Card>
          <CardTitle>عادات اليوم بين المشاركين</CardTitle>
          <div className="space-y-4">
            {habits.map((h) => (
              <div key={h.label}>
                <div className="mb-1.5 flex justify-between text-sm">
                  <span>{h.label}</span>
                  <span className="num text-muted">{pct(h.value)}</span>
                </div>
                <div className="h-2 rounded-full bg-ice">
                  <div className="h-2 rounded-full bg-lapis" style={{ width: `${Math.min(100, h.value)}%` }} />
                </div>
              </div>
            ))}
          </div>
        </Card>

        <Card>
          <CardTitle>تنبيهات</CardTitle>
          <div className="space-y-3">
            {o.pendingReviews > 0 ? (
              <Notice>
                <Link href="/content?status=pending_review" className="underline-offset-4 hover:underline">
                  <span className="num">{num(o.pendingReviews)}</span> عنصر محتوى بانتظار المراجعة الشرعية
                </Link>
              </Notice>
            ) : (
              <Notice tone="blue">لا يوجد محتوى بانتظار المراجعة</Notice>
            )}
          </div>
        </Card>
      </div>
    </>
  );
}
