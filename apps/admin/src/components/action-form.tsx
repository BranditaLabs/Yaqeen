'use client';

import { useActionState, type ReactNode } from 'react';

type State = { error: string | null; ok?: boolean };

/** A form bound to a server action that shows the error / success line under it. */
export function ActionForm({
  action,
  children,
  success = 'تم الحفظ',
  className = '',
}: {
  action: (prev: State, form: FormData) => Promise<State>;
  children: ReactNode;
  success?: string;
  className?: string;
}) {
  const [state, formAction, pending] = useActionState(action, { error: null });
  return (
    <form action={formAction} className={className} aria-busy={pending}>
      <fieldset disabled={pending} className="contents">
        {children}
      </fieldset>
      {state.error && <p className="mt-3 text-sm text-error">{state.error}</p>}
      {state.ok && !state.error && <p className="mt-3 text-sm text-success">{success}</p>}
    </form>
  );
}
