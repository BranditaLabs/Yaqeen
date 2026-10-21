import type { AdminMe } from '@yaqeen/contracts';
import { MobileNav, Sidebar } from '@/components/sidebar';
import { api } from '@/lib/api';

export default async function DashLayout({ children }: { children: React.ReactNode }) {
  const me = await api<AdminMe>('/admin/auth/me');
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
