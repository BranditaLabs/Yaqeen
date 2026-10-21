'use client';

import { useActionState, useState } from 'react';
import type { StreakMilestone } from '@yaqeen/contracts';
import { saveMilestones } from '@/app/(dash)/rewards/actions';
import { Button } from './ui';

export function MilestonesEditor({ initial, editable }: { initial: StreakMilestone[]; editable: boolean }) {
  const [rows, setRows] = useState(initial);
  const [state, action, pending] = useActionState(saveMilestones, { error: null });
  const set = (i: number, patch: Partial<StreakMilestone>) => setRows(rows.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  const dupes = new Set(rows.map((r) => r.days)).size !== rows.length;

  return (
    <form action={action} className="space-y-3">
      <input type="hidden" name="payload" value={JSON.stringify([...rows].sort((a, b) => a.days - b.days))} />
      {rows.length === 0 && <p className="text-sm text-muted">لا توجد مكافآت مواظبة.</p>}
      {rows.map((m, i) => (
        <div key={i} className={`grid grid-cols-[auto_1fr_6rem_6rem_auto] items-center gap-2 rounded-chip bg-white/60 p-2 ${m.active ? '' : 'opacity-60'}`}>
          <input
            type="checkbox"
            aria-label="مفعّلة"
            checked={m.active}
            disabled={!editable}
            onChange={(e) => set(i, { active: e.target.checked })}
            className="mx-1 h-4 w-4 accent-[var(--yq-lapis)]"
          />
          <input value={m.labelAr} disabled={!editable} onChange={(e) => set(i, { labelAr: e.target.value })} placeholder="الاسم" className="field" />
          <label className="flex items-center gap-1 text-xs text-muted">
            <input type="number" min={2} value={m.days} disabled={!editable} onChange={(e) => set(i, { days: Number(e.target.value) })} className="field num px-2 text-center" />
            يوم
          </label>
          <label className="flex items-center gap-1 text-xs text-muted">
            <input type="number" min={1} value={m.points} disabled={!editable} onChange={(e) => set(i, { points: Number(e.target.value) })} className="field num px-2 text-center" />
            نقطة
          </label>
          {editable ? (
            <button type="button" onClick={() => setRows(rows.filter((_, j) => j !== i))} className="px-2 text-lg leading-none text-muted hover:text-error" aria-label="حذف">
              ×
            </button>
          ) : (
            <span />
          )}
        </div>
      ))}
      {dupes && <p className="text-sm text-error">لكل مكافأة عدد أيام مختلف.</p>}
      {editable && (
        <div className="flex flex-wrap items-center gap-3">
          <button
            type="button"
            onClick={() => setRows([...rows, { days: (Math.max(0, ...rows.map((r) => r.days)) || 0) + 7, points: 50, labelAr: 'مواظبة', active: true }])}
            className="text-sm text-lapis"
          >
            + إضافة
          </button>
          <Button disabled={pending || dupes}>حفظ</Button>
        </div>
      )}
      {state.error && <p className="text-sm text-error">{state.error}</p>}
      {state.ok && <p className="text-sm text-success">تم الحفظ</p>}
      <p className="text-xs text-muted">تُمنح تلقائياً مرة واحدة لكل مستخدم عند بلوغ عدد الأيام المتتالية (أيام القضاء تُحتسب).</p>
    </form>
  );
}
