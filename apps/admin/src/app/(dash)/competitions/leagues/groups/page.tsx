import { redirect } from 'next/navigation';

/** «مجموعة بعينها» form target: /competitions/leagues/groups?id=<uuid> → the group page. */
export default async function GroupLookup({ searchParams }: { searchParams: Promise<{ id?: string }> }) {
  const id = ((await searchParams).id ?? '').trim();
  redirect(/^[0-9a-f-]{36}$/i.test(id) ? `/competitions/leagues/groups/${id}` : '/competitions?tab=leagues');
}
