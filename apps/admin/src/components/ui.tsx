import type { ReactNode } from 'react';

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

export function PageHeader({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return (
    <header className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 className="text-2xl font-bold text-ink">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
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
  green: 'bg-[#E3F1EA] text-success',
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

export function Notice({ tone = 'gold', children }: { tone?: 'gold' | 'red' | 'blue'; children: ReactNode }) {
  const s = { gold: 'bg-cream border-gold-light text-gold-text', red: 'bg-[#FDF3F4] border-[#F0C9CF] text-error', blue: 'bg-ice border-mist text-lapis' }[tone];
  return <div className={`rounded-tile border px-4 py-3 text-sm ${s}`}>{children}</div>;
}
