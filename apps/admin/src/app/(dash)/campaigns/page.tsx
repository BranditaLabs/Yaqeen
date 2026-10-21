import Link from 'next/link';
import { Badge, Button, Card, Notice, PageHeader, Table, Td } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime, num } from '@/lib/format';
import { cancelCampaign } from './actions';

interface CampaignRow {
  id: string;
  name: string;
  kind: 'challenge' | 'rewards' | 'offers';
  segment: string;
  status: 'draft' | 'scheduled' | 'sending' | 'sent' | 'cancelled' | 'blocked';
  scheduledAt: string | null;
  estimatedReach: number | null;
  sentCount: number;
  openCount: number;
}

const KIND = { challenge: 'التحدي', rewards: 'المكافآت', offers: 'عروض المتجر' } as const;
const STATUS = {
  draft: ['مسودة', 'gray'],
  scheduled: ['مجدولة', 'blue'],
  sending: ['قيد الإرسال', 'gold'],
  sent: ['أُرسلت', 'green'],
  cancelled: ['ملغاة', 'gray'],
  blocked: ['محجوبة', 'red'],
} as const;

export default async function CampaignsPage() {
  const rows = await api<CampaignRow[]>('/admin/campaigns');
  return (
    <>
      <PageHeader
        title="الحملات"
        subtitle="إشعارات عن بُعد فقط. تذكيرات الأذان والأذكار محلية على الجهاز ولا تُدار من هنا."
        action={
          <Link href="/campaigns/new" className="inline-flex min-h-11 items-center rounded-full bg-lapis px-5 text-sm text-white">
            حملة جديدة
          </Link>
        }
      />
      <Notice tone="blue">
        الضوابط تُطبَّق تلقائياً عند الإرسال: لا إرسال من 10 مساءً حتى 7 صباحاً، ولا قبل الصلاة بـ20 دقيقة أو بعدها بـ30، ولا وقت الجمعة،
        وبحد أقصى إشعار تسويقي واحد يومياً لكل مستخدم، وبموافقة مسبقة فقط.
      </Notice>
      <Card className="mt-4">
        <Table head={['الحملة', 'النوع', 'الحالة', 'الموعد', 'الوصول المتوقع', 'أُرسلت / فُتحت', '']}>
          {rows.map((c) => (
            <tr key={c.id}>
              <Td className="font-medium">{c.name}</Td>
              <Td>{KIND[c.kind]}</Td>
              <Td>
                <Badge tone={STATUS[c.status][1]}>{STATUS[c.status][0]}</Badge>
              </Td>
              <Td className="text-muted">{c.scheduledAt ? dateTime(c.scheduledAt) : '—'}</Td>
              <Td className="num">{c.estimatedReach != null ? num(c.estimatedReach) : '—'}</Td>
              <Td className="num">
                {num(c.sentCount)} / {num(c.openCount)}
              </Td>
              <Td>
                {(c.status === 'scheduled' || c.status === 'draft') && (
                  <form action={cancelCampaign.bind(null, c.id)}>
                    <Button variant="danger">إلغاء</Button>
                  </form>
                )}
              </Td>
            </tr>
          ))}
        </Table>
        {rows.length === 0 && <p className="py-10 text-center text-sm text-muted">لا توجد حملات بعد</p>}
      </Card>
    </>
  );
}
