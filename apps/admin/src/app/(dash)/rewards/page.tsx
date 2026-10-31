import Link from 'next/link';
import type { AdminMe, PointsSettings, ShopifyStatus, StreakMilestone, TaskRuleInput } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { CollectionPicker } from '@/components/collection-picker';
import { GrantForm } from '@/components/grant-form';
import { MilestonesEditor } from '@/components/milestones-editor';
import { ProgramEditor } from '@/components/program-editor';
import { Badge, Button, Card, CardTitle, Kpi, Notice, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { date, dateTime, num, pct } from '@/lib/format';
import { saveBonus, saveReward } from './actions';

interface Program {
  settings: PointsSettings;
  tasks: TaskRuleInput[];
  bonuses: { kind: string; labelAr: string; points: number; enabled: boolean }[];
  milestones: StreakMilestone[];
  totals: Record<string, number>;
}
interface RewardRow {
  id: string;
  titleAr: string;
  titleEn: string;
  kind: 'fixed_amount' | 'percentage' | 'free_shipping';
  value: number;
  costPoints: number;
  monthlyCap: number | null;
  perUserMonthlyLimit: number | null;
  validityDays: number;
  shopifyCollectionIds: string[];
  active: boolean;
  redeemedThisMonth: number;
}
interface RedemptionRow { id: string; code: string; status: string; costPoints: number; createdAt: string; reward: string; user: string | null }
interface GrantRow { id: string; segment: string; points: number; reasonAr: string; recipients: number; createdAt: string }

const TABS = [
  { key: 'program', label: 'البرنامج والمهام' },
  { key: 'streaks', label: 'المواظبة والمكافآت الإضافية' },
  { key: 'catalogue', label: 'كتالوج المكافآت' },
  { key: 'grants', label: 'منح نقاط' },
  { key: 'log', label: 'سجل الاستبدال' },
] as const;
type Tab = (typeof TABS)[number]['key'];

const KIND = { fixed_amount: 'مبلغ ثابت (جنيه)', percentage: 'نسبة %', free_shipping: 'شحن مجاني' };
const REASON: Record<string, string> = {
  task: 'مهام', qada: 'قضاء', bonus: 'إضافية', milestone: 'مواظبة', grant: 'منح', admin_adjustment: 'تعديل إداري', redemption: 'استبدال', reversal: 'استرجاع',
};
const SEGMENT: Record<string, string> = {
  all_enrolled: 'المشتركون', active_7d: 'النشطون 7 أيام', streak_gte_7: 'المواظبون 7 أيام', all_users: 'كل الحسابات',
};
const STATUS: Record<string, [string, 'blue' | 'green' | 'gray' | 'red']> = {
  issued: ['صادر', 'blue'], used: ['مستخدم', 'green'], expired: ['منتهي', 'gray'], void: ['ملغى', 'red'],
};

function RewardFields({ r }: { r?: RewardRow }) {
  return (
    <div className="grid gap-3 md:grid-cols-3">
      <div className="md:col-span-2">
        <label className="label">الاسم</label>
        <input name="titleAr" defaultValue={r?.titleAr} required className="field" />
      </div>
      <div>
        <label className="label">English</label>
        <input name="titleEn" defaultValue={r?.titleEn} required dir="ltr" className="field text-left" />
      </div>
      <div>
        <label className="label">النوع</label>
        <select name="kind" defaultValue={r?.kind ?? 'fixed_amount'} className="field">
          {Object.entries(KIND).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
      </div>
      <div>
        <label className="label">القيمة (جنيه أو %)</label>
        <input name="value" type="number" defaultValue={r?.value} className="field num" />
      </div>
      <div>
        <label className="label">التكلفة بالنقاط</label>
        <input name="costPoints" type="number" min={1} defaultValue={r?.costPoints} required className="field num" />
      </div>
      <div>
        <label className="label">صلاحية الكود (أيام)</label>
        <input name="validityDays" type="number" min={1} max={365} defaultValue={r?.validityDays ?? 30} className="field num" />
      </div>
      <div>
        <label className="label">حد لكل مستخدم شهرياً</label>
        <input name="perUserMonthlyLimit" type="number" min={1} defaultValue={r?.perUserMonthlyLimit ?? ''} placeholder="بلا حد" className="field num" />
      </div>
      <div>
        <label className="label">إجمالي الأكواد شهرياً</label>
        <input name="monthlyCap" type="number" min={1} defaultValue={r?.monthlyCap ?? ''} placeholder="بلا حد" className="field num" />
      </div>
      <div className="md:col-span-3">
        <label className="label">تقتصر على مجموعات Shopify (اختياري)</label>
        <CollectionPicker initial={r?.shopifyCollectionIds ?? []} />
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input name="active" type="checkbox" defaultChecked={r?.active ?? true} className="h-4 w-4 accent-[var(--yq-lapis)]" /> متاحة في التطبيق
      </label>
    </div>
  );
}

export default async function RewardsPage({ searchParams }: { searchParams: Promise<{ tab?: string }> }) {
  const { tab: rawTab } = await searchParams;
  const tab: Tab = TABS.some((t) => t.key === rawTab) ? (rawTab as Tab) : 'program';
  const me = await api<AdminMe>('/admin/auth/me');
  const isSuper = me.role === 'super_admin';
  const canEditCatalogue = isSuper || me.role === 'marketing';
  const [program, shopify, recent] = await Promise.all([
    api<Program>('/admin/rewards/program'),
    api<ShopifyStatus>('/admin/rewards/shopify/status'),
    api<RedemptionRow[]>('/admin/rewards/redemptions'),
  ]);

  const issued = ['task', 'qada', 'bonus', 'milestone', 'grant'].reduce((s, k) => s + (program.totals[k] ?? 0), 0);
  const redeemed = -(program.totals.redemption ?? 0) - (program.totals.reversal ?? 0);
  const codes = recent.filter((r) => r.status !== 'void');
  const used = codes.filter((r) => r.status === 'used').length;

  return (
    <>
      <PageHeader
        title="النقاط والمكافآت"
        subtitle="كل قواعد النقاط وكتالوج الهدايا من مكان واحد. كل تغيير يُسجَّل في سجل المراجعة."
        action={<ShopifyPill s={shopify} />}
      />

      <div className="mb-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <Kpi label="نقاط مُنحت" value={num(issued)} hint={`اليوم الكامل ${num(program.settings.dailyTotal)} · قضاء حتى ${num(program.settings.qadaDayPoints)}`} />
        <Kpi label="نقاط استُبدلت" value={num(Math.max(0, redeemed))} hint={`${num(codes.length)} كوداً في آخر 200 استبدال`} />
        <Kpi
          label="نسبة استخدام الأكواد"
          value={codes.length ? pct((100 * used) / codes.length) : '—'}
          hint={shopify.webhook.configured ? 'من طلبات Shopify المدفوعة' : 'فعّل Webhook الطلبات لتُحتسب'}
        />
        <Kpi
          label="طلبات بأكواد يقين"
          value={shopify.webhook.configured ? num(used) : '—'}
          hint={
            shopify.webhook.configured
              ? shopify.webhook.lastUsedAt
                ? `آخر طلب ${dateTime(shopify.webhook.lastUsedAt)}`
                : 'لم يصل طلب بعد'
              : 'orders/paid → SHOPIFY_WEBHOOK_SECRET'
          }
        />
      </div>

      <ConversionsStrip c={shopify.conversions} />

      <nav className="mb-4 flex gap-2 overflow-x-auto pb-1">
        {TABS.map((t) => (
          <Link
            key={t.key}
            href={`/rewards?tab=${t.key}`}
            className={`min-h-10 shrink-0 rounded-full px-4 py-2 text-sm ${tab === t.key ? 'bg-lapis text-white' : 'glass text-muted hover:text-ink'}`}
          >
            {t.label}
          </Link>
        ))}
      </nav>

      {tab === 'program' && (
        <Card>
          <CardTitle>قواعد البرنامج والمهام اليومية</CardTitle>
          <ProgramEditor settings={program.settings} tasks={program.tasks} editable={isSuper} />
        </Card>
      )}

      {tab === 'streaks' && (
        <div className="grid gap-4 xl:grid-cols-2">
          <Card>
            <CardTitle>مكافآت المواظبة (تلقائية)</CardTitle>
            <MilestonesEditor initial={program.milestones} editable={isSuper} />
          </Card>
          <Card>
            <CardTitle>المكافآت الإضافية (يسجّلها المستخدم)</CardTitle>
            <Notice>تُحتسب الأهلية على الخادم من التاريخ الهجري واليوم — لا يمكن ادعاؤها في غير وقتها.</Notice>
            <div className="mt-3 space-y-3">
              {program.bonuses.map((b) => (
                <ActionForm key={b.kind} action={saveBonus.bind(null, b.kind)} className="flex flex-wrap items-center gap-2 rounded-chip bg-white/60 p-3">
                  <span className="flex-1 text-sm">{b.labelAr}</span>
                  <input name="points" type="number" min={0} defaultValue={b.points} disabled={!isSuper} className="field num w-20 text-center" />
                  <label className="flex items-center gap-1.5 text-xs">
                    <input name="enabled" type="checkbox" defaultChecked={b.enabled} disabled={!isSuper} className="accent-[var(--yq-lapis)]" />
                    مفعّل
                  </label>
                  {isSuper && <Button variant="ghost">حفظ</Button>}
                </ActionForm>
              ))}
            </div>
          </Card>
        </div>
      )}

      {tab === 'catalogue' && <Catalogue canEdit={canEditCatalogue} />}
      {tab === 'grants' && <Grants canGrant={isSuper} />}
      {tab === 'log' && <Log />}

      {tab !== 'catalogue' && tab !== 'log' && (
        <Card className="mt-4">
          <CardTitle>توزيع النقاط حسب المصدر</CardTitle>
          <div className="flex flex-wrap gap-2">
            {Object.entries(program.totals).map(([k, v]) => (
              <span key={k} className="rounded-full bg-white/70 px-3 py-1.5 text-sm">
                {REASON[k] ?? k} <span className={`num ${v < 0 ? 'text-error' : 'text-ink'}`}>{num(v)}</span>
              </span>
            ))}
          </div>
        </Card>
      )}
    </>
  );
}

async function Catalogue({ canEdit }: { canEdit: boolean }) {
  const rewards = await api<RewardRow[]>('/admin/rewards');
  return (
    <Card>
      <CardTitle>كتالوج المكافآت — أكواد خصم Shopify لمرة واحدة</CardTitle>
      <div className="space-y-3">
        {rewards.map((r) => (
          <details key={r.id} className="rounded-tile bg-white/60 p-4">
            <summary className="flex cursor-pointer list-none flex-wrap items-center gap-3">
              <span className="flex-1 font-medium">{r.titleAr}</span>
              <span className="text-xs text-muted">
                هذا الشهر <span className="num">{num(r.redeemedThisMonth)}{r.monthlyCap ? ` / ${num(r.monthlyCap)}` : ''}</span>
              </span>
              <span className="num text-sm text-gold-text">{num(r.costPoints)} نقطة</span>
              <Badge tone={r.active ? 'green' : 'gray'}>{r.active ? 'متاحة' : 'متوقفة'}</Badge>
            </summary>
            {canEdit && (
              <ActionForm action={saveReward.bind(null, r.id)} className="mt-4 space-y-3">
                <RewardFields r={r} />
                <Button variant="ghost">حفظ</Button>
              </ActionForm>
            )}
          </details>
        ))}
      </div>
      {canEdit && (
        <details className="mt-4 rounded-tile border border-dashed border-mist p-4">
          <summary className="cursor-pointer text-sm text-lapis">+ مكافأة جديدة</summary>
          <ActionForm action={saveReward.bind(null, null)} className="mt-4 space-y-3">
            <RewardFields />
            <Button>إضافة</Button>
          </ActionForm>
        </details>
      )}
    </Card>
  );
}

async function Grants({ canGrant }: { canGrant: boolean }) {
  const grants = await api<GrantRow[]>('/admin/rewards/grants');
  return (
    <div className="grid gap-4 xl:grid-cols-[2fr_3fr]">
      <Card>
        <CardTitle>منح نقاط لشريحة</CardTitle>
        {canGrant ? <GrantForm /> : <p className="text-sm text-muted">المنح الجماعي للمدير العام فقط.</p>}
      </Card>
      <Card>
        <CardTitle>المنح السابقة</CardTitle>
        <Table head={['التاريخ', 'السبب', 'الشريحة', 'النقاط', 'المستفيدون']}>
          {grants.map((g) => (
            <tr key={g.id}>
              <Td className="text-muted">{date(g.createdAt)}</Td>
              <Td>{g.reasonAr}</Td>
              <Td>{SEGMENT[g.segment] ?? g.segment}</Td>
              <Td className="num">{num(g.points)}</Td>
              <Td className="num">{num(g.recipients)}</Td>
            </tr>
          ))}
        </Table>
        {grants.length === 0 && <p className="py-6 text-center text-sm text-muted">لا يوجد</p>}
      </Card>
    </div>
  );
}

async function Log() {
  const rows = await api<RedemptionRow[]>('/admin/rewards/redemptions');
  return (
    <Card>
      <CardTitle>آخر الاستبدالات</CardTitle>
      <Table head={['التاريخ', 'المستخدم', 'المكافأة', 'الكود', 'النقاط', 'الحالة']}>
        {rows.map((x) => (
          <tr key={x.id}>
            <Td className="text-muted">{dateTime(x.createdAt)}</Td>
            <Td>{x.user ?? '—'}</Td>
            <Td>{x.reward}</Td>
            <Td className="num"><span dir="ltr">{x.code}</span></Td>
            <Td className="num">{num(x.costPoints)}</Td>
            <Td><Badge tone={STATUS[x.status]?.[1] ?? 'gray'}>{STATUS[x.status]?.[0] ?? x.status}</Badge></Td>
          </tr>
        ))}
      </Table>
      {rows.length === 0 && <p className="py-6 text-center text-sm text-muted">لا توجد استبدالات</p>}
    </Card>
  );
}

const CONVERSION_PLATFORMS = [
  ['meta', 'Meta'],
  ['ga4', 'Google Analytics 4'],
  ['tiktok', 'TikTok'],
] as const;

/** Server-side purchase conversions: flag, salt and which platforms have credentials (never the credentials). */
function ConversionsStrip({ c }: { c: ShopifyStatus['conversions'] }) {
  const any = CONVERSION_PLATFORMS.some(([k]) => c.platforms[k]);
  const live = c.enabled && c.salted && any;
  return (
    <Card className="mb-4 flex flex-wrap items-center gap-x-4 gap-y-2 py-3">
      <span className="text-sm font-medium text-ink">قياس المشتريات للإعلانات</span>
      <Badge tone={live ? 'green' : 'gray'}>{live ? 'يعمل' : c.enabled ? 'مفعّل · ينقصه إعداد' : 'متوقف'}</Badge>
      <span className="flex flex-wrap items-center gap-1.5">
        {CONVERSION_PLATFORMS.map(([k, label]) => (
          <Badge key={k} tone={c.platforms[k] ? 'blue' : 'gray'}>
            <span dir="ltr">{label}</span>
            {c.platforms[k] ? '' : ' · غير مُعد'}
          </Badge>
        ))}
        {!c.salted && <Badge tone="gold">CONVERSIONS_ID_SALT غير مُعد</Badge>}
      </span>
      <span className="text-xs text-muted">
        {c.lastSentAt ? `آخر إرسال ${dateTime(c.lastSentAt)}` : 'لم يُرسل شيء بعد'} · بموافقة «قياس الإعلانات» فقط، دون أي بيانات عبادة أو تواصل
      </span>
    </Card>
  );
}

function ShopifyPill({ s }: { s: ShopifyStatus }) {
  if (!s.configured) return <Badge tone="gray">Shopify غير مُعد</Badge>;
  if (!s.connected) {
    return (
      <span title={s.lastError ?? ''}>
        <Badge tone="red">تعذّر الاتصال · <span dir="ltr">{s.domain}</span></Badge>
      </span>
    );
  }
  const missing = !s.scopes.includes('write_discounts');
  return (
    <span className="flex items-center gap-2">
      <Badge tone="green">
        متصل · <span dir="ltr">{s.domain}</span>
      </Badge>
      {missing && <Badge tone="gold">ينقص صلاحية write_discounts</Badge>}
      {s.lastError && <span className="text-xs text-error" title={s.lastError}>آخر خطأ {s.lastErrorAt ? dateTime(s.lastErrorAt) : ''}</span>}
    </span>
  );
}
