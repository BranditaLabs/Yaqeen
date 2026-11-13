import Link from 'next/link';
import { forbidden } from 'next/navigation';
import type { AdminMe } from '@yaqeen/contracts';
import { Card, Notice, PageHeader } from '@/components/ui';
import { competitionRights } from '@/lib/access';
import { api } from '@/lib/api';
import { cairoDate, tournamentPresets } from '@/lib/hijri';
import { createTournament } from '../../actions';
import { EMPTY_TOURNAMENT, TournamentForm } from '../tournament-form';

/** New seasonal tournament (marketing / super admin). Saved as a draft, or saved and published. */
export default async function NewTournamentPage() {
  const me = await api<AdminMe>('/admin/auth/me');
  if (!competitionRights(me.role).canManage) forbidden();
  const presets = await tournamentPresets(cairoDate(new Date())).catch(() => []);
  return (
    <>
      <PageHeader
        title="بطولة جديدة"
        subtitle="أيام كاملة بتوقيت القاهرة، شارة تذكارية فقط — لا نقاط إضافية"
        action={
          <Link href="/competitions" className="text-sm text-lapis">
            → المسابقات
          </Link>
        }
      />
      <div className="grid gap-6 xl:grid-cols-[1fr_320px]">
        <Card>
          <TournamentForm mode="create" initial={EMPTY_TOURNAMENT} presets={presets} action={createTournament} />
        </Card>
        <div className="space-y-4">
          <Notice tone="gold">العنوان والوصف نص تسويقي فقط: لا آيات ولا أحاديث ولا أدعية. الترتيب العام يُحدَّث كل ليلة، والشارات تُمنح عند الإغلاق.</Notice>
          <Notice tone="blue">تواريخ «رمضان» و«العشر من ذي الحجة» من التقويم الهجري بتعديل مصر المعتمد في الإعدادات — راجعها قبل النشر.</Notice>
        </div>
      </div>
    </>
  );
}
