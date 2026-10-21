'use client';

import { useState, useTransition } from 'react';
import { searchCollections } from '@/app/(dash)/rewards/actions';

type Collection = { id: string; title: string; productsCount: number | null };

/**
 * "+ مكافأة من منتجات Shopify": search the store's collections and pick the ones a code is limited to.
 * Submits the chosen GIDs as the comma-separated `collections` field (controlled, survives actions).
 */
export function CollectionPicker({ initial }: { initial: string[] }) {
  const [selected, setSelected] = useState<string[]>(initial);
  const [titles, setTitles] = useState<Record<string, string>>({});
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Collection[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const search = () =>
    start(async () => {
      const res = await searchCollections(query);
      setError(res.error);
      setResults(res.data ?? []);
    });
  const toggle = (c: Collection) => {
    setTitles((t) => ({ ...t, [c.id]: c.title }));
    setSelected((s) => (s.includes(c.id) ? s.filter((x) => x !== c.id) : [...s, c.id]));
  };

  return (
    <div className="space-y-2">
      <input type="hidden" name="collections" value={selected.join(',')} />
      <div className="flex flex-wrap gap-2">
        {selected.length === 0 && <span className="text-xs text-muted">على كل منتجات المتجر</span>}
        {selected.map((id) => (
          <button
            key={id}
            type="button"
            onClick={() => setSelected((s) => s.filter((x) => x !== id))}
            className="rounded-full bg-ice px-3 py-1 text-xs text-lapis"
            title="إزالة"
          >
            {titles[id] ?? <span dir="ltr">{id.split('/').pop()}</span>} ×
          </button>
        ))}
      </div>
      <div className="flex gap-2">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault();
              search();
            }
          }}
          placeholder="ابحث في مجموعات Shopify — سجاد الصلاة…"
          className="field flex-1"
        />
        <button type="button" onClick={search} disabled={pending} className="min-h-11 rounded-full border border-line bg-white/70 px-4 text-sm">
          {pending ? '…' : 'بحث'}
        </button>
      </div>
      {error && <p className="text-xs text-error">{error}</p>}
      {results && (
        <ul className="max-h-48 space-y-1 overflow-y-auto rounded-chip bg-white/60 p-2">
          {results.length === 0 && <li className="p-2 text-xs text-muted">لا توجد مجموعات مطابقة</li>}
          {results.map((c) => (
            <li key={c.id}>
              <label className="flex cursor-pointer items-center justify-between gap-2 rounded-chip px-2 py-1.5 text-sm hover:bg-white">
                <span>
                  <input type="checkbox" checked={selected.includes(c.id)} onChange={() => toggle(c)} className="me-2 accent-[var(--yq-lapis)]" />
                  {c.title}
                </span>
                {c.productsCount !== null && <span className="num text-xs text-muted">{c.productsCount} منتج</span>}
              </label>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
