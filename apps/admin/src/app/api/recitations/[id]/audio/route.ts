import { apiRaw } from '@/lib/api';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Admin audio proxy for «التلاوات»: a recording in the moderation queue, fetched from
 * GET /admin/recordings/:id/audio with this admin session (religious_reviewer, support, super_admin).
 * The API answers 404 for anything not in the queue — admins never browse a user's recordings.
 * Byte ranges pass through (the browser's player seeks with them). Never cached.
 */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const noStore = { 'Cache-Control': 'private, no-store' };
  if (!UUID.test(id)) return new Response(null, { status: 404, headers: noStore });
  const range = req.headers.get('range');
  const res = await apiRaw(`/admin/recordings/${id}/audio`, range ? { range } : undefined);
  if (!res.ok) {
    const status = res.status === 401 || res.status === 403 ? 403 : res.status === 404 ? 404 : res.status === 416 ? 416 : 502;
    return new Response(null, { status, headers: noStore });
  }
  const headers: Record<string, string> = {
    ...noStore,
    'Content-Type': res.headers.get('content-type') ?? 'audio/mp4',
    'Accept-Ranges': 'bytes',
    'X-Content-Type-Options': 'nosniff',
  };
  const cr = res.headers.get('content-range');
  if (cr) headers['Content-Range'] = cr;
  return new Response(await res.arrayBuffer(), { status: res.status, headers });
}
