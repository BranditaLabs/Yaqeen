import { apiRaw } from '@/lib/api';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Admin photo proxy (design §3.4, §5.7): a member photo support moderates — any status within the
 * 7-day retention — fetched from GET /admin/competitions/competitors/:userId/photos/:photoId/:size
 * with this admin session. The API allows support and super_admin only; any other role gets its 403.
 * Never cached anywhere (`private, no-store`). There is no CSP today; if one with `img-src` is ever
 * added, it must allow 'self' for this route (and the API host for public photos in standings).
 */
export async function GET(_req: Request, { params }: { params: Promise<{ userId: string; photoId: string; size: string }> }) {
  const { userId, photoId, size } = await params;
  if (!UUID.test(userId) || !UUID.test(photoId) || (size !== '96' && size !== '256')) {
    return new Response(null, { status: 404, headers: { 'Cache-Control': 'private, no-store' } });
  }
  const res = await apiRaw(`/admin/competitions/competitors/${userId}/photos/${photoId}/${size}`);
  if (!res.ok) {
    const status = res.status === 401 || res.status === 403 ? 403 : res.status === 404 ? 404 : 502;
    return new Response(null, { status, headers: { 'Cache-Control': 'private, no-store' } });
  }
  return new Response(await res.arrayBuffer(), {
    headers: {
      'Content-Type': res.headers.get('content-type') ?? 'image/webp',
      'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}
