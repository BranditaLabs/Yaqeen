import { api } from '@/lib/api';

/** Downloads the PDPL export as a JSON file. The API audits every export. */
export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const data = await api<unknown>(`/admin/users/${id}/export`);
  return new Response(JSON.stringify(data, null, 2), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Content-Disposition': `attachment; filename="yaqeen-user-${id.slice(0, 8)}.json"`,
      'Cache-Control': 'no-store',
    },
  });
}
