import { headers } from 'next/headers';
import type { AdminMe } from '@yaqeen/contracts';
import { MobileNav, Sidebar } from '@/components/sidebar';
import { api } from '@/lib/api';
import { requireSection } from '@/lib/access';
import { PATH_HEADER, sectionOf } from '@/lib/session';

export default async function DashLayout({ children }: { children: React.ReactNode }) {
  const me = await api<AdminMe>('/admin/auth/me');
  // A direct load of a section the role cannot use is a real 403, decided here before anything
  // streams. Client navigation keeps this layout, so a section's own layout checks again.
  const section = sectionOf((await headers()).get(PATH_HEADER) ?? '/');
  if (section) requireSection(me, section);
  return (
    <div className="mx-auto flex max-w-[1440px] gap-6 p-4">
      <Sidebar me={me} />
      <main className="min-w-0 flex-1 py-2">
        <MobileNav me={me} />
        {children}
      </main>
    </div>
  );
}
