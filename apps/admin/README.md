# @yaqeen/admin

Next.js 15 dashboard (Arabic RTL, Tailwind 4 tokens). Run `pnpm dev:admin`; build with
`pnpm --filter @yaqeen/admin build`; unit tests (pure logic in `src/lib`, `node:test`) with
`pnpm --filter @yaqeen/admin test`. Browser E2E live in `e2e/`.

## Known framework issues (re-check on every Next upgrade)

- **Next 15.5.4: a server-action form inside a re-streamed Suspense boundary stays `pending`.**
  When a form's action re-renders the page and the form sits inside a `<Suspense>` boundary (or a
  route `loading.tsx`, which is one) that streams again in the action response, `useActionState`
  never leaves `pending` and the success/error line never shows. So:
  - «المسابقات» has no route `loading.tsx`; skeletons come from in-page `<Suspense>` around
    read-only parts only (this week's league numbers, tournament stats, the level board, badges).
  - Anything that renders a form (league settings, rollover, support's moderation rows, support's
    standings rows, every «التلاوات» queue row) renders outside Suspense, so support's views of
    those lists have no skeleton.
  - When Next is upgraded: put `app/(dash)/competitions/loading.tsx` back, wrap the support views in
    Suspense (and the «التلاوات» queue), and run the E2E «المسابقات» and «التلاوات» suites (league
    settings save, photo hide, standings name hide, recording approve, comment remove, reports dismiss).
    If they pass, drop this note and the comments that point here.
