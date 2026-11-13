import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';
import type { AdminMe, AdminStandingRow, AdminTournamentRow, AdminTournamentStats } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Bar } from '@/components/charts';
import { Badge, Button, Card, CardTitle, Kpi, Notice, PageHeader, SkeletonKpis, SkeletonRows } from '@/components/ui';
import { competitionRights } from '@/lib/access';
import { api, tryApi } from '@/lib/api';
import { longDate, num } from '@/lib/format';
import { cairoDate, hijriDays, tournamentPresets } from '@/lib/hijri';
import { BADGE_LABEL, COMPETITION_ERROR, TOURNAMENT_STATUS, tournamentDisplay } from '@/lib/labels';
import { cancelTournament, closeTournament, publishTournament, updateTournament } from '../../actions';
import { Medal, SnapshotLine, StandingsTable } from '../../parts';
import { type FormMode, TournamentForm } from '../tournament-form';

function BackLink() {
  return (
    <Link href="/competitions" className="text-sm text-lapis">
      → المسابقات
    </Link>
  );
}

const lastDayOf = (iso: string) => cairoDate(new Date(Date.parse(iso) - 1));
const dash = (n: number | null) => (n === null ? '—' : num(n));

/** One tournament: status, window, edit/publish/close/cancel, aggregate stats and snapshot standings. */
export default async function TournamentPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ publishError?: string }> }) {
  const [{ id }, { publishError }] = await Promise.all([params, searchParams]);
  const [me, res] = await Promise.all([api<AdminMe>('/admin/auth/me'), tryApi<AdminTournamentRow>(`/admin/competitions/tournaments/${id}`)]);
  if (res.code === 'not_found' || res.code === 'validation') notFound();
  if (!res.data) {
    return (
      <>
        <PageHeader title="البطولة" action={<BackLink />} />
        <Notice tone="red">تعذّر تحميل البطولة. أعد تحميل الصفحة بعد قليل.</Notice>
      </>
    );
  }
  const t = res.data;
  const rights = competitionRights(me.role);
  const display = tournamentDisplay(t);
  const status = TOURNAMENT_STATUS[display];
  const over = t.status === 'cancelled' || t.closed || t.phase === 'ended';
  const mode: FormMode = !rights.canManage || over ? 'readonly' : t.status === 'draft' ? 'draft' : t.phase === 'upcoming' ? 'scheduled' : 'live';
  const startsOn = cairoDate(t.startsAt);
  const lastDay = lastDayOf(t.endsAt);
  const joinLastDay = lastDayOf(t.joinUntil);
  const [hijri, presets] = await Promise.all([
    hijriDays([startsOn, lastDay, joinLastDay]),
    mode === 'draft' || mode === 'scheduled' ? tournamentPresets(cairoDate(new Date())).catch(() => []) : Promise.resolve([]),
  ]);
  const at = (day: string) => longDate(new Date(`${day}T12:00:00Z`), hijri.get(day) ?? null);

  return (
    <>
      <PageHeader
        title={t.titleAr}
        subtitle={`من ${at(startsOn)} إلى ${at(lastDay)} · الانضمام حتى ${at(joinLastDay)}`}
        action={
          <div className="flex items-center gap-3">
            <Badge tone={status.tone}>{status.label}</Badge>
            <BackLink />
          </div>
        }
      />

      {publishError && t.status === 'draft' && (
        <div className="mb-6">
          {/* «حفظ ونشر» created the draft, then publishing it failed: carry on from here. */}
          <Notice tone="red">حُفظت المسودة، ولم تُنشر: {COMPETITION_ERROR[publishError] ?? 'تعذّر النشر'}. راجعها ثم انشرها من «النشر».</Notice>
        </div>
      )}

      <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_360px]">
        <div className="space-y-6">
          <Suspense fallback={<SkeletonKpis />}>
            <Stats id={id} closed={t.closed} />
          </Suspense>
          {rights.canModerate ? (
            // Support's per-row forms must not sit inside a streamed boundary (see competitions/page.tsx).
            <Standings id={id} podium={t.closed} canModerate />
          ) : (
            <Suspense fallback={<SkeletonRows rows={8} />}>
              <Standings id={id} podium={t.closed} canModerate={false} />
            </Suspense>
          )}
        </div>

        <div className="space-y-6">
          <Card>
            <CardTitle>{mode === 'readonly' ? 'البطولة' : 'تعديل البطولة'}</CardTitle>
            <TournamentForm
              mode={mode}
              presets={presets}
              initial={{
                slug: t.slug,
                titleAr: t.titleAr,
                titleEn: t.titleEn,
                bodyAr: t.bodyAr,
                bodyEn: t.bodyEn,
                startsOn,
                lastDay,
                joinLastDay: joinLastDay === lastDay ? '' : joinLastDay,
                badgeAr: t.badgeAr,
                badgeEn: t.badgeEn,
                minPoints: String(t.minPoints),
              }}
              action={updateTournament.bind(null, id, mode === 'draft' ? 'draft' : mode === 'scheduled' ? 'scheduled' : 'live')}
            />
          </Card>

          {rights.canManage && t.status === 'draft' && (
            <Card>
              <CardTitle>النشر</CardTitle>
              <p className="mb-3 text-sm text-muted">تظهر البطولة في التطبيق بعد النشر، ولا يتغير معرّفها بعدها.</p>
              <ActionForm action={publishTournament.bind(null, id)} success="نُشرت البطولة">
                <Button>نشر البطولة</Button>
              </ActionForm>
            </Card>
          )}

          {rights.canManage && t.status === 'published' && t.phase === 'live' && !t.closed && (
            <Card>
              <CardTitle>إغلاق مبكر</CardTitle>
              <p className="mb-3 text-sm text-muted">تنتهي البطولة عند منتصف الليل القادم (اليوم لا يزال يُحتسب)، ثم تُعلن النتائج وتُمنح الشارات.</p>
              <ActionForm action={closeTournament.bind(null, id)} className="space-y-2" success="ستُغلق البطولة عند منتصف الليل">
                <label className="label" htmlFor="close-reason">
                  سبب الإغلاق المبكر
                </label>
                <input id="close-reason" name="reason" required minLength={3} maxLength={500} className="field" />
                <p className="text-xs text-muted">يُسجَّل في سجل التدقيق</p>
                <Button variant="ghost">إغلاق مبكر</Button>
              </ActionForm>
            </Card>
          )}

          {rights.canManage && t.status !== 'cancelled' && !t.closed && (
            <Card>
              <CardTitle>إلغاء البطولة</CardTitle>
              <p className="mb-3 text-sm text-muted">لا تُمنح أي شارات، ويخرج المشاركون منها.</p>
              <ActionForm action={cancelTournament.bind(null, id)} className="space-y-2" success="أُلغيت البطولة">
                <label className="label" htmlFor="cancel-reason">
                  سبب الإلغاء
                </label>
                <input id="cancel-reason" name="reason" required minLength={3} maxLength={500} className="field" />
                <p className="text-xs text-muted">يُسجَّل في سجل التدقيق</p>
                <Button variant="danger">إلغاء</Button>
              </ActionForm>
            </Card>
          )}

          <Notice tone="blue">لا تظهر هنا أي بيانات عبادة — النقاط فقط. الأعداد تحت 20 مخفية.</Notice>
        </div>
      </div>
    </>
  );
}

async function Stats({ id, closed }: { id: string; closed: boolean }) {
  const res = await tryApi<AdminTournamentStats>(`/admin/competitions/tournaments/${id}/stats`);
  if (!res.data) return <Notice tone="red">تعذّر تحميل أرقام البطولة. أعد تحميل الصفحة بعد قليل.</Notice>;
  const s = res.data;
  const maxBucket = Math.max(1, ...s.buckets.map((b) => b.count ?? 0));
  return (
    <div className="space-y-6">
      <div className="grid gap-4 md:grid-cols-3" data-testid="tournament-kpis">
        <Kpi label="المشاركون" value={dash(s.participants)} hint={s.participants === null ? 'أقل من 20 — مخفي' : undefined} />
        <Kpi label="النشطون (لهم نقاط)" value={dash(s.active)} hint={s.active === null ? 'أقل من 20 — مخفي' : undefined} />
        <Kpi label="الوسيط (نقاط)" value={s.median === null ? '—' : num(Math.round(s.median))} hint={s.median === null ? 'يظهر من 20 مشاركاً' : undefined} />
      </div>
      <Card>
        <CardTitle>توزيع النقاط</CardTitle>
        <div className="space-y-4">
          {s.buckets.map((b) => (
            <Bar key={b.label} label={`${b.label} نقطة`} value={b.count} suffix=" مشارك" max={maxBucket} />
          ))}
        </div>
      </Card>
      {closed && (
        <Card>
          <CardTitle>الشارات الممنوحة</CardTitle>
          <ul className="grid gap-3 sm:grid-cols-3">
            {s.badges.map((b) => (
              <li key={b.kind} className="flex items-center gap-3">
                <Medal size={36} />
                <div>
                  <p className="text-sm font-medium">{BADGE_LABEL[b.kind]?.label ?? b.kind}</p>
                  <p className="num text-sm text-gold-text">{dash(b.count)}</p>
                </div>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}

async function Standings({ id, podium, canModerate }: { id: string; podium: boolean; canModerate: boolean }) {
  const res = await tryApi<{ snapshotDay: string | null; total: number; rows: AdminStandingRow[] }>(`/admin/competitions/tournaments/${id}/standings?limit=50`);
  if (!res.data) {
    return (
      <Card>
        <CardTitle>{podium ? 'النتائج النهائية' : 'الترتيب'}</CardTitle>
        <Notice tone="red">تعذّر تحميل الترتيب. أعد تحميل الصفحة بعد قليل.</Notice>
      </Card>
    );
  }
  const s = res.data;
  return (
    <Card>
      <CardTitle>{podium ? 'النتائج النهائية' : 'الترتيب'}</CardTitle>
      {s.rows.length === 0 ? <p className="text-sm text-muted">لا مشاركين بعد.</p> : <StandingsTable rows={s.rows} podium={podium} canModerate={canModerate} />}
      <SnapshotLine day={podium ? undefined : s.snapshotDay} final={podium} />
      <p className="mt-1 text-xs text-muted">
        أعلى 50 من <span className="num">{num(s.total)}</span> مشارك ظاهر
      </p>
    </Card>
  );
}
