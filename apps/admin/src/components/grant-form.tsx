'use client';

import { useActionState, useState } from 'react';
import { grant } from '@/app/(dash)/rewards/actions';
import { Button, Notice } from './ui';

const SEGMENTS = {
  all_enrolled: 'كل المشتركين في التحدي',
  active_7d: 'النشطون خلال 7 أيام',
  streak_gte_7: 'المواظبون 7 أيام',
  all_users: 'كل الحسابات (غير الزوار)',
};

const nf = new Intl.NumberFormat('en-US');

/**
 * Two-step: preview (count recipients) → grant. Inputs are controlled so they survive the
 * server action, and the grant button only works for exactly the values that were previewed.
 */
export function GrantForm() {
  const [state, action, pending] = useActionState(grant, { error: null });
  const [segment, setSegment] = useState('all_enrolled');
  const [points, setPoints] = useState('');
  const [reasonAr, setReason] = useState('');
  const key = JSON.stringify({ segment, points: Number(points), reasonAr });
  const previewed = !!state.previewKey && state.previewKey === key && !state.ok;

  return (
    <form action={action} className="space-y-3">
      <div className="grid gap-3 md:grid-cols-[2fr_1fr]">
        <select name="segment" className="field" value={segment} onChange={(e) => setSegment(e.target.value)}>
          {Object.entries(SEGMENTS).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
        <input
          name="points"
          type="number"
          min={1}
          max={5000}
          required
          value={points}
          onChange={(e) => setPoints(e.target.value)}
          placeholder="النقاط لكل مستخدم"
          className="field num"
        />
      </div>
      <input
        name="reasonAr"
        required
        minLength={3}
        maxLength={120}
        value={reasonAr}
        onChange={(e) => setReason(e.target.value)}
        placeholder="السبب — يظهر للمستخدم في سجل نقاطه (مثال: هدية رمضان)"
        className="field"
      />
      <div className="flex flex-wrap gap-2">
        <Button name="intent" value="preview" variant="ghost" disabled={pending}>احسب المستفيدين</Button>
        <Button name="intent" value="grant" disabled={pending || !previewed}>منح النقاط</Button>
      </div>
      {state.error && <p className="text-sm text-error">{state.error}</p>}
      {previewed && (
        <Notice tone="blue">
          سيستفيد <span className="num font-semibold">{nf.format(state.recipients ?? 0)}</span> مستخدم — إجمالي{' '}
          <span className="num font-semibold">{nf.format(state.totalPoints ?? 0)}</span> نقطة. اضغط «منح النقاط» للتأكيد.
        </Notice>
      )}
      {state.previewKey && state.previewKey !== key && !state.ok && (
        <p className="text-xs text-muted">تغيّرت القيم — احسب المستفيدين مرة أخرى قبل المنح.</p>
      )}
      {state.ok && (
        <Notice tone="gold">
          تم منح النقاط لـ <span className="num">{nf.format(state.recipients ?? 0)}</span> مستخدم وسُجّل في سجل المراجعة. لا يمكن التراجع إلا بتعديل فردي.
        </Notice>
      )}
    </form>
  );
}
