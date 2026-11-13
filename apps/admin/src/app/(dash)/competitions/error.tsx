'use client';

import * as Sentry from '@sentry/nextjs';
import { useRouter } from 'next/navigation';
import { startTransition, useEffect } from 'react';
import { Notice } from '@/components/ui';

/**
 * «المسابقات» failed to load (API down, timeout, a role the API refuses): the section says so and
 * offers a retry, while the sidebar stays. Cards that read on their own show their own notice;
 * this catches what is left (the page frame, a tournament or group that failed outright).
 */
export default function CompetitionsError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  const router = useRouter();
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);
  return (
    <div className="space-y-4" role="alert">
      <h1 className="text-2xl font-bold text-ink">المسابقات</h1>
      <Notice tone="red">تعذّر تحميل المسابقات. حاول مرة أخرى بعد قليل.</Notice>
      {error.digest && (
        <p dir="ltr" className="num text-right text-xs text-muted">
          ref {error.digest}
        </p>
      )}
      {/* The error came from the server render: fetch it again, then clear the boundary. */}
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
