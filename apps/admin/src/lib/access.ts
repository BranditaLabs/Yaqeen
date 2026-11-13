import 'server-only';
import { forbidden } from 'next/navigation';
import type { AdminMe, AdminRole } from '@yaqeen/contracts';
import { NAV_ACCESS } from './session';

/** 403 page unless the admin's role may use `section` (NAV_ACCESS mirrors the API's RBAC). */
export function requireSection(me: Pick<AdminMe, 'role'>, section: string): void {
  const roles = NAV_ACCESS[section];
  if (roles && !roles.includes(me.role)) forbidden();
}

/** Capabilities inside «المسابقات» (design §11; the API guards each endpoint the same way). */
export function competitionRights(role: AdminRole) {
  const isSuper = role === 'super_admin';
  return {
    /** Tournaments and league settings. */
    canManage: isSuper || role === 'marketing',
    /** Names, photos, bans, reports and the admin photo route. */
    canModerate: isSuper || role === 'support',
    /** Run the community job now. */
    canRollover: isSuper,
  };
}
