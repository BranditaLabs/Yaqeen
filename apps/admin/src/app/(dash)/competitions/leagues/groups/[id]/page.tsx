import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { AdminMe, AdminStandingRow, LeagueSettings } from '@yaqeen/contracts';
import { Badge, Card, CardTitle, Notice, PageHeader } from '@/components/ui';
import { competitionRights } from '@/lib/access';
import { api, tryApi } from '@/lib/api';
import { longDate, num } from '@/lib/format';
import { hijriDays } from '@/lib/hijri';
import { isUuid } from '@/lib/ids';
import { divisionName } from '@/lib/labels';
import { SnapshotLine, StandingsTable } from '../../../parts';

interface GroupView {
  id: string;
  startsOn: string;
  division: number;
  size: number;
  closedAt: string | null;
  /** The nightly snapshot the open week's ranks come from (servers that send it). */
  snapshotDay?: string | null;
  rows: (AdminStandingRow & { outcome: 'up' | 'stay' | 'down' | null })[];
}

/** One league group, read-only: the nightly snapshot during the week, the finals once closed. */
export default async function LeagueGroupPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const [me, res, settings] = await Promise.all([
    api<AdminMe>('/admin/auth/me'),
    tryApi<GroupView>(`/admin/competitions/leagues/groups/${id}`),
    tryApi<LeagueSettings>('/admin/competitions/leagues/settings'),
  ]);
  const names = settings.data?.divisionNames;
  if (res.code === 'not_found' || !res.data) {
    if (res.code === 'not_found') notFound();
    return <Notice tone="red">{res.error ?? 'تعذّر تحميل المجموعة'}</Notice>;
  }
  const g = res.data;
  const closed = g.closedAt !== null;
  const hijri = await hijriDays([g.startsOn]);
  const { canModerate } = competitionRights(me.role);
  return (
    <>
      <PageHeader
        title={`مجموعة ${divisionName(g.division, names)}`}
        subtitle={`أسبوع ${longDate(new Date(`${g.startsOn}T12:00:00Z`), hijri.get(g.startsOn) ?? null)} · ${num(g.size)} عضو`}
        action={
          <div className="flex items-center gap-3">
            <Badge tone={closed ? 'gray' : 'green'}>{closed ? 'مغلقة' : 'جارية'}</Badge>
            <Link href="/competitions?tab=leagues" className="text-sm text-lapis">
              → الدوري الأسبوعي
            </Link>
          </div>
        }
      />
      <Card>
        <CardTitle>{closed ? 'النتائج النهائية' : 'الترتيب'}</CardTitle>
        {g.rows.length === 0 ? (
          <p className="text-sm text-muted">لا أعضاء ظاهرون في هذه المجموعة.</p>
        ) : (
          <StandingsTable
            rows={g.rows}
            podium={closed}
            canModerate={canModerate}
            extra={
              closed
                ? {
                    head: 'النتيجة',
                    // Gentle framing (design §1.4): no red, no «هبوط».
                    cell: (r) =>
                      r.outcome === 'up' ? (
                        <Badge tone="blue">صعد</Badge>
                      ) : r.outcome === 'down' ? (
                        <span className="text-xs text-muted">يبدأ الأسبوع القادم في القسم السابق</span>
                      ) : (
                        <span className="text-xs text-muted">—</span>
                      ),
                  }
                : undefined
            }
          />
        )}
        <SnapshotLine day={closed ? undefined : g.snapshotDay} final={closed} />
      </Card>
    </>
  );
}
