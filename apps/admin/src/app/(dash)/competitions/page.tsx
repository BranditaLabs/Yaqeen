import Link from 'next/link';
import { Suspense } from 'react';
import {
  LEVELS,
  type AdminCompetitorRow,
  type AdminLeagueStats,
  type AdminMe,
  type AdminReportRow,
  type AdminStandingRow,
  type AdminTournamentRow,
  type BadgeKind,
  type LeagueSettings,
} from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Bar } from '@/components/charts';
import { CompetitorActions } from '@/components/competitor-actions';
import { Avatar, Badge, Button, Card, CardTitle, Kpi, Notice, PageHeader, SkeletonKpis, SkeletonRows, Table, Td } from '@/components/ui';
import { competitionRights } from '@/lib/access';
import { api, tryApi } from '@/lib/api';
import { dateTime, longDate, num } from '@/lib/format';
import { cairoDate, hijriDays } from '@/lib/hijri';
import { BADGE_LABEL, DIVISION, REPORT_REASON, TOURNAMENT_STATUS, divisionName, tournamentDisplay } from '@/lib/labels';
import { resolveReport, runRollover, saveLeagueSettings } from './actions';
import { CompetitorFlags, HIDDEN_NAME, Medal, PhotoHistory, SnapshotLine, StandingsTable, competitorState } from './parts';

const TABS = [
  { key: 'tournaments', label: 'البطولات' },
  { key: 'leagues', label: 'الدوري الأسبوعي' },
  { key: 'leaderboard', label: 'لوحة المستويات' },
  { key: 'moderation', label: 'الإشراف' },
  { key: 'badges', label: 'الشارات' },
] as const;
type Tab = (typeof TABS)[number]['key'];

type Query = { tab?: string; filter?: string; q?: string; scope?: string; country?: string };

/**
 * «المسابقات» (design §11): seasonal tournaments, the weekly league, the level board, moderation of
 * names/photos/participation, and the badge catalogue. Standings are nightly snapshots; aggregates are
 * suppressed under 20. Points and levels only — never which prayers, azkar or tasks.
 */
export default async function CompetitionsPage({ searchParams }: { searchParams: Promise<Query> }) {
  const q = await searchParams;
  const tab: Tab = TABS.some((t) => t.key === q.tab) ? (q.tab as Tab) : 'tournaments';
  const me = await api<AdminMe>('/admin/auth/me');
  const rights = competitionRights(me.role);

  return (
    <div className="space-y-6">
      <PageHeader
        title="المسابقات"
        subtitle="بطولات موسمية، دوري أسبوعي ولوحة مستويات — النقاط والمستويات فقط، بلا أي بيانات عبادة"
        action={
          tab === 'tournaments' && rights.canManage ? (
            <Link href="/competitions/tournaments/new" className="inline-flex min-h-11 items-center rounded-full bg-lapis px-5 text-sm font-medium text-white hover:bg-royal">
              بطولة جديدة
            </Link>
          ) : undefined
        }
      />
      <nav className="flex flex-wrap gap-2" aria-label="أقسام المسابقات">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={`/competitions?tab=${t.key}`}
            aria-current={tab === t.key ? 'page' : undefined}
            className={`inline-flex min-h-10 items-center rounded-full px-4 text-sm transition ${tab === t.key ? 'bg-lapis text-white' : 'bg-white/70 text-muted hover:text-ink'}`}
          >
            {t.label}
          </Link>
        ))}
      </nav>
      {/* Tabs with forms render outside Suspense: with Next 15.5.4 a server action whose form sits
          inside a boundary that streams again in the action response never leaves `pending`. */}
      {tab === 'leagues' && <Leagues canManage={rights.canManage} canRollover={rights.canRollover} />}
      {tab === 'moderation' && <Moderation q={q} canModerate={rights.canModerate} />}
      {(tab === 'tournaments' || tab === 'leaderboard' || tab === 'badges') && (
        <Suspense key={JSON.stringify(q)} fallback={<TabSkeleton />}>
          {tab === 'tournaments' && <Tournaments />}
          {tab === 'leaderboard' && <Leaderboard q={q} />}
          {tab === 'badges' && <Badges />}
        </Suspense>
      )}
    </div>
  );
}

function TabSkeleton() {
  return (
    <div className="space-y-6">
      <SkeletonKpis />
      <SkeletonRows />
    </div>
  );
}

/* ------------------------------------------------------------ tournaments */

/** «{longDate} · {Hijri}» for an instant's Cairo day. */
function dayLabel(d: Date, hijri: Map<string, Parameters<typeof longDate>[1]>) {
  return longDate(d, hijri.get(cairoDate(d)) ?? null);
}

async function Tournaments() {
  const list = await api<AdminTournamentRow[]>('/admin/competitions/tournaments');
  const lastOf = (t: AdminTournamentRow) => new Date(Date.parse(t.endsAt) - 1);
  const hijri = await hijriDays(list.flatMap((t) => [cairoDate(t.startsAt), cairoDate(lastOf(t))]));
  return (
    <Card>
      <CardTitle>البطولات</CardTitle>
      {list.length === 0 ? (
        <p className="text-sm text-muted">لا توجد بطولات بعد.</p>
      ) : (
        <Table head={['البطولة', 'الفترة (بتوقيت القاهرة)', 'الحالة', 'المشاركون', '']}>
          {list.map((t) => {
            const s = TOURNAMENT_STATUS[tournamentDisplay(t)];
            return (
              <tr key={t.id}>
                <Td>
                  <p className="font-medium">{t.titleAr}</p>
                  <p dir="ltr" className="num text-right text-xs text-muted">
                    {t.slug}
                  </p>
                </Td>
                <Td className="text-xs">
                  <p>من {dayLabel(new Date(t.startsAt), hijri)}</p>
                  <p className="mt-1 text-muted">إلى {dayLabel(lastOf(t), hijri)}</p>
                </Td>
                <Td>
                  <Badge tone={s.tone}>{s.label}</Badge>
                </Td>
                <Td className="num">{num(t.participants)}</Td>
                <Td>
                  <Link href={`/competitions/tournaments/${t.id}`} className="text-sm text-lapis">
                    التفاصيل
                  </Link>
                </Td>
              </tr>
            );
          })}
        </Table>
      )}
    </Card>
  );
}

/* ---------------------------------------------------------------- leagues */

async function Leagues({ canManage, canRollover }: { canManage: boolean; canRollover: boolean }) {
  const [settings, stats] = await Promise.all([
    api<LeagueSettings>('/admin/competitions/leagues/settings'),
    api<AdminLeagueStats>('/admin/competitions/leagues/stats'),
  ]);
  const inForce = stats.settingsInForce;
  const counts = stats.members.map((m) => m.count ?? 0);
  const maxCount = Math.max(1, ...counts);
  const rollover = new Date(stats.endsAt);
  const hijri = await hijriDays([cairoDate(rollover), stats.startsOn]);

  return (
    <div className="grid gap-6 xl:grid-cols-[1fr_380px]">
      <div className="space-y-6">
        <Card>
          <CardTitle>هذا الأسبوع</CardTitle>
          <p className="mb-4 text-sm text-muted">
            بدأ {longDate(new Date(`${stats.startsOn}T12:00:00Z`), hijri.get(stats.startsOn) ?? null)} · التدوير القادم {dayLabel(rollover, hijri)} عند منتصف الليل
          </p>
          <div className="grid gap-4 md:grid-cols-3">
            <Kpi label="المجموعات" value={num(stats.groups)} />
            <Kpi label="نسبة النشطين" value={stats.activeShare === null ? '—' : `${num(stats.activeShare)}%`} hint={stats.activeShare === null ? 'تُخفى تحت 20 عضواً' : 'من لهم نقاط في لقطة الليلة'} />
            <Kpi
              label="الأسبوع الماضي: صعود / هبوط"
              value={stats.lastWeek ? `${stats.lastWeek.up === null ? '—' : num(stats.lastWeek.up)} / ${stats.lastWeek.down === null ? '—' : num(stats.lastWeek.down)}` : '—'}
              hint={stats.lastWeek ? 'تُخفى الأعداد تحت 20' : 'لا يوجد أسبوع مغلق بعد'}
            />
          </div>
          <div className="mt-6 space-y-4">
            <p className="text-sm font-medium">الأعضاء في كل قسم</p>
            {stats.members.map((m) => (
              <Bar key={m.division} label={divisionName(m.division, inForce.divisionNames)} value={m.count} suffix=" عضو" max={maxCount} />
            ))}
          </div>
        </Card>
        <Card>
          <CardTitle>إعدادات الدوري</CardTitle>
          <ActionForm action={saveLeagueSettings} className="space-y-4" success="حُفظت — تُطبَّق من الأسبوع القادم">
            <fieldset disabled={!canManage} className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-3">
                <div>
                  <label className="label" htmlFor="groupSize">
                    حجم المجموعة (10–50)
                  </label>
                  <input id="groupSize" name="groupSize" type="number" min={10} max={50} required defaultValue={settings.groupSize} className="field num" dir="ltr" />
                </div>
                <div>
                  <label className="label" htmlFor="promote">
                    يصعدون (1–10)
                  </label>
                  <input id="promote" name="promote" type="number" min={1} max={10} required defaultValue={settings.promote} className="field num" dir="ltr" />
                </div>
                <div>
                  <label className="label" htmlFor="demote">
                    يبدأون في القسم الأدنى (0–10)
                  </label>
                  <input id="demote" name="demote" type="number" min={0} max={10} required defaultValue={settings.demote} className="field num" dir="ltr" />
                </div>
              </div>
              <div>
                <p className="label">أسماء الأقسام (اتركها فارغة للأسماء الافتراضية)</p>
                <div className="grid gap-2">
                  {[1, 2, 3, 4, 5, 6].map((d) => (
                    <div key={d} className="grid grid-cols-[28px_1fr_1fr] items-center gap-2">
                      <span className="num text-center text-sm text-muted">{d}</span>
                      <input
                        name={`nameAr${d}`}
                        aria-label={`اسم القسم ${d} بالعربية`}
                        maxLength={24}
                        placeholder={DIVISION[d]}
                        defaultValue={settings.divisionNames?.[d - 1]?.ar ?? ''}
                        className="field"
                      />
                      <input
                        name={`nameEn${d}`}
                        aria-label={`Division ${d} name in English`}
                        maxLength={24}
                        placeholder={['Bronze', 'Silver', 'Gold', 'Emerald', 'Ruby', 'Diamond'][d - 1]}
                        defaultValue={settings.divisionNames?.[d - 1]?.en ?? ''}
                        dir="ltr"
                        className="field text-left"
                      />
                    </div>
                  ))}
                </div>
              </div>
              <Notice tone="blue">تُطبَّق التغييرات من الأسبوع القادم — الأسبوع الجاري يبقى على الإعدادات التي بدأ بها.</Notice>
              {canManage && <Button>حفظ الإعدادات</Button>}
            </fieldset>
          </ActionForm>
        </Card>
      </div>
      <div className="space-y-6">
        <Card>
          <CardTitle>المعمول به هذا الأسبوع</CardTitle>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between">
              <dt className="text-muted">حجم المجموعة</dt>
              <dd className="num">{num(inForce.groupSize)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted">يصعدون</dt>
              <dd className="num">{num(inForce.promote)}</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted">يبدأون في القسم الأدنى</dt>
              <dd className="num">{num(inForce.demote)}</dd>
            </div>
            <div className="flex justify-between gap-3">
              <dt className="text-muted">الأقسام</dt>
              <dd className="text-left">{[1, 2, 3, 4, 5, 6].map((d) => divisionName(d, inForce.divisionNames)).join(' · ')}</dd>
            </div>
          </dl>
        </Card>
        <Card>
          <CardTitle>مجموعة بعينها</CardTitle>
          <form action="/competitions/leagues/groups" className="flex gap-2">
            <label className="sr-only" htmlFor="group-id">
              معرّف المجموعة
            </label>
            <input id="group-id" name="id" required placeholder="معرّف المجموعة" dir="ltr" className="field num text-left" />
            <Button variant="ghost">عرض</Button>
          </form>
          <p className="mt-2 text-xs text-muted">عرض للقراءة فقط: الترتيب من لقطة الليلة، والنتائج النهائية بعد الإغلاق.</p>
        </Card>
        {canRollover && (
          <Card>
            <CardTitle>تشغيل التدوير الآن</CardTitle>
            <p className="mb-3 text-sm text-muted">يغلق الأسابيع المستحقة، ويلتقط لقطة الليلة، ويغلق البطولات المنتهية — كما تفعل المهمة كل ساعة.</p>
            <ActionForm action={runRollover} className="space-y-2" success="شُغّلت المهمة">
              <input name="reason" aria-label="سبب التشغيل" placeholder="سبب التشغيل اليدوي" required minLength={3} maxLength={500} className="field" />
              <p className="text-xs text-muted">يُسجَّل في سجل التدقيق</p>
              <Button variant="ghost">تشغيل التدوير الآن</Button>
            </ActionForm>
          </Card>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------ leaderboard */

interface AdminLeaderboard {
  scope: 'global' | 'country';
  country: string | null;
  snapshotDay: string | null;
  rows: AdminStandingRow[];
  levels: { level: number; count: number | null }[];
}

async function Leaderboard({ q }: { q: Query }) {
  const scope = q.scope === 'country' ? 'country' : 'global';
  const country = (q.country ?? '').trim().toUpperCase();
  const qs = new URLSearchParams({ scope });
  if (scope === 'country' && country) qs.set('country', country);
  const res = scope === 'country' && !/^[A-Z]{2}$/.test(country) ? null : await tryApi<AdminLeaderboard>(`/admin/competitions/leaderboard?${qs}`);
  const board = res?.data ?? null;
  const maxLevel = Math.max(1, ...(board?.levels.map((l) => l.count ?? 0) ?? []));
  return (
    <div className="grid gap-6 xl:grid-cols-[1fr_340px]">
      <Card>
        <CardTitle>لوحة المستويات</CardTitle>
        <form action="/competitions" className="mb-4 flex flex-wrap items-end gap-3">
          <input type="hidden" name="tab" value="leaderboard" />
          <div>
            <label className="label" htmlFor="scope">
              اللوحة
            </label>
            <select id="scope" name="scope" defaultValue={scope} className="field w-44">
              <option value="global">كل الدول</option>
              <option value="country">دولة واحدة</option>
            </select>
          </div>
          <div>
            <label className="label" htmlFor="country">
              رمز الدولة (للوحة الدولة)
            </label>
            <input id="country" name="country" defaultValue={country} placeholder="EG" maxLength={2} dir="ltr" className="field num w-24 text-left uppercase" />
          </div>
          <Button variant="ghost">عرض</Button>
        </form>
        {scope === 'country' && !/^[A-Z]{2}$/.test(country) ? (
          <p className="text-sm text-muted">اكتب رمز الدولة بحرفين لاتينيين (مثل EG).</p>
        ) : !board ? (
          <Notice tone="red">{res?.error ?? 'تعذّر تحميل اللوحة'}</Notice>
        ) : board.rows.length === 0 ? (
          <p className="text-sm text-muted">لا أحد في اللوحة بعد — تُلتقط كل ليلة.</p>
        ) : (
          <StandingsTable rows={board.rows} points={false} />
        )}
        <SnapshotLine day={board?.snapshotDay} />
      </Card>
      <Card className="h-fit">
        <CardTitle>توزيع المستويات</CardTitle>
        <div className="space-y-4">
          {(board?.levels ?? LEVELS.map((_, i) => ({ level: i + 1, count: null }))).map((l) => (
            <Bar key={l.level} label={`${num(l.level)} · ${LEVELS[l.level - 1]?.ar ?? ''}`} value={l.count} suffix=" عضو" max={maxLevel} />
          ))}
        </div>
        <p className="mt-4 text-xs text-muted">من لقطة الليلة لأعضاء اللوحة فقط؛ الأعداد تحت 20 مخفية.</p>
      </Card>
    </div>
  );
}

/* ------------------------------------------------------------- moderation */

const FILTERS = [
  { key: '', label: 'الكل' },
  { key: 'reported', label: 'مُبلَّغ عنه' },
  { key: 'hidden', label: 'مخفي' },
  { key: 'banned', label: 'موقوف' },
  { key: 'recent_photo', label: 'صور حديثة' },
] as const;

async function Moderation({ q, canModerate }: { q: Query; canModerate: boolean }) {
  const filter = FILTERS.some((f) => f.key === q.filter) ? (q.filter as string) : '';
  const qs = new URLSearchParams();
  if (filter) qs.set('filter', filter);
  if (q.q) qs.set('q', q.q);
  const [list, reports] = await Promise.all([
    api<{ items: AdminCompetitorRow[] }>(`/admin/competitions/competitors?${qs}`),
    api<{ items: AdminReportRow[] }>('/admin/competitions/reports?status=open'),
  ]);
  return (
    <div className="space-y-6">
      {reports.items.length > 0 && (
        <Card>
          <CardTitle>البلاغات المفتوحة</CardTitle>
          <Table head={['المُبلَّغ عنه', 'السبب', 'البلاغات', 'منذ', ...(canModerate ? ['القرار'] : [])]}>
            {reports.items.map((r) => (
              <tr key={r.id}>
                <Td>
                  <div className="flex items-center gap-3">
                    <Avatar avatar={r.target.avatar} name={r.target.name ?? HIDDEN_NAME} photos={canModerate} />
                    <div>
                      <p className="font-medium">{r.target.name ?? HIDDEN_NAME}</p>
                      {r.target.handle && (
                        <p dir="ltr" className="num text-right text-xs text-muted">
                          @{r.target.handle}
                        </p>
                      )}
                    </div>
                  </div>
                </Td>
                <Td>{REPORT_REASON[r.reason]}</Td>
                <Td className="num">{num(r.count)}</Td>
                <Td className="text-muted">{dateTime(r.createdAt)}</Td>
                {canModerate && (
                  <Td>
                    <details>
                      <summary className="cursor-pointer text-sm text-lapis">قرار</summary>
                      <ActionForm action={resolveReport.bind(null, r.id)} className="mt-2 min-w-64 space-y-2" success="عولج البلاغ">
                        <input name="reason" aria-label="سبب القرار" placeholder="سبب القرار" required minLength={3} maxLength={500} className="field" />
                        <p className="text-xs text-muted">يُسجَّل في سجل التدقيق · يشمل كل البلاغات المفتوحة على هذا العضو</p>
                        <div className="flex flex-wrap gap-2">
                          <Button variant="ghost" name="resolution" value="dismissed">
                            تجاهل
                          </Button>
                          <Button name="resolution" value="actioned">
                            تم الإجراء
                          </Button>
                        </div>
                      </ActionForm>
                    </details>
                  </Td>
                )}
              </tr>
            ))}
          </Table>
        </Card>
      )}
      <Card>
        <CardTitle>المشاركون</CardTitle>
        <div className="mb-4 flex flex-wrap items-center gap-2">
          {FILTERS.map((f) => (
            <Link
              key={f.key}
              href={`/competitions?tab=moderation${f.key ? `&filter=${f.key}` : ''}`}
              aria-current={filter === f.key ? 'page' : undefined}
              className={`inline-flex min-h-10 items-center rounded-full px-4 text-sm ${filter === f.key ? 'bg-ink text-white' : 'border border-line bg-white/70 text-muted hover:text-ink'}`}
            >
              {f.label}
            </Link>
          ))}
          <form action="/competitions" className="ms-auto flex gap-2">
            <input type="hidden" name="tab" value="moderation" />
            {filter && <input type="hidden" name="filter" value={filter} />}
            <label className="sr-only" htmlFor="mod-q">
              بحث بالاسم أو المعرّف
            </label>
            <input id="mod-q" name="q" defaultValue={q.q} placeholder="الاسم أو @المعرّف" className="field max-w-56" />
            <Button variant="ghost">بحث</Button>
          </form>
        </div>
        {list.items.length === 0 ? (
          <p className="text-sm text-muted">لا أحد هنا.</p>
        ) : (
          <ul className="divide-y divide-line/70">
            {list.items.map((c) => (
              <li key={c.userId} className="grid gap-4 py-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]" data-testid={`competitor-${c.handle ?? c.userId}`}>
                <div className="flex items-start gap-3">
                  <Avatar avatar={c.avatar} name={c.name ?? HIDDEN_NAME} size={44} photos={canModerate} />
                  <div className="min-w-0 space-y-2">
                    <div>
                      <Link href={`/users/${c.userId}`} className="font-medium text-ink hover:text-lapis">
                        {c.name ?? HIDDEN_NAME}
                      </Link>
                      {c.handle && (
                        <p dir="ltr" className="num text-right text-xs text-muted">
                          @{c.handle}
                        </p>
                      )}
                    </div>
                    <CompetitorFlags c={c} />
                    <p className="text-xs text-muted">القسم: {DIVISION[c.division]}</p>
                  </div>
                </div>
                <div className="space-y-3">
                  {canModerate ? <PhotoHistory c={c} /> : <p className="text-xs text-muted">سجل الصور متاح للدعم فقط.</p>}
                  {canModerate && (
                    <details>
                      <summary className="cursor-pointer text-sm text-lapis">إجراء</summary>
                      <div className="mt-3">
                        <CompetitorActions state={competitorState(c)} />
                      </div>
                    </details>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}

/* ----------------------------------------------------------------- badges */

async function Badges() {
  const { items } = await api<{ items: { kind: BadgeKind; count: number | null }[] }>('/admin/competitions/badges');
  return (
    <div className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {items.map((b) => (
          <Card key={b.kind}>
            <div className="flex items-start gap-4">
              <Medal />
              <div className="min-w-0 flex-1">
                <p className="font-bold text-ink">{BADGE_LABEL[b.kind]?.label ?? b.kind}</p>
                <p className="mt-1 text-xs text-muted">{BADGE_LABEL[b.kind]?.hint}</p>
                <p dir="ltr" className="num mt-2 text-right text-[11px] text-muted">
                  {b.kind}
                </p>
              </div>
              <p className="num text-xl font-semibold text-gold-text" title={b.count === null ? 'أقل من 20 — مخفي' : undefined}>
                {b.count === null ? '—' : num(b.count)}
              </p>
            </div>
          </Card>
        ))}
      </div>
      <Notice tone="gold">الشارات تذكارٌ فقط: لا نقاط إضافية. الأعداد تحت 20 مخفية. شارات المواظبة والمستوى مشتقة من سجل النقاط.</Notice>
    </div>
  );
}
