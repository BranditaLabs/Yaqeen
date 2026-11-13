'use client';

import { useActionState, useState } from 'react';
import { Button, Notice } from '@/components/ui';

type S = { error: string | null; ok?: boolean };

export interface TournamentValues {
  slug: string;
  titleAr: string;
  titleEn: string;
  bodyAr: string;
  bodyEn: string;
  startsOn: string;
  lastDay: string;
  joinLastDay: string;
  badgeAr: string;
  badgeEn: string;
  minPoints: string;
}

export const EMPTY_TOURNAMENT: TournamentValues = {
  slug: '',
  titleAr: '',
  titleEn: '',
  bodyAr: '',
  bodyEn: '',
  startsOn: '',
  lastDay: '',
  joinLastDay: '',
  badgeAr: '',
  badgeEn: '',
  minPoints: '1',
};

/**
 * create / draft: every field · scheduled (published, not started): every field but the slug ·
 * live: only a later last day, with a reason · readonly: ended, closed or cancelled.
 */
export type FormMode = 'create' | 'draft' | 'scheduled' | 'live' | 'readonly';

/**
 * Tournament form (campaigns/new pattern: controlled, so values survive a refused save). Days are
 * whole Cairo calendar days; the API stores Cairo midnights.
 */
export function TournamentForm({
  mode,
  initial,
  presets,
  action,
}: {
  mode: FormMode;
  initial: TournamentValues;
  presets: { key: string; label: string; startsOn: string; lastDay: string }[];
  action: (prev: S, form: FormData) => Promise<S>;
}) {
  const [state, formAction, pending] = useActionState(action, { error: null });
  const [v, setV] = useState(initial);
  const bind = (k: keyof TournamentValues) => ({
    name: k,
    id: `t-${k}`,
    value: v[k],
    onChange: (e: { target: { value: string } }) => setV((cur) => ({ ...cur, [k]: e.target.value })),
  });
  const locked = mode === 'live' || mode === 'readonly';
  const slugLocked = locked || mode === 'scheduled';
  const count = (k: keyof TournamentValues, max: number) => (
    <span className="num">
      {v[k].length}/{max}
    </span>
  );

  return (
    <form action={formAction} className="space-y-5" aria-busy={pending}>
      {presets.length > 0 && !locked && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs text-muted">تعبئة الأيام من التقويم الهجري:</span>
          {presets.map((p) => (
            <button
              key={p.key}
              type="button"
              onClick={() => setV((cur) => ({ ...cur, startsOn: p.startsOn, lastDay: p.lastDay, joinLastDay: '' }))}
              className="inline-flex min-h-10 items-center rounded-full border border-line bg-white/70 px-4 text-sm text-ink hover:bg-white"
            >
              {p.label}
            </button>
          ))}
        </div>
      )}

      <fieldset disabled={locked || pending} className="grid gap-4 md:grid-cols-2">
        <div className="md:col-span-2">
          <label className="label" htmlFor="t-slug">
            المعرّف (حروف لاتينية صغيرة وأرقام و -)
          </label>
          <input {...bind('slug')} required pattern="[a-z0-9\-]{3,40}" maxLength={40} dir="ltr" readOnly={slugLocked} aria-readonly={slugLocked} className={`field num text-left ${slugLocked ? 'bg-ice text-muted' : ''}`} placeholder="ramadan-1448" />
          {mode === 'scheduled' && <p className="mt-1 text-xs text-muted">معرّف البطولة المنشورة ثابت.</p>}
        </div>
        <div>
          <label className="label" htmlFor="t-titleAr">
            العنوان بالعربية ({count('titleAr', 60)})
          </label>
          <input {...bind('titleAr')} required maxLength={60} className="field" />
        </div>
        <div>
          <label className="label" htmlFor="t-titleEn">
            Title (English) ({count('titleEn', 60)})
          </label>
          <input {...bind('titleEn')} required maxLength={60} dir="ltr" className="field text-left" />
        </div>
        <div>
          <label className="label" htmlFor="t-bodyAr">
            الوصف بالعربية ({count('bodyAr', 280)})
          </label>
          <textarea {...bind('bodyAr')} maxLength={280} rows={3} className="field" />
        </div>
        <div>
          <label className="label" htmlFor="t-bodyEn">
            Description (English) ({count('bodyEn', 280)})
          </label>
          <textarea {...bind('bodyEn')} maxLength={280} rows={3} dir="ltr" className="field text-left" />
        </div>
        <p className="text-xs text-muted md:col-span-2">نص تسويقي فقط — لا آيات ولا أحاديث ولا أدعية.</p>
      </fieldset>

      <fieldset disabled={mode === 'readonly' || pending} className="grid gap-4 md:grid-cols-3">
        <legend className="mb-2 text-sm font-medium text-ink">الأيام (بتوقيت القاهرة، أيام كاملة)</legend>
        <div>
          <label className="label" htmlFor="t-startsOn">
            اليوم الأول
          </label>
          <input {...bind('startsOn')} type="date" required disabled={locked} className="field num" />
        </div>
        <div>
          <label className="label" htmlFor="t-lastDay">
            اليوم الأخير
          </label>
          <input {...bind('lastDay')} type="date" required min={mode === 'live' ? initial.lastDay : undefined} className="field num" />
        </div>
        <div>
          <label className="label" htmlFor="t-joinLastDay">
            آخر يوم للانضمام (اختياري)
          </label>
          <input {...bind('joinLastDay')} type="date" disabled={locked} className="field num" />
        </div>
        <p className="text-xs text-muted md:col-span-3">
          تبدأ البطولة عند منتصف ليل اليوم الأول وتنتهي بنهاية اليوم الأخير. الانضمام حتى نهاية اليوم الأخير ما لم تحدد غير ذلك.
        </p>
      </fieldset>

      <fieldset disabled={locked || pending} className="grid gap-4 md:grid-cols-3">
        <div>
          <label className="label" htmlFor="t-badgeAr">
            اسم الشارة بالعربية ({count('badgeAr', 40)})
          </label>
          <input {...bind('badgeAr')} required maxLength={40} className="field" />
        </div>
        <div>
          <label className="label" htmlFor="t-badgeEn">
            Badge name (English) ({count('badgeEn', 40)})
          </label>
          <input {...bind('badgeEn')} required maxLength={40} dir="ltr" className="field text-left" />
        </div>
        <div>
          <label className="label" htmlFor="t-minPoints">
            الحد الأدنى للنقاط لشارة الإتمام
          </label>
          <input {...bind('minPoints')} type="number" min={1} max={100000} required dir="ltr" className="field num" />
        </div>
      </fieldset>

      {mode === 'live' && (
        <div className="space-y-2">
          <Notice tone="blue">البطولة جارية: يمكن تمديد اليوم الأخير فقط.</Notice>
          <label className="label" htmlFor="t-reason">
            سبب التمديد
          </label>
          <input id="t-reason" name="reason" required minLength={3} maxLength={500} className="field" placeholder="مثال: إتاحة أيام إضافية بعد العيد" />
          <p className="text-xs text-muted">يُسجَّل في سجل التدقيق</p>
        </div>
      )}

      {state.error && (
        <p role="alert" className="text-sm text-error">
          {state.error}
        </p>
      )}
      {state.ok && !state.error && (
        <p role="status" className="text-sm text-success">
          تم الحفظ
        </p>
      )}

      {mode !== 'readonly' && (
        <div className="flex flex-wrap gap-2">
          {(mode === 'create' || mode === 'draft') && (
            <>
              <Button name="intent" value="save" variant="ghost" disabled={pending}>
                حفظ كمسودة
              </Button>
              <Button name="intent" value="publish" disabled={pending}>
                حفظ ونشر
              </Button>
            </>
          )}
          {mode === 'scheduled' && (
            <Button name="intent" value="save" disabled={pending}>
              حفظ التعديلات
            </Button>
          )}
          {mode === 'live' && (
            <Button name="intent" value="save" disabled={pending}>
              تمديد البطولة
            </Button>
          )}
        </div>
      )}
    </form>
  );
}
