import type { AdminMe, ContentAdminRow, RemoteConfig } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { AddAdminForm, HijriForm } from '@/components/settings-forms';
import { Badge, Button, Card, CardTitle, Notice, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { date, dateTime } from '@/lib/format';
import { CONTENT_STATUS } from '@/lib/labels';
import { ROLE_LABEL } from '@/lib/session';
import { proposeSplashVerse, saveFlags, saveTestDevices } from './actions';

const FEATURE_LABEL: Record<string, string> = {
  challenge: 'تحدي 365 يوماً من اليقين',
  rewards: 'استبدال النقاط',
  hifz: 'الحفظ',
  listen: 'الاستماع',
  bonuses: 'المكافآت الإضافية',
  recite: 'التسميع (تجريبي)',
  ramadan: 'وضع رمضان',
  tafsirFull: 'التفسير الكامل',
  publicCards: 'البطاقات العامة (بطاقة يقين)',
  medalActivation: 'تفعيل الميداليات من التطبيق',
};
const ROLLOUT_FLAGS = ['recite'];

interface TeamRow { id: string; name: string; email: string; role: keyof typeof ROLE_LABEL; active: boolean; lastLoginAt: string | null }
interface AuditRow { id: string; action: string; targetType: string; targetId: string | null; reason: string | null; createdAt: string; admin: string | null }

export default async function SettingsPage() {
  const me = await api<AdminMe>('/admin/auth/me');
  const isSuper = me.role === 'super_admin';
  const config = await api<RemoteConfig>('/admin/settings/config');
  const canProposeVerse = isSuper || me.role === 'content_editor';
  const verses = isSuper || me.role === 'content_editor' || me.role === 'religious_reviewer'
    ? (await api<ContentAdminRow[]>('/admin/content?type=splash_verse')).slice(0, 5)
    : [];
  const [team, auditRows] = isSuper
    ? await Promise.all([api<TeamRow[]>('/admin/settings/team'), api<AuditRow[]>('/admin/settings/audit')])
    : [[], []];

  return (
    <>
      <PageHeader title="الإعدادات" subtitle="التقويم الهجري، الميزات، الإصدارات، الفريق وسجل المراجعة." />

      <div className="grid gap-4 xl:grid-cols-2">
        <Card>
          <CardTitle>
            التقويم الهجري — مصر{' '}
            <Badge tone="blue">
              أم القرى {config.hijri.offsetDays > 0 ? `+${config.hijri.offsetDays}` : config.hijri.offsetDays}
            </Badge>
          </CardTitle>
          <p className="mb-4 text-sm text-muted">
            المصدر: AlAdhan بطريقة أم القرى. عند إعلان دار الإفتاء رؤية مختلفة، عدّل بيوم واحد ابتداءً من الشهر المعني. تمنع المعاينة أي شهر
            بطول غير 29 أو 30 يوماً.
          </p>
          <HijriForm canSave={isSuper || me.role === 'religious_reviewer'} />
        </Card>

        {isSuper && (
          <Card>
            <CardTitle>الميزات والإصدارات</CardTitle>
            <ActionForm action={saveFlags.bind(null, config.features)} className="space-y-3">
              {Object.entries(config.features).map(([k, v]) => (
                <div key={k} className="flex items-center justify-between gap-3 rounded-chip bg-white/60 px-3 py-2.5 text-sm">
                  <label className="flex flex-1 items-center justify-between gap-3">
                    {FEATURE_LABEL[k] ?? k}
                    <input name={k} type="checkbox" defaultChecked={v} className="h-4 w-4 accent-[var(--yq-lapis)]" />
                  </label>
                  {ROLLOUT_FLAGS.includes(k) && (
                    <label className="flex items-center gap-1 text-xs text-muted">
                      لـ
                      <input
                        name={`rollout_${k}`}
                        type="number"
                        min={0}
                        max={100}
                        defaultValue={config.featureRollout?.[k] ?? 100}
                        className="field num w-16 py-1 text-center"
                      />
                      % من المستخدمين
                    </label>
                  )}
                </div>
              ))}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="label">أقل إصدار iOS</label>
                  <input name="minIos" defaultValue={config.minVersion.ios} dir="ltr" className="field num" />
                </div>
                <div>
                  <label className="label">أقل إصدار Android</label>
                  <input name="minAndroid" defaultValue={config.minVersion.android} dir="ltr" className="field num" />
                </div>
              </div>
              <label className="flex items-center justify-between rounded-chip bg-[#FDF3F4] px-3 py-2.5 text-sm text-error">
                وضع الصيانة
                <input name="maintenance" type="checkbox" defaultChecked={config.maintenance.enabled} className="h-4 w-4" />
              </label>
              <input name="maintenanceAr" defaultValue={config.maintenance.messageAr} placeholder="رسالة الصيانة بالعربية" className="field" />
              <input name="maintenanceEn" defaultValue={config.maintenance.messageEn} placeholder="Maintenance message" dir="ltr" className="field text-left" />
              <Button>حفظ</Button>
            </ActionForm>
          </Card>
        )}

        <Card>
          <CardTitle>آية شاشة البداية</CardTitle>
          <p dir="rtl" className="font-[family-name:var(--font-naskh)] text-2xl leading-loose text-ink">{config.splashVerse.textAr}</p>
          <p className="mb-4 text-xs text-gold-text">{config.splashVerse.reference}</p>
          <Notice>أي تغيير يُرسل للمراجعة الشرعية، ولا يظهر في التطبيق قبل اعتماد مراجع غير كاتبه.</Notice>
          {canProposeVerse && (
            <ActionForm action={proposeSplashVerse} className="mt-4 space-y-3" success="أُرسلت للمراجعة الشرعية">
              <textarea name="textAr" required rows={2} placeholder="نص الآية بالرسم العثماني" className="field font-[family-name:var(--font-naskh)] text-xl leading-loose" />
              <input name="reference" required placeholder="السورة: رقم الآية — الرعد: 28" className="field" />
              <Button variant="ghost">إرسال للمراجعة</Button>
            </ActionForm>
          )}
          {verses.length > 0 && (
            <ul className="mt-4 space-y-2 text-sm">
              {verses.map((v) => (
                <li key={v.id} className="flex items-center justify-between gap-2 rounded-chip bg-white/60 px-3 py-2">
                  <span className="truncate">{v.source}</span>
                  <span className="flex items-center gap-2">
                    <span className="text-xs text-muted">{date(v.updatedAt)}</span>
                    <Badge tone={CONTENT_STATUS[v.status].tone}>{CONTENT_STATUS[v.status].label}</Badge>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card>
          <CardTitle>أجهزة الاختبار</CardTitle>
          <p className="mb-3 text-sm text-muted">
            رموز FCM لهواتفك (من شاشة «عن يقين» في نسخة الاختبار) لاستخدام «إرسال تجريبي لجهازي» في الحملات. حتى 5 أجهزة.
          </p>
          <ActionForm action={saveTestDevices} className="space-y-3">
            <textarea name="tokens" rows={3} dir="ltr" placeholder={'fcm-token-1\nfcm-token-2'} className="field text-left font-mono text-xs" />
            <Button variant="ghost">حفظ الأجهزة</Button>
          </ActionForm>
        </Card>

        {isSuper && (
          <Card>
            <CardTitle>الفريق</CardTitle>
            <ul className="mb-5 space-y-2">
              {team.map((t) => (
                <li key={t.id} className="flex items-center justify-between rounded-chip bg-white/60 px-3 py-2 text-sm">
                  <span>
                    {t.name} <span dir="ltr" className="text-xs text-muted">{t.email}</span>
                  </span>
                  <span className="flex items-center gap-2">
                    <Badge tone="blue">{ROLE_LABEL[t.role]}</Badge>
                    {!t.active && <Badge tone="red">موقوف</Badge>}
                  </span>
                </li>
              ))}
            </ul>
            <AddAdminForm />
          </Card>
        )}

        {isSuper && (
          <Card>
            <CardTitle>سجل المراجعة</CardTitle>
            <Table head={['الوقت', 'العضو', 'الإجراء', 'السبب']}>
              {auditRows.map((a) => (
                <tr key={a.id}>
                  <Td className="text-muted">{dateTime(a.createdAt)}</Td>
                  <Td>{a.admin ?? 'المستخدم'}</Td>
                  <Td>
                    <code dir="ltr" className="text-xs">{a.action}</code>
                  </Td>
                  <Td className="text-muted">{a.reason ?? ''}</Td>
                </tr>
              ))}
            </Table>
          </Card>
        )}
      </div>
    </>
  );
}
