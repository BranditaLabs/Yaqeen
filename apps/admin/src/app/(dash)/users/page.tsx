import Link from 'next/link';
import type { AdminUserRow } from '@yaqeen/contracts';
import { Badge, Card, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { date, num } from '@/lib/format';
import { USER_STATUS as STATUS } from '@/lib/labels';

const PROVIDER: Record<AdminUserRow['provider'], string> = { google: 'Google', apple: 'Apple', guest: 'زائر' };

export default async function UsersPage({ searchParams }: { searchParams: Promise<{ search?: string; status?: string; cursor?: string }> }) {
  const sp = await searchParams;
  const qs = new URLSearchParams(Object.entries(sp).filter(([, v]) => v) as [string, string][]);
  const { items, nextCursor } = await api<{ items: AdminUserRow[]; nextCursor: string | null }>(`/admin/users?${qs}`);

  return (
    <>
      <PageHeader title="المستخدمون" subtitle="البريد مُقنَّع. سجل العبادة الشخصي غير متاح من اللوحة." />
      <Card>
        <form className="mb-4 flex flex-wrap gap-3">
          <input name="search" defaultValue={sp.search} placeholder="ابحث بالاسم أو البريد" className="field max-w-xs" />
          <select name="status" defaultValue={sp.status ?? ''} className="field max-w-[180px]">
            <option value="">كل الحالات</option>
            {Object.entries(STATUS).map(([k, v]) => (
              <option key={k} value={k}>
                {v.label}
              </option>
            ))}
          </select>
          <button className="min-h-11 rounded-full bg-lapis px-5 text-sm text-white">تصفية</button>
        </form>

        <Table head={['المستخدم', 'الدخول', 'الحالة', 'يوم التحدي', 'الرصيد', 'انضم']}>
          {items.map((u) => (
            <tr key={u.id} className="hover:bg-white/50">
              <Td>
                <Link href={`/users/${u.id}`} className="font-medium text-ink hover:text-lapis">
                  {u.displayName ?? '—'}
                </Link>
                <p dir="ltr" className="text-right text-xs text-muted">
                  {u.emailMasked ?? ''}
                </p>
              </Td>
              <Td>{PROVIDER[u.provider]}</Td>
              <Td>
                <Badge tone={STATUS[u.status].tone}>{STATUS[u.status].label}</Badge>
              </Td>
              <Td className="num">{u.challengeDay ? `${u.challengeDay} / 365` : '—'}</Td>
              <Td className="num">{num(u.balance)}</Td>
              <Td className="text-muted">{date(u.joinedAt)}</Td>
            </tr>
          ))}
        </Table>
        {items.length === 0 && <p className="py-10 text-center text-sm text-muted">لا نتائج</p>}
        {nextCursor && (
          <div className="mt-4 text-center">
            <Link
              className="text-sm text-lapis"
              href={`/users?${new URLSearchParams({ ...Object.fromEntries(qs), cursor: nextCursor })}`}
            >
              التالي ←
            </Link>
          </div>
        )}
      </Card>
    </>
  );
}
