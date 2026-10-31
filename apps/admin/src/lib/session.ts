import type { AdminRole } from '@yaqeen/contracts';

export const SESSION_COOKIE = 'yq_admin';

/** Which sidebar sections each role can see (mirrors the API's RBAC; the API is the enforcer). */
export const NAV_ACCESS: Record<string, AdminRole[]> = {
  '/': ['super_admin', 'marketing', 'support', 'content_editor', 'religious_reviewer'],
  '/users': ['super_admin', 'support', 'marketing'],
  '/content': ['super_admin', 'content_editor', 'religious_reviewer'],
  '/campaigns': ['super_admin', 'marketing'],
  '/rewards': ['super_admin', 'marketing', 'support'],
  '/analytics': ['super_admin', 'marketing', 'support'],
  '/cards': ['super_admin', 'marketing', 'support'],
  '/tags': ['super_admin', 'marketing', 'support'],
  '/settings': ['super_admin', 'religious_reviewer', 'content_editor', 'marketing'],
};

export const ROLE_LABEL: Record<AdminRole, string> = {
  super_admin: 'مدير عام',
  content_editor: 'محرر محتوى',
  religious_reviewer: 'مراجع شرعي',
  marketing: 'تسويق',
  support: 'دعم',
};
