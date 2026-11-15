import {
  type AdminCommentItem,
  type AdminMe,
  type AdminRecordingItem,
  type AdminRecordingQueue,
  type RecordingReportReason,
  verseRef,
} from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Badge, Button, Card, CardTitle, Notice, PageHeader } from '@/components/ui';
import { requireSection, recitationRights } from '@/lib/access';
import { api } from '@/lib/api';
import { dateTime, num } from '@/lib/format';
import { decideComment, decideRecording } from './actions';

const REASON: Record<RecordingReportReason, string> = {
  not_recitation: 'ليست تلاوة',
  inappropriate: 'غير لائق',
  spam: 'مزعج',
  other: 'سبب آخر',
};

const REJECT = [
  { key: 'not_matching', label: 'لا تطابق الآيات المختارة' },
  { key: 'unclear', label: 'غير واضحة' },
  { key: 'silence', label: 'صامتة' },
  { key: 'too_long', label: 'أطول من 30 ثانية' },
] as const;

const pct = (x: number | null) => (x === null ? '—' : `${num(Math.round(x * 100))}%`);
const secs = (ms: number) => `${num(Math.round(ms / 1000))} ث`;

/**
 * «التلاوات» (design doc §16): only what sits in the moderation queue — recordings the AI check sent to
 * review, recordings and comments members reported, and what was removed in the last 7 days (to
 * restore). Never a user's list of recordings. The transcript is kept only while an item is queued.
 */
export default async function RecitationsPage() {
  const me = await api<AdminMe>('/admin/auth/me');
  requireSection(me, '/recitations');
  const rights = recitationRights(me.role);
  return (
    <div className="space-y-6">
      <PageHeader title="التلاوات" subtitle="قائمة المراجعة لتلاوات المستخدمين بأصواتهم: ما علّمه الفحص الآلي وما أبلغ عنه الأعضاء فقط" />
      <Notice tone="blue">
        لا تظهر هنا إلا العناصر التي تحتاج قراراً. كل قرار يُسجَّل في سجل التدقيق مع السبب. اعتماد التلاوة أو رفضها للمراجع الشرعي، والبلاغات
        والتعليقات للدعم.
      </Notice>
      {/* No Suspense here: every row carries a decision form, and with Next 15.5.4 a server-action
          form inside a boundary that streams again in the action response never leaves `pending`
          (apps/admin/README.md › Known framework issues). */}
      <Queue rights={rights} />
    </div>
  );
}

async function Queue({ rights }: { rights: ReturnType<typeof recitationRights> }) {
  const q = await api<AdminRecordingQueue>('/admin/recordings/queue');
  return (
    <>
      <Card>
        <CardTitle>
          تلاوات للمراجعة <span className="num text-muted">({num(q.recordings.length)})</span>
        </CardTitle>
        {q.recordings.length === 0 ? (
          <p className="text-sm text-muted">لا توجد تلاوات تنتظر قراراً.</p>
        ) : (
          <ul className="divide-y divide-line/70" aria-label="تلاوات للمراجعة">
            {q.recordings.map((r) => (
              <RecordingRow key={r.id} r={r} rights={rights} />
            ))}
          </ul>
        )}
      </Card>
      <Card>
        <CardTitle>
          تعليقات مُبلَّغ عنها <span className="num text-muted">({num(q.comments.length)})</span>
        </CardTitle>
        {q.comments.length === 0 ? (
          <p className="text-sm text-muted">لا توجد تعليقات مُبلَّغ عنها.</p>
        ) : (
          <ul className="divide-y divide-line/70" aria-label="تعليقات مُبلَّغ عنها">
            {q.comments.map((c) => (
              <CommentRow key={c.id} c={c} canModerate={rights.canModerate} />
            ))}
          </ul>
        )}
      </Card>
    </>
  );
}

function Reports({ count, reasons }: { count: number; reasons: RecordingReportReason[] }) {
  if (count === 0) return null;
  return (
    <span className="text-xs text-muted">
      <span className="num">{num(count)}</span> بلاغ · {reasons.map((x) => REASON[x]).join('، ')}
    </span>
  );
}

function RecordingRow({ r, rights }: { r: AdminRecordingItem; rights: ReturnType<typeof recitationRights> }) {
  const ref = verseRef(r.surah, r.fromAyah, r.toAyah, 'ar');
  const act = decideRecording.bind(null, r.id);
  return (
    <li className="space-y-3 py-4" data-testid={`recording-${r.id}`}>
      <div className="flex flex-wrap items-center gap-2">
        <p className="font-medium">{ref}</p>
        {r.flagged && <Badge tone="gold">علّمها الفحص الآلي</Badge>}
        {r.held && <Badge tone="red">محجوبة بالبلاغات</Badge>}
        {r.status === 'removed' && <Badge tone="gray">أُزيلت</Badge>}
        <Badge tone="blue">{r.visibility === 'public' ? 'عامة' : r.visibility === 'members' ? 'للأعضاء' : 'خاصة'}</Badge>
        <span className="text-xs text-muted">
          {r.ownerHandle ? <span dir="ltr" className="num">@{r.ownerHandle}</span> : null} · {dateTime(r.createdAt)} · <span className="num">{secs(r.durationMs)}</span>
        </span>
      </div>
      <audio controls preload="none" src={`/api/recitations/${r.id}/audio`} className="h-10 w-full max-w-md" aria-label={`الاستماع: ${ref}`} />
      <dl className="flex flex-wrap gap-x-6 gap-y-1 text-sm">
        <div>
          <dt className="inline text-muted">التطابق: </dt>
          <dd className="num inline">{pct(r.score)}</dd>
        </div>
        <div>
          <dt className="inline text-muted">الكلام: </dt>
          <dd className="num inline">{pct(r.speech)}</dd>
        </div>
        {r.clientScore !== null && (
          <div>
            <dt className="inline text-muted">فحص الجهاز (للعلم فقط): </dt>
            <dd className="num inline">{pct(r.clientScore)}</dd>
          </div>
        )}
        {r.reports > 0 && (
          <div>
            <dt className="inline text-muted">البلاغات: </dt>
            <dd className="inline">
              <Reports count={r.reports} reasons={r.reasons} />
            </dd>
          </div>
        )}
      </dl>
      {r.transcript && (
        <p className="max-w-2xl rounded-xl bg-white/70 px-3 py-2 text-sm leading-7 text-ink" lang="ar">
          <span className="text-xs text-muted">ما سمعه الفحص الآلي: </span>
          {r.transcript}
        </p>
      )}
      <div className="flex flex-wrap gap-4">
        {r.flagged && rights.canVerify && (
          <ActionForm action={act} success="تم القرار" className="flex flex-wrap items-end gap-2">
            <input name="reason" required minLength={3} placeholder="السبب (يُسجَّل)" className="field max-w-60" aria-label="سبب القرار" />
            <select name="rejectReason" defaultValue="" className="field max-w-56" aria-label="سبب الرفض">
              <option value="">— سبب الرفض —</option>
              {REJECT.map((x) => (
                <option key={x.key} value={x.key}>
                  {x.label}
                </option>
              ))}
            </select>
            <Button name="action" value="approve">
              اعتماد
            </Button>
            <Button name="action" value="reject" variant="danger">
              رفض
            </Button>
          </ActionForm>
        )}
        {rights.canModerate && r.status !== 'needs_review' && (
          <ActionForm action={act} success="تم القرار" className="flex flex-wrap items-end gap-2">
            <input name="reason" required minLength={3} placeholder="السبب (يُسجَّل)" className="field max-w-60" aria-label="سبب القرار" />
            {r.status === 'removed' ? (
              <Button name="action" value="restore" variant="ghost">
                استعادة
              </Button>
            ) : (
              <>
                <Button name="action" value="dismiss" variant="ghost">
                  إسقاط البلاغات
                </Button>
                <Button name="action" value="remove" variant="danger">
                  إزالة
                </Button>
              </>
            )}
          </ActionForm>
        )}
      </div>
    </li>
  );
}

function CommentRow({ c, canModerate }: { c: AdminCommentItem; canModerate: boolean }) {
  const act = decideComment.bind(null, c.id);
  return (
    <li className="space-y-2 py-4" data-testid={`comment-${c.id}`}>
      <div className="flex flex-wrap items-center gap-2">
        {c.status === 'hidden' && <Badge tone="red">مخفي تلقائياً</Badge>}
        {c.status === 'removed' && <Badge tone="gray">أُزيل</Badge>}
        <span className="text-xs text-muted">
          {c.authorHandle ? <span dir="ltr" className="num">@{c.authorHandle}</span> : null} · على {verseRef(c.surah, c.fromAyah, c.toAyah, 'ar')} · {dateTime(c.createdAt)}
        </span>
        <Reports count={c.reports} reasons={c.reasons} />
      </div>
      <p className="max-w-2xl whitespace-pre-line text-sm leading-7">{c.text}</p>
      {canModerate && (
        <ActionForm action={act} success="تم القرار" className="flex flex-wrap items-end gap-2">
          <input name="reason" required minLength={3} placeholder="السبب (يُسجَّل)" className="field max-w-60" aria-label="سبب القرار" />
          {c.status === 'removed' ? (
            <Button name="action" value="restore" variant="ghost">
              استعادة
            </Button>
          ) : (
            <>
              <Button name="action" value="dismiss" variant="ghost">
                إسقاط البلاغات
              </Button>
              <Button name="action" value="remove" variant="danger">
                إزالة التعليق
              </Button>
            </>
          )}
        </ActionForm>
      )}
    </li>
  );
}
