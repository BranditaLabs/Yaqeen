import Link from 'next/link';
import type { LedgerEntry } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Badge, Button, Card, CardTitle, Kpi, Notice, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { date, dateTime, num } from '@/lib/format';
import { adjustPoints, setStatus, unpublishCard } from '../actions';
import { USER_STATUS as STATUS } from '@/lib/labels';

interface UserDetail {
  id: string;
  displayName: string | null;
  emailMasked: string | null;
  status: keyof typeof STATUS;
  city: string | null;
  joinedAt: string;
  lastSeenAt: string | null;
  deletionRequestedAt: string | null;
  deletionDueAt: string | null;
  balance: number;
  ledger: LedgerEntry[];
  redemptions: { id: string; code: string; status: string; costPoints: number; createdAt: string }[];
  publicProfile: { handle: string; published: boolean; views: number; url: string } | null;
  tags?: { code: string; kind: string; scans: number; linkedAt: string | null; active: boolean }[];
}

const REASON: Record<LedgerEntry['reason'], string> = {
  task: 'مهمة',
  bonus: 'مكافأة إضافية',
  milestone: 'مكافأة مواظبة',
  grant: 'منح جماعي',
  qada: 'قضاء',
  redemption: 'استبدال',
  admin_adjustment: 'تعديل إداري',
  reversal: 'استرجاع',
};

function daysUntil(iso: string): number {
  return Math.max(0, Math.ceil((new Date(iso).getTime() - Date.now()) / 86_400_000));
}

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const u = await api<UserDetail>(`/admin/users/${id}`);

  return (
    <>
      <PageHeader
        title={u.displayName ?? 'مستخدم'}
        subtitle={`${u.emailMasked ?? 'بدون بريد'} · انضم ${date(u.joinedAt)}`}
        action={
          <div className="flex items-center gap-3">
            {/* Plain link: the route handler streams a file download (audited by the API). */}
            <a href={`/users/${u.id}/export`} className="inline-flex min-h-11 items-center rounded-full border border-line bg-white/70 px-5 text-sm hover:bg-white">
              تصدير بيانات المستخدم
            </a>
            <Link href="/users" className="text-sm text-lapis">→ كل المستخدمين</Link>
          </div>
        }
      />
      {u.status === 'deletion_requested' && u.deletionDueAt && (
        <div className="mb-4">
          <Notice tone="red">
            طلب المستخدم حذف حسابه في {date(u.deletionRequestedAt!)} — يُحذف نهائياً بعد{' '}
            <span className="num">{num(daysUntil(u.deletionDueAt))}</span> يوماً ({date(u.deletionDueAt)}). تسجيل دخوله مجدداً يلغي الطلب.
          </Notice>
        </div>
      )}

      <div className="grid gap-4 md:grid-cols-3">
        <Kpi label="الرصيد" value={num(u.balance)} />
        <Kpi label="آخر ظهور" value={u.lastSeenAt ? date(u.lastSeenAt) : '—'} />
        <Card>
          <p className="text-xs font-medium text-muted">الحالة</p>
          <div className="mt-3 flex items-center gap-2">
            <Badge tone={STATUS[u.status].tone}>{STATUS[u.status].label}</Badge>
            {u.deletionDueAt && u.status === 'deletion_requested' && (
              <span className="text-xs text-error">
                بعد <span className="num">{num(daysUntil(u.deletionDueAt))}</span> يوماً
              </span>
            )}
          </div>
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-[3fr_2fr]">
        <Card>
          <CardTitle>سجل النقاط</CardTitle>
          <Table head={['التاريخ', 'السبب', 'القيمة', 'ملاحظة']}>
            {u.ledger.map((l) => (
              <tr key={l.id}>
                <Td className="text-muted">{dateTime(l.createdAt)}</Td>
                <Td>{REASON[l.reason]}</Td>
                <Td className={`num ${l.delta < 0 ? 'text-error' : 'text-success'}`}>{l.delta > 0 ? `+${num(l.delta)}` : num(l.delta)}</Td>
                <Td className="text-muted">{l.note ?? ''}</Td>
              </tr>
            ))}
          </Table>
        </Card>

        <div className="space-y-4">
          <Card>
            <CardTitle>تعديل النقاط</CardTitle>
            <Notice>كل تعديل يتطلب سبباً ويُسجَّل في سجل المراجعة.</Notice>
            <ActionForm action={adjustPoints.bind(null, u.id)} className="mt-4 space-y-3">
              <div>
                <label className="label">القيمة (سالبة للخصم)</label>
                <input name="delta" type="number" required className="field num" dir="ltr" />
              </div>
              <div>
                <label className="label">السبب</label>
                <select name="reason" required className="field">
                  <option value="technical_compensation">تعويض عن خلل تقني</option>
                  <option value="approved_support">طلب دعم موافَق عليه</option>
                  <option value="fraud_reversal">إلغاء نقاط احتيالية</option>
                </select>
              </div>
              <div>
                <label className="label">ملاحظة</label>
                <input name="note" maxLength={200} className="field" />
              </div>
              <Button>حفظ التعديل</Button>
            </ActionForm>
          </Card>

          <Card>
            <CardTitle>حالة الحساب</CardTitle>
            <ActionForm action={setStatus.bind(null, u.id)} className="space-y-3">
              <select name="status" defaultValue={u.status} className="field">
                {Object.entries(STATUS).map(([k, v]) => (
                  <option key={k} value={k}>
                    {v.label}
                  </option>
                ))}
              </select>
              <input name="reason" placeholder="السبب" required minLength={3} className="field" />
              <Button variant="danger">تحديث الحالة</Button>
            </ActionForm>
          </Card>

          {u.publicProfile && (
            <Card>
              <CardTitle>بطاقة يقين العامة</CardTitle>
              <p className="text-sm">
                <a href={u.publicProfile.url} target="_blank" rel="noreferrer" dir="ltr" className="num text-lapis">
                  @{u.publicProfile.handle}
                </a>{' '}
                <Badge tone={u.publicProfile.published ? 'green' : 'gray'}>{u.publicProfile.published ? 'منشورة' : 'مخفية'}</Badge>
              </p>
              <p className="mt-1 text-sm text-muted">
                فُتحت <span className="num">{num(u.publicProfile.views)}</span> مرة
              </p>
              {(u.tags ?? []).length > 0 && (
                <ul className="mt-3 space-y-1 text-sm">
                  {u.tags!.map((t) => (
                    <li key={t.code} className="flex items-center justify-between gap-2">
                      <Link href={`/tags?code=${t.code}`} className="num text-lapis" dir="ltr">
                        {t.code.slice(0, 4)}-{t.code.slice(4)}
                      </Link>
                      <span className="text-muted">
                        {t.kind === 'medal' ? 'ميدالية' : 'بطاقة'} · <span className="num">{num(t.scans)}</span> مسح{' '}
                        <Badge tone={t.active ? 'green' : 'red'}>{t.active ? 'مفعّلة' : 'موقوفة'}</Badge>
                      </span>
                    </li>
                  ))}
                </ul>
              )}
              {u.publicProfile.published && (
                <ActionForm action={unpublishCard.bind(null, u.id)} className="mt-3 space-y-3">
                  <input name="reason" placeholder="سبب الإخفاء (يُسجَّل في سجل التدقيق)" required minLength={3} className="field" />
                  <Button variant="danger">إخفاء البطاقة</Button>
                </ActionForm>
              )}
            </Card>
          )}

          <Card>
            <CardTitle>الاستبدالات</CardTitle>
            {u.redemptions.length === 0 ? (
              <p className="text-sm text-muted">لا يوجد</p>
            ) : (
              <ul className="space-y-2 text-sm">
                {u.redemptions.map((r) => (
                  <li key={r.id} className="flex justify-between">
                    <span dir="ltr" className="num">{r.code}</span>
                    <span className="text-muted">{r.status} · {num(r.costPoints)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      </div>
    </>
  );
}
