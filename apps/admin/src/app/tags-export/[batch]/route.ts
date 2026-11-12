import { cookies } from 'next/headers';
import { SESSION_COOKIE } from '@/lib/session';

const API_URL = process.env.API_URL ?? 'http://localhost:4000';

/** The batch CSV for the manufacturer, streamed through with the admin's session (never exposed to JS). */
export async function GET(_req: Request, { params }: { params: Promise<{ batch: string }> }) {
  const { batch } = await params;
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(batch)) return new Response('bad batch', { status: 400 });
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  if (!token) return new Response('unauthorized', { status: 401 });
  const res = await fetch(`${API_URL}/admin/tags/batches/${batch}.csv`, { headers: { Authorization: `Bearer ${token}` }, cache: 'no-store' });
  if (!res.ok) return new Response('not found', { status: res.status });
  return new Response(await res.text(), {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="yaqeen-tags-${batch}.csv"`,
      'Cache-Control': 'no-store',
    },
  });
}
