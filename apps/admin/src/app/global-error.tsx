'use client';

import * as Sentry from '@sentry/nextjs';
import { useEffect } from 'react';

/** Last-resort error page: reports the render error, then offers a reload. */
export default function GlobalError({ error }: { error: Error & { digest?: string } }) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);
  return (
    <html lang="ar" dir="rtl">
      <body style={{ fontFamily: 'system-ui', display: 'grid', placeItems: 'center', minHeight: '100vh', margin: 0 }}>
        <div style={{ textAlign: 'center' }}>
          <h1 style={{ fontSize: 20 }}>حدث خطأ غير متوقع</h1>
          <p style={{ color: '#56637F' }}>سُجّل الخطأ لفريق يقين. أعد تحميل الصفحة.</p>
          {error.digest && <p style={{ color: '#56637F', fontSize: 12 }} dir="ltr">ref {error.digest}</p>}
        </div>
      </body>
    </html>
  );
}
