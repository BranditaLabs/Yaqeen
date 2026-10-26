import Link from 'next/link';
import type { AdminCardRow, AdminMe, CardMetric, CardsSettings, CardsStats } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Bar, LineChart } from '@/components/charts';
import { Badge, Button, Card, CardTitle, Kpi, Notice, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { date, num } from '@/lib/format';
import { moderateCard, releaseHandle, restoreCard, saveCardSettings } from './actions';

const TABS = [
  { key: 'directory', label: 'الدليل' },
  { key: 'numbers', label: 'الأرقام' },
  { key: 'settings', label: 'الإعدادات' },
] as const;
type Tab = (typeof TABS)[number]['key'];

const STATUS = {
  published: 'منشورة',
  hidden: 'مخفية',
  moderated: 'موقوفة بقرار إداري',
} as const;

const METRIC: Record<CardMetric, string> = {
  page_open: 'فتح صفحات البطاقات',
  tag_scan: 'لمسات/مسح الميداليات',
  activation_open: 'فتح صفحة ميدالية جديدة',
  get_app: 'نقرات «حمّل التطبيق»',
  store_click: 'نقرات «تسوّق من المتجر»',
  card_published: 'بطاقات نُشرت',
  tag_activated: 'ميداليات فُعّلت',
};

/** «بطاقة يقين» programme (spec §5.26): directory + moderation, numbers (aggregates only), settings. */
export default async function CardsPage({ searchParams }: { searchParams: Promise<{ tab?: string; search?: string; status?: string }> }) {
  const q = await searchParams;
  const tab: Tab = TABS.some((t) => t.key === q.tab) ? (q.tab as Tab) : 'directory';
  const me = await api<AdminMe>('/admin/auth/me');
  const isSuper = me.role === 'super_admin';
  const canModerate = isSuper || me.role === 'support';
  const canEditSettings = isSuper || me.role === 'marketing';

  return (
    <div className="space-y-6">
      <PageHeader title="البطاقات العامة" subtitle="بطاقة يقين: صفحات المستخدمين العامة والميداليات التي تفتحها — بلا أي بيانات عبادة" />
      <nav className="flex flex-wrap gap-2" aria-label="أقسام البطاقات">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={`/cards?tab=${t.key}`}
            className={`rounded-full px-4 py-2 text-sm transition ${tab === t.key ? 'bg-lapis text-white' : 'bg-white/70 text-muted hover:text-ink'}`}
          >
            {t.label}
          </Link>
        ))}
      </nav>
      {tab === 'directory' && <Directory q={q} canModerate={canModerate} />}
      {tab === 'numbers' && <Numbers />}
      {tab === 'settings' && <Settings canEdit={canEditSettings} />}
    </div>
  );
}

async function Directory({ q, canModerate }: { q: { search?: string; status?: string }; canModerate: boolean }) {
  const qs = new URLSearchParams();
  if (q.search) qs.set('search', q.search);
  if (q.status) qs.set('status', q.status);
  const list = await api<{ items: AdminCardRow[]; nextCursor: string | null }>(`/admin/cards?${qs}`);
  return (
    <Card>
      <form className="mb-4 flex flex-wrap gap-3" action="/cards">
        <input type="hidden" name="tab" value="directory" />
        <input name="search" defaultValue={q.search} placeholder="الاسم أو @المعرّف" className="field max-w-64" />
        <select name="status" defaultValue={q.status ?? ''} className="field max-w-48">
          <option value="">كل البطاقات</option>
          {Object.entries(STATUS).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </select>
        <Button variant="ghost">بحث</Button>
      </form>
      {list.items.length === 0 ? (
        <p className="text-sm text-muted">لا توجد بطاقات.</p>
      ) : (
        <Table head={['البطاقة', 'الحالة', 'مرات الفتح', 'ميداليات', 'آخر تعديل', '']}>
          {list.items.map((c) => (
            <tr key={c.userId}>
              <Td>
                <p className="font-medium">{c.displayName}</p>
                <a href={c.url} target="_blank" rel="noreferrer" dir="ltr" className="num text-xs text-lapis">
                  @{c.handle}
                </a>
                {c.bio && <p className="mt-1 max-w-80 truncate text-xs text-muted">{c.bio}</p>}
              </Td>
              <Td>
                {c.moderated ? (
                  <span title={c.moderationReason ?? ''}>
                    <Badge tone="red">{STATUS.moderated}</Badge>
                  </span>
                ) : (
                  <Badge tone={c.published ? 'green' : 'gray'}>{c.published ? STATUS.published : STATUS.hidden}</Badge>
                )}
              </Td>
              <Td className="num">{num(c.views)}</Td>
              <Td className="num">{num(c.tags)}</Td>
              <Td>{date(c.updatedAt)}</Td>
              <Td>
                <div className="flex items-center gap-3">
                  <Link href={`/users/${c.userId}`} className="text-sm text-lapis">
                    الحساب
                  </Link>
                  {canModerate && (
                    <details>
                      <summary className="cursor-pointer text-sm text-lapis">إجراء</summary>
                      <div className="mt-2 grid min-w-64 gap-3">
                        {c.moderated ? (
                          <ActionForm action={restoreCard.bind(null, c.userId)} className="space-y-2" success="رُفع الإيقاف — يستطيع صاحبها نشرها">
                            <input name="reason" placeholder="سبب رفع الإيقاف" required minLength={3} className="field" />
                            <Button variant="ghost">رفع الإيقاف</Button>
                          </ActionForm>
                        ) : (
                          <ActionForm action={moderateCard.bind(null, c.userId)} className="space-y-2" success="أُوقفت البطاقة">
                            <input name="reason" placeholder="السبب: محتوى مسيء، انتحال…" required minLength={3} className="field" />
                            <Button variant="danger">إيقاف البطاقة</Button>
                          </ActionForm>
                        )}
                        <ActionForm action={releaseHandle.bind(null, c.userId)} className="space-y-2" success="حُرّر المعرّف">
                          <input name="reason" placeholder="سبب تحرير المعرّف (انتحال، علامة تجارية…)" required minLength={3} className="field" />
                          <Button variant="ghost">تحرير المعرّف</Button>
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
  );
}

async function Numbers() {
  const st = await api<CardsStats>('/admin/cards/stats?days=30');
  // Cairo days, counted back from the API's «today» (not the server clock's UTC date).
  const end = Date.parse(`${st.to}T00:00:00Z`);
  const days = Array.from({ length: st.days }, (_, i) => new Date(end - (st.days - 1 - i) * 86_400_000).toISOString().slice(0, 10));
  const seriesOf = (m: CardMetric) => {
    const by = new Map(st.series.filter((r) => r.metric === m).map((r) => [r.date, r.value]));
    return days.map((d) => ({ date: d, value: by.get(d) ?? 0 }));
  };
  const maxBatch = Math.max(1, ...st.activationsByBatch.map((b) => b.total));
  return (
    <div className="space-y-6">
      <div className="grid gap-4 md:grid-cols-3 xl:grid-cols-6">
        <Kpi label="بطاقات منشورة الآن" value={num(st.publishedCards)} />
        <Kpi label="ميداليات مفعّلة" value={num(st.activeTags)} />
        <Kpi label="فتح البطاقات · 30 يوماً" value={num(st.totals.page_open)} />
        <Kpi label="لمسات الميداليات · 30 يوماً" value={num(st.totals.tag_scan)} />
        <Kpi label="«حمّل التطبيق» · 30 يوماً" value={num(st.totals.get_app)} />
        <Kpi label="«تسوّق» · 30 يوماً" value={num(st.totals.store_click)} />
      </div>
      <div className="grid gap-6 lg:grid-cols-2">
        {(['page_open', 'tag_scan', 'get_app', 'store_click', 'card_published', 'tag_activated'] as const).map((m) => (
          <Card key={m}>
            <CardTitle>{METRIC[m]}</CardTitle>
            <LineChart points={seriesOf(m)} height={160} label={METRIC[m]} />
          </Card>
        ))}
      </div>
      <Card>
        <CardTitle>التفعيل حسب الدفعة</CardTitle>
        {st.activationsByBatch.length === 0 ? (
          <p className="text-sm text-muted">لا توجد دفعات بعد.</p>
        ) : (
          <div className="space-y-4">
            {st.activationsByBatch.map((b) => (
              <Bar key={b.batch} label={`${b.batch} · ${num(b.total)} قطعة`} value={b.active} suffix=" مفعّلة" max={maxBatch} tone="gold" />
            ))}
          </div>
        )}
      </Card>
      <Notice tone="blue">أرقام يومية مجمّعة فقط: لا نحفظ من فتح أو مسح أو نقر، ولا أي بيانات عبادة. الروبوتات ومعاينات الروابط لا تُحتسب.</Notice>
    </div>
  );
}

async function Settings({ canEdit }: { canEdit: boolean }) {
  const s = await api<CardsSettings>('/admin/cards/settings');
  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_340px]">
      <Card>
        <CardTitle>إعدادات البطاقات والميداليات</CardTitle>
        <ActionForm action={saveCardSettings} className="space-y-4">
          <fieldset disabled={!canEdit} className="space-y-4">
            <div className="grid gap-3 md:grid-cols-2">
              <div>
                <label className="label">رابط منتج الميدالية في المتجر</label>
                <input name="medalProductUrl" defaultValue={s.medalProductUrl} placeholder="https://www.yaqin-brand.com/products/…" dir="ltr" className="field text-left" />
              </div>
              <div>
                <label className="label">رابط «تسوّق من متجر يقين» في الصفحة</label>
                <input name="storeUrl" defaultValue={s.storeUrl} placeholder="https://www.yaqin-brand.com" dir="ltr" className="field text-left" />
              </div>
            </div>
            <div className="grid gap-3 md:grid-cols-2">
              <div>
                <label className="label">عنوان الدعوة (عربي)</label>
                <input name="ctaTitleAr" defaultValue={s.ctaTitleAr} maxLength={80} placeholder="طمأنينة يومية تبدأ من هنا" className="field" />
              </div>
              <div>
                <label className="label">CTA title (English)</label>
                <input name="ctaTitleEn" defaultValue={s.ctaTitleEn} maxLength={80} placeholder="Daily calm starts here" dir="ltr" className="field text-left" />
              </div>
              <div>
                <label className="label">نص الدعوة (عربي)</label>
                <textarea name="ctaBodyAr" defaultValue={s.ctaBodyAr} maxLength={300} rows={3} className="field" />
              </div>
              <div>
                <label className="label">CTA text (English)</label>
                <textarea name="ctaBodyEn" defaultValue={s.ctaBodyEn} maxLength={300} rows={3} dir="ltr" className="field text-left" />
              </div>
            </div>
            <div>
              <label className="label">معرّفات محجوزة (مفصولة بمسافة أو فاصلة)</label>
              <textarea name="reservedHandles" defaultValue={s.reservedHandles.join(' ')} rows={3} dir="ltr" className="field text-left" placeholder="yaqeen_team brandname" />
            </div>
            {canEdit && <Button>حفظ الإعدادات</Button>}
          </fieldset>
        </ActionForm>
      </Card>
      <div className="space-y-4">
        <Notice tone="gold">الحقول الفارغة تعود للقيم الافتراضية. نص الدعوة يظهر في أسفل كل بطاقة عامة وصفحة الميدالية.</Notice>
        <Notice tone="blue">
          لإيقاف البطاقات العامة أو تفعيل الميداليات مؤقتاً استخدم مفاتيح «المزايا» في{' '}
          <Link href="/settings" className="underline">
            الإعدادات
          </Link>
          .
        </Notice>
        <Notice tone="blue">
          الدفعات وطباعة الميداليات في{' '}
          <Link href="/tags" className="underline">
            الميداليات والبطاقات
          </Link>
          .
        </Notice>
      </div>
    </div>
  );
}
