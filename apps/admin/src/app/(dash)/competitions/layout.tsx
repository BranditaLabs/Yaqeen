import type { AdminMe } from '@yaqeen/contracts';
import { requireSection } from '@/lib/access';
import { api } from '@/lib/api';

/** «المسابقات»: super admin, marketing and support only (content editors and reviewers get 403). */
export default async function CompetitionsLayout({ children }: { children: React.ReactNode }) {
  requireSection(await api<AdminMe>('/admin/auth/me'), '/competitions');
  return children;
}
