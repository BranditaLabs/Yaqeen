'use client';

import { useActionState } from 'react';
import { addAdmin, hijri } from '@/app/(dash)/settings/actions';
import { ROLE_LABEL } from '@/lib/session';
import { Button, Notice } from './ui';

const MONTHS = ['محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'];

export function HijriForm({ canSave }: { canSave: boolean }) {
  const [state, action, pending] = useActionState(hijri, { error: null });
  return (
    <form action={action} className="space-y-3">
      <div className="grid grid-cols-3 gap-3">
        <div>
          <label className="label">التعديل</label>
          <select name="offsetDays" defaultValue="0" className="field num">
            <option value="-1">-1 يوم</option>
            <option value="0">0</option>
            <option value="1">+1 يوم</option>
          </select>
        </div>
        <div>
          <label className="label">ابتداءً من شهر</label>
          <select name="month" defaultValue="6" className="field">
            {MONTHS.map((m, i) => (
              <option key={m} value={i + 1}>{m}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="label">السنة</label>
          <input name="year" type="number" defaultValue={1448} className="field num" />
        </div>
      </div>
      <div className="flex gap-2">
        <Button name="intent" value="preview" variant="ghost" disabled={pending}>معاينة</Button>
        {canSave && <Button name="intent" value="save" disabled={pending}>اعتماد</Button>}
      </div>
      {state.error && <p className="text-sm text-error">{state.error}</p>}
      {state.preview && (
        <div className="space-y-2">
          {state.preview.warnings.length > 0 && <Notice tone="red">{state.preview.warnings.join(' · ')}</Notice>}
          <ul className="space-y-1 text-sm">
            {state.preview.firstOfMonths.map((d) => (
              <li key={d.gregorian} className="flex justify-between">
                <span>1 {d.hijriMonthNameAr} {d.hijriYear}</span>
                <span className="num text-muted">{d.gregorian}</span>
              </li>
            ))}
          </ul>
          {state.ok && <p className="text-sm text-success">تم الاعتماد ويظهر للمستخدمين خلال 5 دقائق</p>}
        </div>
      )}
    </form>
  );
}

export function AddAdminForm() {
  const [state, action, pending] = useActionState(addAdmin, { error: null });
  return (
    <form action={action} className="grid gap-3 md:grid-cols-2">
      <input name="name" required placeholder="الاسم" className="field" />
      <input name="email" type="email" required placeholder="البريد" dir="ltr" className="field text-left" />
      <select name="role" className="field">
        {Object.entries(ROLE_LABEL).map(([k, v]) => (
          <option key={k} value={k}>{v}</option>
        ))}
      </select>
      <input name="password" type="password" required minLength={12} placeholder="كلمة مرور مؤقتة (12+)" dir="ltr" className="field text-left" />
      <div className="md:col-span-2">
        <Button disabled={pending}>إضافة عضو</Button>
      </div>
      {state.error && <p className="text-sm text-error md:col-span-2">{state.error}</p>}
      {state.secret && (
        <div className="md:col-span-2">
          <Notice>
            يظهر مرة واحدة — أضفه إلى تطبيق المصادقة:
            <code dir="ltr" className="mt-2 block break-all text-xs">{state.secret}</code>
          </Notice>
        </div>
      )}
    </form>
  );
}
