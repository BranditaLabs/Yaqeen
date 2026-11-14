import type { AdminRole } from '@yaqeen/contracts';

export const SESSION_COOKIE = 'yq_admin';
/** The request path, set by the middleware for the dashboard layout's role gate (layouts do not receive it). */
export const PATH_HEADER = 'x-yq-path';

/** Which sidebar sections each role can see (mirrors the API's RBAC; the API is the enforcer). */
export const NAV_ACCESS: Record<string, AdminRole[]> = {
  '/': ['super_admin', 'marketing', 'support', 'content_editor', 'religious_reviewer'],
  '/users': ['super_admin', 'support', 'marketing'],
  '/content': ['super_admin', 'content_editor', 'religious_reviewer'],
  '/campaigns': ['super_admin', 'marketing'],
  '/rewards': ['super_admin', 'marketing', 'support'],
  '/competitions': ['super_admin', 'marketing', 'support'],
  '/analytics': ['super_admin', 'marketing', 'support'],
  '/cards': ['super_admin', 'marketing', 'support'],
  '/tags': ['super_admin', 'marketing', 'support'],
  '/settings': ['super_admin', 'religious_reviewer', 'content_editor', 'marketing'],
};

/**
 * The section a path belongs to (the longest NAV_ACCESS prefix, never the overview), or null.
 * The dashboard layout answers 403 when the signed-in role is not listed for it.
 */
export function sectionOf(path: string): string | null {
  let best: string | null = null;
  for (const key of Object.keys(NAV_ACCESS)) {
    if (key === '/') continue;
    if ((path === key || path.startsWith(`${key}/`)) && (!best || key.length > best.length)) best = key;
  }
  return best;
}

export const ROLE_LABEL: Record<AdminRole, string> = {
  super_admin: 'مدير عام',
  content_editor: 'محرر محتوى',
  religious_reviewer: 'مراجع شرعي',
  marketing: 'تسويق',
  support: 'دعم',
};
