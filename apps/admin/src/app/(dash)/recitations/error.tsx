'use client';

import * as Sentry from '@sentry/nextjs';
import { useRouter } from 'next/navigation';
import { startTransition, useEffect } from 'react';
import { Notice } from '@/components/ui';

/** «التلاوات» failed to load: say so and offer a retry; the sidebar stays. */
export default function RecitationsError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const router = useRouter();
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);
  return (
    <div className="space-y-4" role="alert">
      <h1 className="text-2xl font-bold text-ink">التلاوات</h1>
      <Notice tone="red">تعذّر تحميل قائمة المراجعة. حاول مرة أخرى بعد قليل.</Notice>
      {error.digest && (
        <p dir="ltr" className="num text-right text-xs text-muted">
          ref {error.digest}
        </p>
      )}
      <button
        type="button"
        onClick={() =>
          startTransition(() => {
            router.refresh();
            reset();
          })
        }
        className="inline-flex min-h-11 items-center justify-center rounded-full border border-line bg-white/70 px-5 text-sm font-medium text-ink transition hover:bg-white"
      >
        إعادة المحاولة
      </button>
    </div>
  );
}
