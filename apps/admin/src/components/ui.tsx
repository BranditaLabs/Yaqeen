import type { ReactNode } from 'react';
import type { Avatar as AvatarValue } from '@yaqeen/contracts';

export function Card({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <section className={`glass rounded-card p-5 ${className}`}>{children}</section>;
}

export function CardTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-4 flex items-center justify-between gap-3">
      <h2 className="text-[15px] font-bold text-ink">{children}</h2>
      {action}
    </div>
  );
}

export function PageHeader({ title, subtitle, action, icon }: { title: string; subtitle?: string; action?: ReactNode; icon?: ReactNode }) {
  return (
    <header className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div className="flex items-center gap-3">
        {icon}
        <div>
          <h1 className="text-2xl font-bold text-ink">{title}</h1>
          {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
        </div>
      </div>
      {action}
    </header>
  );
}

export function Kpi({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card>
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className="num mt-2 text-3xl font-semibold text-ink">{value}</p>
      {hint && <p className="mt-1 text-xs text-muted">{hint}</p>}
    </Card>
  );
}

const TONES = {
  blue: 'bg-ice text-lapis',
  gold: 'bg-sand text-gold-text',
  green: 'bg-[#EDF6F1] text-success',
  red: 'bg-[#F7E4E7] text-error',
  gray: 'bg-white text-muted border border-line',
} as const;

export function Badge({ tone = 'gray', children }: { tone?: keyof typeof TONES; children: ReactNode }) {
  return <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${TONES[tone]}`}>{children}</span>;
}

export function Button({
  children,
  variant = 'primary',
  type = 'submit',
  name,
  value,
  disabled,
}: {
  children: ReactNode;
  variant?: 'primary' | 'ghost' | 'danger';
  type?: 'submit' | 'button';
  name?: string;
  value?: string;
  disabled?: boolean;
}) {
  const styles = {
    primary: 'bg-lapis text-white hover:bg-royal shadow-[0_8px_20px_-10px_rgba(31,63,148,0.7)]',
    ghost: 'bg-white/70 text-ink border border-line hover:bg-white',
    danger: 'bg-white text-error border border-[#F0C9CF] hover:bg-[#FDF3F4]',
  }[variant];
  return (
    <button
      type={type}
      name={name}
      value={value}
      disabled={disabled}
      className={`inline-flex min-h-11 items-center justify-center gap-2 rounded-full px-5 text-sm font-medium transition disabled:opacity-50 ${styles}`}
    >
      {children}
    </button>
  );
}

export function Table({ head, children }: { head: string[]; children: ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-right text-sm">
        <thead>
          <tr className="border-b border-line text-xs text-muted">
            {head.map((h) => (
              <th key={h} className="px-3 py-2.5 font-medium">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-line/70">{children}</tbody>
      </table>
    </div>
  );
}

export function Td({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <td className={`px-3 py-3 align-middle ${className}`}>{children}</td>;
}

/**
 * A member's avatar: a bundled preset (/avatars/<id>.webp), a photo at the URL the API row gives
 * (the admin photo proxy for competitor rows, the public URL in standings), or the initial in ink on
 * ice. `photos=false` (roles without the support photo route) shows the initial instead of a proxy URL
 * that would answer 403.
 */
export function Avatar({ avatar, name, size = 32, photos = true }: { avatar: AvatarValue | null | undefined; name: string | null; size?: number; photos?: boolean }) {
  const box = { width: size, height: size };
  const cls = 'shrink-0 rounded-full border border-line bg-ice object-cover';
  if (avatar?.kind === 'preset') {
    // eslint-disable-next-line @next/next/no-img-element -- bundled artwork, already sized
    return <img src={`/avatars/${avatar.id}.webp`} alt="" {...box} className={cls} loading="lazy" decoding="async" />;
  }
  if (avatar?.kind === 'photo' && (photos || !avatar.smallUrl.startsWith('/api/'))) {
    // eslint-disable-next-line @next/next/no-img-element -- per-member photo served by the API
    return <img src={size <= 48 ? avatar.smallUrl : avatar.url} alt="" {...box} className={cls} loading="lazy" decoding="async" referrerPolicy="no-referrer" />;
  }
  const initial = (name ?? '').trim().charAt(0) || '؟';
  return (
    <span aria-hidden className={`${cls} grid place-items-center font-bold text-ink`} style={{ ...box, fontSize: Math.round(size * 0.42) }}>
      {initial}
    </span>
  );
}

/**
 * Small level ring: lapis arc on a hairline track with the level numeral. Gold only for the top
 * level (منارة), an achievement.
 */
export function LevelRing({ level, progress, size = 28, label }: { level: number; progress: number; size?: number; label?: string }) {
  const r = (size - 4) / 2;
  const c = 2 * Math.PI * r;
  const p = level >= 6 ? 1 : Math.max(0, Math.min(1, progress));
  const stroke = level >= 6 ? 'var(--yq-gold)' : 'var(--yq-lapis)';
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label={label ?? `المستوى ${level}`} className="shrink-0">
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--yq-line)" strokeWidth={2.5} />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke={stroke}
        strokeWidth={2.5}
        strokeLinecap="round"
        strokeDasharray={`${(c * p).toFixed(2)} ${c.toFixed(2)}`}
        transform={`rotate(-90 ${size / 2} ${size / 2})`}
      />
      <text x="50%" y="50%" dominantBaseline="central" textAnchor="middle" className="fill-ink" style={{ fontFamily: 'var(--font-num)', fontSize: size * 0.42, fontWeight: 600 }}>
        {level}
      </text>
    </svg>
  );
}

/** Placeholder for a KPI row while it loads. */
export function SkeletonKpis({ count = 3 }: { count?: number }) {
  return (
    <div className="grid gap-4 md:grid-cols-3" aria-hidden>
      {Array.from({ length: count }, (_, i) => (
        <section key={i} className="glass rounded-card p-5">
          <div className="skeleton h-3 w-24 rounded-full" />
          <div className="skeleton mt-4 h-8 w-20 rounded-chip" />
        </section>
      ))}
    </div>
  );
}

/** Placeholder for a table / list while it loads: avatar circle + two text bars per row. */
export function SkeletonRows({ rows = 6 }: { rows?: number }) {
  return (
    <section className="glass rounded-card p-5" aria-hidden>
      <div className="skeleton mb-5 h-4 w-32 rounded-full" />
      <div className="space-y-4">
        {Array.from({ length: rows }, (_, i) => (
          <div key={i} className="flex items-center gap-3">
            <div className="skeleton h-8 w-8 shrink-0 rounded-full" />
            <div className="flex-1 space-y-2">
              <div className="skeleton h-3 rounded-full" style={{ width: `${60 - ((i * 13) % 30)}%` }} />
              <div className="skeleton h-2.5 w-1/4 rounded-full" />
            </div>
            <div className="skeleton h-3 w-12 rounded-full" />
          </div>
        ))}
      </div>
    </section>
  );
}

export function Notice({ tone = 'gold', children }: { tone?: 'gold' | 'red' | 'blue'; children: ReactNode }) {
  const s = { gold: 'bg-cream border-gold-light text-gold-text', red: 'bg-[#FDF3F4] border-[#F0C9CF] text-error', blue: 'bg-ice border-mist text-lapis' }[tone];
  return <div className={`rounded-tile border px-4 py-3 text-sm ${s}`}>{children}</div>;
}
