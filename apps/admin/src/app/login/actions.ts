'use server';

import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { AdminLoginRequest } from '@yaqeen/contracts';
import { SESSION_COOKIE } from '@/lib/session';

const API_URL = process.env.API_URL ?? 'http://localhost:4000';

export async function login(_prev: { error: string | null }, form: FormData): Promise<{ error: string | null }> {
  const parsed = AdminLoginRequest.safeParse({
    email: form.get('email'),
    password: form.get('password'),
    totp: form.get('totp'),
  });
  if (!parsed.success) return { error: 'تحقق من البريد وكلمة المرور ورمز التحقق المكوّن من 6 أرقام' };

  const res = await fetch(`${API_URL}/admin/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(parsed.data),
    cache: 'no-store',
  });
  if (res.status === 429) return { error: 'محاولات كثيرة. انتظر بضع دقائق ثم حاول مرة أخرى' };
  if (!res.ok) return { error: 'بيانات الدخول غير صحيحة' };

  const { token, expiresIn } = (await res.json()) as { token: string; expiresIn: number };
  (await cookies()).set(SESSION_COOKIE, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: '/',
    maxAge: expiresIn,
  });
  redirect('/');
}

export async function logout() {
  (await cookies()).delete(SESSION_COOKIE);
  redirect('/login');
}
