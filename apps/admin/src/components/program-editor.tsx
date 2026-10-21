'use client';

import { useActionState, useState } from 'react';
import type { PointsSettings, TaskRuleInput } from '@yaqeen/contracts';
import { saveProgram } from '@/app/(dash)/rewards/actions';
import { Button, Notice } from './ui';

const SETTING_FIELDS: { key: keyof PointsSettings; label: string; hint: string; suffix: string }[] = [
  { key: 'dailyTotal', label: 'نقاط اليوم الكامل', hint: 'مجموع قيم المهام المفعّلة يجب أن يساويه', suffix: 'نقطة' },
  { key: 'qadaDayPoints', label: 'الحد الأقصى ليوم القضاء', hint: 'قيمة اليوم كاملاً إذا قُضي لاحقاً', suffix: 'نقطة' },
  { key: 'qadaWindowDays', label: 'مهلة القضاء', hint: '0 يوقف القضاء', suffix: 'يوم' },
  { key: 'challengeLengthDays', label: 'مدة التحدي', hint: 'يسري على المشتركين الحاليين أيضاً', suffix: 'يوم' },
];

export function ProgramEditor({ settings: s0, tasks: t0, editable }: { settings: PointsSettings; tasks: TaskRuleInput[]; editable: boolean }) {
  const [settings, setSettings] = useState(s0);
  const [tasks, setTasks] = useState(t0);
  const [state, action, pending] = useActionState(saveProgram, { error: null });

  const activeTotal = tasks.filter((t) => t.active).reduce((s, t) => s + (Number(t.points) || 0), 0);
  const totalOk = activeTotal === settings.dailyTotal;
  const qadaOk = settings.qadaDayPoints <= settings.dailyTotal;
  const dirty = JSON.stringify({ settings, tasks }) !== JSON.stringify({ settings: s0, tasks: t0 });
  const setTask = (i: number, patch: Partial<TaskRuleInput>) => setTasks(tasks.map((t, j) => (j === i ? { ...t, ...patch } : t)));

  return (
    <form action={action} className="space-y-5">
      <input type="hidden" name="payload" value={JSON.stringify({ settings, tasks })} />

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {SETTING_FIELDS.map((f) => (
          <label key={f.key} className="rounded-tile bg-white/60 p-3">
            <span className="label">{f.label}</span>
            <span className="flex items-center gap-2">
              <input
                type="number"
                min={0}
                disabled={!editable}
                value={settings[f.key]}
                onChange={(e) => setSettings({ ...settings, [f.key]: Number(e.target.value) })}
                className="field num text-center"
              />
              <span className="shrink-0 text-xs text-muted">{f.suffix}</span>
            </span>
            <span className="mt-1.5 block text-[11px] text-muted">{f.hint}</span>
          </label>
        ))}
      </div>

      <div className="overflow-x-auto">
        <table className="w-full text-right text-sm">
          <thead>
            <tr className="border-b border-line text-xs text-muted">
              <th className="px-2 py-2 font-medium">مفعّلة</th>
              <th className="px-2 py-2 font-medium">الاسم في التطبيق</th>
              <th className="px-2 py-2 font-medium">English</th>
              <th className="px-2 py-2 font-medium">النقاط</th>
              <th className="px-2 py-2 font-medium">النسبة</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-line/70">
            {tasks.map((t, i) => (
              <tr key={t.key} className={t.active ? '' : 'opacity-50'}>
                <td className="px-2 py-2">
                  <input
                    type="checkbox"
                    aria-label={`تفعيل ${t.labelAr}`}
                    checked={t.active}
                    disabled={!editable}
                    onChange={(e) => setTask(i, { active: e.target.checked })}
                    className="h-4 w-4 accent-[var(--yq-lapis)]"
                  />
                </td>
                <td className="px-2 py-2">
                  <input value={t.labelAr} disabled={!editable} onChange={(e) => setTask(i, { labelAr: e.target.value })} className="field" />
                </td>
                <td className="px-2 py-2">
                  <input value={t.labelEn} disabled={!editable} dir="ltr" onChange={(e) => setTask(i, { labelEn: e.target.value })} className="field text-left" />
                </td>
                <td className="w-28 px-2 py-2">
                  <input
                    type="number"
                    min={0}
                    value={t.points}
                    disabled={!editable || !t.active}
                    onChange={(e) => setTask(i, { points: Number(e.target.value) })}
                    className="field num text-center"
                  />
                </td>
                <td className="num w-20 px-2 py-2 text-muted">
                  {t.active && settings.dailyTotal ? `${Math.round((t.points / settings.dailyTotal) * 100)}%` : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className={`flex items-center justify-between rounded-chip px-4 py-2.5 text-sm ${totalOk ? 'bg-[#E3F1EA] text-success' : 'bg-[#FDF3F4] text-error'}`}>
        <span>مجموع المهام المفعّلة</span>
        <span className="num font-semibold">
          {activeTotal} / {settings.dailyTotal}
        </span>
      </div>
      {!qadaOk && <Notice tone="red">حد يوم القضاء لا يمكن أن يتجاوز نقاط اليوم الكامل.</Notice>}

      {editable ? (
        <div className="flex flex-wrap items-center gap-3">
          <Button disabled={pending || !totalOk || !qadaOk || !dirty}>{pending ? 'جارٍ الحفظ…' : 'حفظ البرنامج'}</Button>
          {dirty && (
            <button
              type="button"
              onClick={() => {
                setSettings(s0);
                setTasks(t0);
              }}
              className="text-sm text-muted hover:text-ink"
            >
              تراجع عن التغييرات
            </button>
          )}
          <span className="text-xs text-muted">يُطبَّق فوراً على التطبيق. النقاط المكتسبة سابقاً لا تتغير.</span>
        </div>
      ) : (
        <p className="text-xs text-muted">التعديل للمدير العام فقط.</p>
      )}
      {state.error && <p className="text-sm text-error">{state.error}</p>}
      {state.ok && !dirty && <p className="text-sm text-success">تم حفظ البرنامج</p>}
    </form>
  );
}
