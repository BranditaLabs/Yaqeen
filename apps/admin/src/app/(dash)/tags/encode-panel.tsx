'use client';

import { useActionState } from 'react';
import type { AdminEncodeSession } from '@yaqeen/contracts';
import { ActionForm } from '@/components/action-form';
import { Button } from '@/components/ui';
import { type EncodeState, openEncodeSession, revokeEncodeSession } from './actions';

const time = new Intl.DateTimeFormat('ar-EG-u-nu-latn', { hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'short' });

/**
 * «ترميز بالهاتف»: opens a 2-hour staff encoding session for the batch and shows its link once, as
 * a QR for the staff phone and as text. Active sessions can be revoked at once.
 */
export function EncodePanel({ batch, sessions }: { batch: string; sessions: AdminEncodeSession[] }) {
  const [state, action, pending] = useActionState<EncodeState, FormData>(openEncodeSession.bind(null, batch), { error: null });
  const active = sessions.filter((s) => s.active);
  return (
    <div className="space-y-3" data-testid={`encode-${batch}`}>
      <p className="text-xs leading-5 text-muted">
        افتح الرابط على هاتف الموظف (تطبيق يقين) ليكتب رابط كل قطعة على الشرائح الفارغة. الجلسة لهذه الدفعة فقط، وتنتهي بعد ساعتين، ويمكن إيقافها في أي وقت.
      </p>
      <form action={action} aria-busy={pending}>
        <Button variant="ghost" disabled={pending}>
          فتح جلسة ترميز جديدة
        </Button>
      </form>
      {state.error && <p className="text-sm text-error">{state.error}</p>}
      {state.session && (
        <div className="space-y-2 rounded-xl border border-line bg-white p-3">
          <div
            className="mx-auto w-44"
            role="img"
            aria-label="رمز QR لجلسة الترميز"
            // SVG generated on the server by `qrcode` from our own deep link.
            dangerouslySetInnerHTML={{ __html: state.session.qrSvg }}
          />
          <p className="break-all text-left text-xs num" dir="ltr" data-testid="encode-link">
            {state.session.url}
          </p>
          <p className="text-xs text-muted">تنتهي {time.format(new Date(state.session.expiresAt))} · يظهر الرابط مرة واحدة فقط، لا تشاركه خارج فريق التصنيع.</p>
        </div>
      )}
      {active.length > 0 && (
        <ul className="space-y-2">
          {active.map((s) => (
            <li key={s.id} className="flex items-center justify-between gap-2 text-xs">
              <span className="text-muted">جلسة نشطة حتى {time.format(new Date(s.expiresAt))}</span>
              <ActionForm action={revokeEncodeSession.bind(null, batch, s.id)} success="أُوقفت الجلسة">
                <Button variant="danger">إيقاف</Button>
              </ActionForm>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
