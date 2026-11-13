import type { CompetitorAction } from '@yaqeen/contracts';
import { competitorAction } from '@/app/(dash)/competitions/actions';
import { ActionForm } from './action-form';
import { Button } from './ui';

/** What support may do to one competitor, from the flags the API row carries. */
export interface CompetitorState {
  userId: string;
  nameHidden: boolean;
  /** An active photo is shown (so it can be hidden). */
  photoActive: boolean;
  /** A photo support removed under 7 days ago can come back. */
  photoRestorable: boolean;
  banned: boolean;
}

const ACTIONS: Record<CompetitorAction, { label: string; done: string; placeholder: string; variant: 'ghost' | 'danger'; note?: string }> = {
  'hide-name': {
    label: 'إخفاء الاسم',
    done: 'أُخفي الاسم',
    placeholder: 'السبب: اسم مسيء، انتحال…',
    variant: 'danger',
    note: 'يُغيَّر المعرّف أيضاً ما لم تكن البطاقة منشورة',
  },
  'restore-name': { label: 'إظهار الاسم', done: 'ظهر الاسم', placeholder: 'سبب إظهار الاسم', variant: 'ghost' },
  'hide-photo': { label: 'إخفاء الصورة', done: 'أُخفيت الصورة', placeholder: 'السبب: صورة غير لائقة…', variant: 'danger' },
  'restore-photo': { label: 'استعادة الصورة', done: 'استُعيدت الصورة', placeholder: 'سبب الاستعادة', variant: 'ghost', note: 'الصور التي أخفاها الدعم خلال 7 أيام فقط' },
  ban: { label: 'إيقاف من المنافسات', done: 'أُوقف من المنافسات', placeholder: 'السبب: إساءة متكررة…', variant: 'danger' },
  unban: { label: 'إلغاء الإيقاف', done: 'أُلغي الإيقاف', placeholder: 'سبب إلغاء الإيقاف', variant: 'ghost' },
};

export function availableActions(s: CompetitorState): CompetitorAction[] {
  const out: CompetitorAction[] = [s.nameHidden ? 'restore-name' : 'hide-name'];
  if (s.photoActive) out.push('hide-photo');
  if (s.photoRestorable) out.push('restore-photo');
  out.push(s.banned ? 'unban' : 'ban');
  return out;
}

/**
 * Support forms (support / super admin only — callers check the role): each needs an audited reason.
 * `actions` narrows the forms when the caller knows less than a full competitor row.
 */
export function CompetitorActions({ state, compact = false, actions }: { state: CompetitorState; compact?: boolean; actions?: readonly CompetitorAction[] }) {
  const shown = actions ?? availableActions(state);
  if (shown.length === 0) return null;
  return (
    <div className={`grid gap-3 ${compact ? 'min-w-64' : 'sm:grid-cols-2'}`}>
      {shown.map((a) => {
        const c = ACTIONS[a];
        return (
          <ActionForm key={a} action={competitorAction.bind(null, state.userId, a)} className="space-y-2 rounded-tile border border-line bg-white/60 p-3" success={c.done}>
            <label className="label" htmlFor={`r-${state.userId}-${a}`}>
              {c.label}
            </label>
            <input id={`r-${state.userId}-${a}`} name="reason" placeholder={c.placeholder} required minLength={3} maxLength={500} className="field" />
            <p className="text-xs text-muted">
              يُسجَّل في سجل التدقيق{c.note ? ` · ${c.note}` : ''}
            </p>
            <Button variant={c.variant}>{c.label}</Button>
          </ActionForm>
        );
      })}
    </div>
  );
}
