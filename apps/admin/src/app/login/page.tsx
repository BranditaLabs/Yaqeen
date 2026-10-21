'use client';

import { useActionState } from 'react';
import { login } from './actions';

export default function LoginPage() {
  const [state, action, pending] = useActionState(login, { error: null });

  return (
    <main className="grid min-h-dvh lg:grid-cols-[1fr_1.1fr]">
      {/* Brand panel — gradient + white lockup, as on the guide's cover */}
      <section className="relative hidden flex-col justify-between bg-[image:var(--yq-gradient-brand)] p-12 text-white lg:flex">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/mark-white.png" alt="" className="h-10 w-auto self-start opacity-90" />
        <div>
          <p className="font-[family-name:var(--font-display)] text-4xl leading-snug">باليقين تطمئن القلوب</p>
          <p dir="ltr" className="mt-3 text-right font-[family-name:var(--font-display-en)] text-lg text-sky-200">Certain in Faith. At Peace in Heart.</p>
        </div>
        <p className="text-xs text-white/50">لوحة التحكم · Yaqeen</p>
      </section>
      <div className="grid place-items-center px-4 py-10">
      <form action={action} className="glass w-full max-w-sm rounded-[30px] p-8">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/lockup-stacked-navy.png" alt="يقين Yaqeen" className="mx-auto h-28 w-auto" />
        <p className="mb-8 mt-3 text-center text-sm text-muted">لوحة التحكم</p>

        <label className="label" htmlFor="email">البريد الإلكتروني</label>
        <input id="email" name="email" type="email" required autoComplete="username" dir="ltr" className="field mb-4 text-left" />

        <label className="label" htmlFor="password">كلمة المرور</label>
        <input id="password" name="password" type="password" required autoComplete="current-password" dir="ltr" className="field mb-4 text-left" />

        <label className="label" htmlFor="totp">رمز التحقق (تطبيق المصادقة)</label>
        <input
          id="totp"
          name="totp"
          inputMode="numeric"
          pattern="\d{6}"
          maxLength={6}
          required
          autoComplete="one-time-code"
          dir="ltr"
          className="field num mb-6 text-center tracking-[0.5em]"
        />

        {state.error && <p className="mb-4 rounded-chip bg-[#FDF3F4] px-3 py-2 text-sm text-error">{state.error}</p>}

        <button disabled={pending} className="min-h-12 w-full rounded-full bg-lapis text-sm font-medium text-white transition hover:bg-royal disabled:opacity-60">
          {pending ? 'جارٍ الدخول…' : 'دخول'}
        </button>
        <p className="mt-5 text-center text-xs text-muted">الدخول مسجَّل. كل تعديل يُحفظ في سجل المراجعة.</p>
      </form>
      </div>
    </main>
  );
}
