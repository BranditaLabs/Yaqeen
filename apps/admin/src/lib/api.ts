import 'server-only';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { SESSION_COOKIE } from './session';

const API_URL = process.env.API_URL ?? 'http://localhost:4000';

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
  ) {
    super(message);
  }
}

/**
 * Server-side call to the Yaqeen API. The admin token lives in an httpOnly cookie and is
 * never exposed to browser JavaScript.
 */
export async function api<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const token = (await cookies()).get(SESSION_COOKIE)?.value;
  const res = await fetch(`${API_URL}${path}`, {
    method: init.method ?? 'GET',
    headers: {
      ...(init.body !== undefined ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
    cache: 'no-store',
  });
  if (res.status === 401) redirect('/login');
  if (!res.ok) {
    const err = (await res.json().catch(() => ({}))) as { error?: { code?: string; message?: string } };
    throw new ApiError(res.status, err.error?.code ?? 'error', err.error?.message ?? res.statusText);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

/** For server actions: returns `{ error }` instead of throwing so forms can show it. */
export async function tryApi<T>(path: string, init: { method?: string; body?: unknown } = {}) {
  try {
    return { data: await api<T>(path, init), error: null as string | null };
  } catch (e) {
    if (e instanceof ApiError) return { data: null, error: e.message || e.code };
    throw e;
  }
}
