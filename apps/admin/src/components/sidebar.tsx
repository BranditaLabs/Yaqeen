'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { AdminMe } from '@yaqeen/contracts';
import { logout } from '@/app/login/actions';
import { NAV_ACCESS, ROLE_LABEL } from '@/lib/session';
import { Icon, type IconName } from './icons';

const ITEMS: { href: string; label: string; icon: IconName }[] = [
  { href: '/', label: 'نظرة عامة', icon: 'home' },
  { href: '/users', label: 'المستخدمون', icon: 'users' },
  { href: '/content', label: 'المحتوى', icon: 'book' },
  { href: '/campaigns', label: 'الحملات', icon: 'bell' },
  { href: '/rewards', label: 'النقاط والمكافآت', icon: 'gift' },
  { href: '/settings', label: 'الإعدادات', icon: 'gear' },
];

export function Sidebar({ me }: { me: AdminMe }) {
  const path = usePathname();
  const items = ITEMS.filter((i) => NAV_ACCESS[i.href]?.includes(me.role));
  const isActive = (href: string) => (href === '/' ? path === '/' : path.startsWith(href));

  return (
    <aside className="glass sticky top-4 flex h-[calc(100dvh-2rem)] w-64 shrink-0 flex-col rounded-[30px] p-4 max-lg:hidden">
      <div className="px-3 pb-6 pt-2">
        {/* eslint-disable-next-line @next/next/no-img-element -- static brand artwork */}
        <img src="/brand/lockup-horizontal-navy.png" alt="يقين Yaqeen" className="h-12 w-auto" />
        <p className="mt-2 text-xs text-muted">لوحة التحكم</p>
      </div>
      <nav className="flex flex-1 flex-col gap-1">
        {items.map((i) => (
          <Link
            key={i.href}
            href={i.href}
            className={`flex min-h-11 items-center gap-3 rounded-tile px-3 text-sm transition ${
              isActive(i.href) ? 'bg-white text-lapis shadow-sm' : 'text-muted hover:bg-white/60 hover:text-ink'
            }`}
          >
            <Icon name={i.icon} />
            {i.label}
          </Link>
        ))}
      </nav>
      <div className="rounded-tile bg-white/70 p-3">
        <p className="truncate text-sm font-medium text-ink">{me.name}</p>
        <p className="text-xs text-muted">{ROLE_LABEL[me.role]}</p>
        <form action={logout} className="mt-2">
          <button className="flex items-center gap-2 text-xs text-muted hover:text-error">
            <Icon name="logout" size={16} /> تسجيل الخروج
          </button>
        </form>
      </div>
    </aside>
  );
}

/** Compact top bar for small screens. */
export function MobileNav({ me }: { me: AdminMe }) {
  const path = usePathname();
  const items = ITEMS.filter((i) => NAV_ACCESS[i.href]?.includes(me.role));
  return (
    <nav className="glass sticky top-2 z-10 mb-4 flex gap-1 overflow-x-auto rounded-full p-1.5 lg:hidden">
      {items.map((i) => (
        <Link
          key={i.href}
          href={i.href}
          className={`flex min-h-10 shrink-0 items-center gap-1.5 rounded-full px-3 text-xs ${
            (i.href === '/' ? path === '/' : path.startsWith(i.href)) ? 'bg-white text-lapis' : 'text-muted'
          }`}
        >
          <Icon name={i.icon} size={16} />
          {i.label}
        </Link>
      ))}
    </nav>
  );
}
