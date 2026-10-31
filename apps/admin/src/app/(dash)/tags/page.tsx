import Link from 'next/link';
import type { AdminEncodeSession, AdminMe, AdminTagBatch, AdminTagRow } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Badge, Button, Card, CardTitle, Kpi, Notice, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { date, dateTime, num } from '@/lib/format';
import { assignTag, disableTag, mintBatch, releaseTag, updateBatch, voidBatch } from './actions';
import { EncodePanel } from './encode-panel';

const KIND = { medal: 'ميدالية مفاتيح', card: 'بطاقة' } as const;
const STATUS: Record<AdminTagRow['status'], [string, 'blue' | 'green' | 'gray' | 'red']> = {
  unclaimed: ['غير مفعّلة', 'gray'],
  active: ['مفعّلة', 'green'],
  disabled: ['موقوفة', 'red'],
};
const BATCH: Record<AdminTagBatch['status'], [string, 'blue' | 'green' | 'gray' | 'red' | 'gold']> = {
  ordered: ['طُلبت من المصنع', 'gold'],
  received: ['استُلمت', 'blue'],
  on_sale: ['في المتجر', 'green'],
  void: ['ملغاة', 'red'],
};
const printed = (c: string) => `${c.slice(0, 4)}-${c.slice(4)}`;

/** Physical «بطاقة يقين» tags (spec §5.26): mint batches for the manufacturer, find and moderate tags. */
export default async function TagsPage({ searchParams }: { searchParams: Promise<{ batch?: string; status?: string; code?: string }> }) {
  const q = await searchParams;
  const me = await api<AdminMe>('/admin/auth/me');
  const canMint = me.role === 'super_admin' || me.role === 'marketing';
  const canModerate = me.role === 'super_admin' || me.role === 'support';
  const qs = new URLSearchParams();
  if (q.batch) qs.set('batch', q.batch);
  if (q.status) qs.set('status', q.status);
  if (q.code) qs.set('code', q.code);
  const [batches, list] = await Promise.all([
    api<AdminTagBatch[]>('/admin/tags/batches'),
    api<{ items: AdminTagRow[]; nextCursor: string | null }>(`/admin/tags?${qs}`),
  ]);
  // Staff encoding sessions per open batch (marketing only; tokens are never listed).
  const encodable = canMint ? batches.filter((b) => b.status !== 'void').slice(0, 30) : [];
  const sessions = new Map(
    await Promise.all(encodable.map(async (b) => [b.batch, await api<AdminEncodeSession[]>(`/admin/tags/batches/${encodeURIComponent(b.batch)}/encode-sessions`)] as const)),
  );
  const total = batches.reduce((s, b) => s + b.total, 0);
  const active = batches.reduce((s, b) => s + b.active, 0);

  return (
    <div className="space-y-6">
      <PageHeader title="الميداليات والبطاقات" subtitle="رموز دائمة تُكتب في شريحة NFC وتُطبع كرمز QR، ويفعّلها المشتري من التطبيق" />

      <div className="grid gap-4 md:grid-cols-3">
        <Kpi label="رموز مصدرة" value={num(total)} />
        <Kpi label="مفعّلة" value={num(active)} hint={total ? `${Math.round((active / total) * 100)}% من المصدر` : undefined} />
        <Kpi label="دفعات" value={num(batches.length)} />
      </div>

      <div className="grid gap-6 2xl:grid-cols-[1fr_360px]">
        <Card>
          <CardTitle>الدفعات</CardTitle>
          {batches.length === 0 ? (
            <p className="text-sm text-muted">لا توجد دفعات بعد.</p>
          ) : (
            <Table head={['الدفعة', 'الحالة', 'النوع', 'العدد', 'مفعّلة', 'موقوفة', 'مُرمّزة', 'التاريخ', '']}>
              {batches.map((b) => (
                <tr key={b.batch}>
                  <Td>
                    <Link href={`/tags?batch=${encodeURIComponent(b.batch)}`} className="whitespace-nowrap font-medium text-lapis" dir="ltr">
                      {b.batch}
                    </Link>
                  </Td>
                  <Td>
                    <Badge tone={BATCH[b.status][1]}>{BATCH[b.status][0]}</Badge>
                    {b.note && <p className="mt-1 max-w-48 truncate text-xs text-muted">{b.note}</p>}
                  </Td>
                  <Td>{KIND[b.kind]}</Td>
                  <Td className="num">{num(b.total)}</Td>
                  <Td className="num">{num(b.active)}</Td>
                  <Td className="num">{num(b.disabled)}</Td>
                  <Td className="num whitespace-nowrap">
                    <span dir="ltr">
                      {num(b.encoded)} / {num(b.total - b.disabled)}
                    </span>
                  </Td>
                  <Td className="whitespace-nowrap">{date(b.createdAt)}</Td>
                  <Td>
                    <div className="flex items-center gap-3">
                      <a href={`/tags-export/${encodeURIComponent(b.batch)}`} className="whitespace-nowrap text-sm text-lapis underline-offset-4 hover:underline">
                        تنزيل CSV
                      </a>
                      {sessions.has(b.batch) && (
                        <details>
                          <summary className="cursor-pointer whitespace-nowrap text-sm text-lapis">ترميز بالهاتف</summary>
                          <div className="mt-2 min-w-64">
                            <EncodePanel batch={b.batch} sessions={sessions.get(b.batch) ?? []} />
                          </div>
                        </details>
                      )}
                      {b.status !== 'void' && (canMint || canModerate) && (
                        <details>
                          <summary className="cursor-pointer text-sm text-lapis">إدارة</summary>
                          <div className="mt-2 grid min-w-64 gap-3">
                            {canMint && (
                              <ActionForm action={updateBatch.bind(null, b.batch)} className="space-y-2">
                                <select name="status" defaultValue={b.status} className="field">
                                  {(['ordered', 'received', 'on_sale'] as const).map((st) => (
                                    <option key={st} value={st}>
                                      {BATCH[st][0]}
                                    </option>
                                  ))}
                                </select>
                                <input name="note" defaultValue={b.note} maxLength={500} placeholder="ملاحظة: المصنع، رقم الطلب…" className="field" />
                                <Button variant="ghost">حفظ</Button>
                              </ActionForm>
                            )}
                            <ActionForm action={voidBatch.bind(null, b.batch)} className="space-y-2" success="أُلغيت الدفعة وأُوقفت كل قطعها">
                              <input name="reason" placeholder="سبب الإلغاء: عيب تصنيع…" required minLength={3} className="field" />
                              <Button variant="danger">إلغاء الدفعة وإيقاف كل قطعها</Button>
                            </ActionForm>
                          </div>
                        </details>
                      )}
                    </div>
                  </Td>
                </tr>
              ))}
            </Table>
          )}
        </Card>

        {canMint && (
          <Card>
            <CardTitle>دفعة جديدة</CardTitle>
            <ActionForm action={mintBatch} className="space-y-3" success="تم إصدار الدفعة">
              <div>
                <label className="label">اسم الدفعة</label>
                <input name="batch" required pattern="[A-Za-z0-9_\-]{1,40}" placeholder="medal-2026-11" dir="ltr" className="field text-left" />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="label">النوع</label>
                  <select name="kind" className="field" defaultValue="medal">
                    <option value="medal">{KIND.medal}</option>
                    <option value="card">{KIND.card}</option>
                  </select>
                </div>
                <div>
                  <label className="label">العدد</label>
                  <input name="count" type="number" min={1} max={5000} defaultValue={100} required className="field num" />
                </div>
              </div>
              <Button>إصدار الرموز</Button>
            </ActionForm>
            <div className="mt-4">
              <Notice tone="blue">
                ملف CSV فيه لكل قطعة: الرمز، الرمز المطبوع (XXXX-XXXX) والرابط. اكتب الرابط في الشريحة كسجل NDEF URI (أو رمّزها بنفسك بالهاتف من «ترميز بالهاتف» في صف الدفعة)، واطبعه كرمز QR مع الرمز المطبوع. الرابط يُكتب مرة واحدة إلى الأبد، فتأكد من نطاق البطاقات قبل الإرسال للمصنع.
              </Notice>
            </div>
          </Card>
        )}
      </div>

      <Card>
        <CardTitle>
          الرموز{q.batch ? <span className="ms-2 text-sm font-normal text-muted" dir="ltr">{q.batch}</span> : null}
        </CardTitle>
        <form className="mb-4 flex flex-wrap gap-3" action="/tags">
          {q.batch && <input type="hidden" name="batch" value={q.batch} />}
          <input name="code" defaultValue={q.code} placeholder="ابحث بالرمز" dir="ltr" className="field max-w-48 text-left" />
          <select name="status" defaultValue={q.status ?? ''} className="field max-w-40">
            <option value="">كل الحالات</option>
            {Object.entries(STATUS).map(([k, [label]]) => (
              <option key={k} value={k}>
                {label}
              </option>
            ))}
          </select>
          <Button variant="ghost">تصفية</Button>
        </form>
        {list.items.length === 0 ? (
          <p className="text-sm text-muted">لا نتائج.</p>
        ) : (
          <Table head={['الرمز', 'الحالة', 'الشريحة', 'البطاقة', 'المسح', 'التفعيل', '']}>
            {list.items.map((t) => (
              <tr key={t.code}>
                <Td>
                  <span className="num font-medium" dir="ltr">
                    {printed(t.code)}
                  </span>
                </Td>
                <Td>
                  <Badge tone={STATUS[t.status][1]}>{STATUS[t.status][0]}</Badge>
                </Td>
                <Td>
                  {t.encodedAt ? (
                    <span className="whitespace-nowrap" title={dateTime(t.encodedAt)}>
                      <Badge tone="blue">{t.encodedLocked ? 'مُرمّزة · مقفلة' : 'مُرمّزة'}</Badge>
                    </span>
                  ) : (
                    <span className="text-muted">—</span>
                  )}
                </Td>
                <Td>
                  {t.userId ? (
                    <Link href={`/users/${t.userId}`} className="text-lapis" dir="ltr">
                      {t.handle ? `@${t.handle}` : '—'}
                    </Link>
                  ) : (
                    '—'
                  )}
                </Td>
                <Td className="num">{num(t.scans)}</Td>
                <Td>{t.linkedAt ? date(t.linkedAt) : '—'}</Td>
                <Td>
                  {canModerate && t.status === 'unclaimed' && (
                    <details>
                      <summary className="cursor-pointer text-sm text-lapis">ربط بمستخدم</summary>
                      <ActionForm action={assignTag.bind(null, t.code)} className="mt-2 grid min-w-64 gap-2" success="رُبطت بالحساب">
                        <input name="userId" placeholder="معرّف الحساب (من صفحة المستخدم)" required dir="ltr" className="field text-left" />
                        <input name="reason" placeholder="السبب: العميل لم يستطع التفعيل…" required minLength={3} className="field" />
                        <Button variant="ghost">ربط</Button>
                      </ActionForm>
                    </details>
                  )}
                  {canModerate && t.status !== 'unclaimed' && (
                    <details>
                      <summary className="cursor-pointer text-sm text-lapis">إجراء</summary>
                      <div className="mt-2 grid gap-3">
                        {t.status === 'active' && (
                          <ActionForm action={disableTag.bind(null, t.code)} className="space-y-2" success="تم الإيقاف">
                            <input name="reason" placeholder="السبب: مفقودة، بلاغ…" required minLength={3} className="field" />
                            <Button variant="danger">إيقاف الرمز</Button>
                          </ActionForm>
                        )}
                        <ActionForm action={releaseTag.bind(null, t.code)} className="space-y-2" success="أصبحت جاهزة للتفعيل من جديد">
                          <input name="reason" placeholder="السبب: مرتجعة، استبدال…" required minLength={3} className="field" />
                          <Button variant="ghost">إعادة إصدار كقطعة جديدة</Button>
                        </ActionForm>
                      </div>
                    </details>
                  )}
                </Td>
              </tr>
            ))}
          </Table>
        )}
      </Card>
    </div>
  );
}
