import type { AdminMe, RemoteConfig } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { AddAdminForm, HijriForm } from '@/components/settings-forms';
import { Badge, Button, Card, CardTitle, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime } from '@/lib/format';
import { ROLE_LABEL } from '@/lib/session';
import { saveFlags } from './actions';

const FEATURE_LABEL: Record<string, string> = {
  challenge: 'تحدي 365 يوماً من اليقين',
  rewards: 'استبدال النقاط',
  hifz: 'الحفظ',
  listen: 'الاستماع',
  bonuses: 'المكافآت الإضافية',
};

interface TeamRow { id: string; name: string; email: string; role: keyof typeof ROLE_LABEL; active: boolean; lastLoginAt: string | null }
interface AuditRow { id: string; action: string; targetType: string; targetId: string | null; reason: string | null; createdAt: string; admin: string | null }

export default async function SettingsPage() {
  const me = await api<AdminMe>('/admin/auth/me');
  const isSuper = me.role === 'super_admin';
  const config = await api<RemoteConfig>('/admin/settings/config');
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
                <label key={k} className="flex items-center justify-between rounded-chip bg-white/60 px-3 py-2.5 text-sm">
                  {FEATURE_LABEL[k] ?? k}
                  <input name={k} type="checkbox" defaultChecked={v} className="h-4 w-4 accent-[var(--yq-lapis)]" />
                </label>
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
                  <Td>{a.admin ?? '—'}</Td>
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
