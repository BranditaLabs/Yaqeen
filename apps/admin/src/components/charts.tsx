import { num } from '@/lib/format';

/** Server-rendered SVG charts — no client JS, tokens only, Western digits. */

export function LineChart({
  points,
  height = 180,
  label = 'المستخدمون النشطون يومياً',
}: {
  points: { date: string; value: number | null }[];
  height?: number;
  label?: string;
}) {
  const W = 640;
  const H = height;
  const pad = { top: 16, right: 12, bottom: 26, left: 40 };
  const values = points.map((p) => p.value ?? 0);
  const max = Math.max(1, ...values);
  const x = (i: number) => pad.left + (i * (W - pad.left - pad.right)) / Math.max(1, points.length - 1);
  const y = (v: number) => pad.top + (1 - v / max) * (H - pad.top - pad.bottom);
  const path = points.map((p, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)} ${y(p.value ?? 0).toFixed(1)}`).join(' ');
  const area = `${path} L${x(points.length - 1)} ${H - pad.bottom} L${x(0)} ${H - pad.bottom} Z`;
  const ticks = [...new Set([0, 0.5, 1].map((f) => Math.round(max * f)))];
  const isFriday = (d: string) => new Date(`${d}T00:00:00Z`).getUTCDay() === 5;
  const every = Math.ceil(points.length / 7);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label={label} style={{ direction: 'ltr' }}>
      {ticks.map((t) => (
        <g key={t}>
          <line x1={pad.left} x2={W - pad.right} y1={y(t)} y2={y(t)} stroke="var(--yq-line)" strokeDasharray="3 4" />
          <text x={pad.left - 8} y={y(t) + 4} textAnchor="end" className="fill-muted text-[10px]" style={{ fontFamily: 'var(--font-num)' }}>
            {num(t)}
          </text>
        </g>
      ))}
      <path d={area} fill="var(--yq-sky)" opacity={0.18} />
      <path d={path} fill="none" stroke="var(--yq-lapis)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
      {points.map((p, i) =>
        p.value === null ? (
          <circle key={p.date} cx={x(i)} cy={y(0)} r={2.5} fill="var(--yq-mist)">
            <title>{`${p.date}: أقل من 20 — مخفي`}</title>
          </circle>
        ) : isFriday(p.date) ? (
          <circle key={p.date} cx={x(i)} cy={y(p.value)} r={4} fill="var(--yq-gold)" stroke="white" strokeWidth={1.5}>
            <title>{`الجمعة ${p.date}: ${num(p.value)}`}</title>
          </circle>
        ) : null,
      )}
      {points.map((p, i) =>
        i % every === 0 || i === points.length - 1 ? (
          <text key={`l${p.date}`} x={x(i)} y={H - 8} textAnchor="middle" className="fill-muted text-[10px]" style={{ fontFamily: 'var(--font-num)' }}>
            {p.date.slice(5).replace('-', '/')}
          </text>
        ) : null,
      )}
    </svg>
  );
}

/** Horizontal bar with a label; `value` null renders the k-anonymity placeholder. */
export function Bar({ label, value, suffix = '%', max = 100, tone = 'lapis' }: { label: string; value: number | null; suffix?: string; max?: number; tone?: 'lapis' | 'gold' }) {
  return (
    <div>
      <div className="mb-1.5 flex justify-between text-sm">
        <span>{label}</span>
        <span className="num text-muted">{value === null ? 'أقل من 20 مشاركاً' : `${num(value)}${suffix}`}</span>
      </div>
      <div className="h-2 rounded-full bg-ice">
        {value !== null && (
          <div className={`h-2 rounded-full ${tone === 'gold' ? 'bg-gold' : 'bg-lapis'}`} style={{ width: `${Math.min(100, (100 * value) / Math.max(1, max))}%` }} />
        )}
      </div>
    </div>
  );
}
