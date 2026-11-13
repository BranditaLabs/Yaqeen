import { SkeletonKpis, SkeletonRows } from '@/components/ui';

/** Shaped placeholders while a section loads (one shimmer, stopped by reduced motion). */
export default function Loading() {
  return (
    <div className="space-y-6" aria-busy="true">
      <span className="sr-only" role="status">
        جارٍ التحميل…
      </span>
      <div className="skeleton h-8 w-48 rounded-chip" />
      <SkeletonKpis />
      <SkeletonRows />
    </div>
  );
}
