import Link from 'next/link';

/** 403: the signed-in role has no access to this section (NAV_ACCESS; the API enforces the same rule). */
export default function Forbidden() {
  return (
    <main className="grid min-h-dvh place-items-center p-4">
      <section className="glass max-w-md rounded-card p-8 text-center">
        <p className="num text-sm text-muted">403</p>
        <h1 className="mt-2 text-xl font-bold text-ink">لا تملك صلاحية هذا القسم</h1>
        <p className="mt-2 text-sm text-muted">هذا القسم غير متاح لدورك في لوحة التحكم. اطلب الصلاحية من المدير العام إن احتجتها.</p>
        <Link href="/" className="mt-6 inline-flex min-h-11 items-center rounded-full bg-lapis px-5 text-sm font-medium text-white hover:bg-royal">
          العودة إلى النظرة العامة
        </Link>
      </section>
    </main>
  );
}
