import { SkeletonKpis, SkeletonRows } from '@/components/ui';

/** «المسابقات» while it loads: header, tab chips, KPIs and a standings-shaped list. */
export default function Loading() {
  return (
    <div className="space-y-6" aria-busy="true">
      <span className="sr-only" role="status">
        جارٍ تحميل المسابقات…
      </span>
      <div className="space-y-2">
        <div className="skeleton h-8 w-40 rounded-chip" />
        <div className="skeleton h-3 w-72 rounded-full" />
      </div>
      <div className="flex gap-2">
        {[88, 112, 104, 72, 72].map((w, i) => (
          <div key={i} className="skeleton h-9 rounded-full" style={{ width: w }} />
        ))}
      </div>
      <SkeletonKpis />
      <SkeletonRows rows={8} />
    </div>
  );
}
