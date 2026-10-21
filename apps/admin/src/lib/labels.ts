import type { AdminUserRow, ContentStatus } from '@yaqeen/contracts';

export const USER_STATUS: Record<AdminUserRow['status'], { label: string; tone: 'green' | 'red' | 'gold' | 'gray' }> = {
  active: { label: 'نشط', tone: 'green' },
  suspended: { label: 'موقوف', tone: 'red' },
  under_review: { label: 'قيد المراجعة', tone: 'gold' },
  deletion_requested: { label: 'طلب حذف', tone: 'gray' },
};

export const CONTENT_STATUS: Record<ContentStatus, { label: string; tone: 'green' | 'red' | 'gold' | 'gray' | 'blue' }> = {
  draft: { label: 'مسودة', tone: 'gray' },
  pending_review: { label: 'بانتظار المراجعة', tone: 'gold' },
  changes_requested: { label: 'مطلوب تعديل', tone: 'red' },
  published: { label: 'منشور', tone: 'green' },
};
