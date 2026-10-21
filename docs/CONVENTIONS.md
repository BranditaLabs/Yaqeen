# Conventions

## Repo

- pnpm workspaces: `apps/admin`, `services/*`, `packages/*`. Flutter (`apps/mobile`) is outside the JS workspace.
- Node 22, pnpm 10.34.7, TypeScript 5.9 (strict, `noUncheckedIndexedAccess`). Prettier: 2 spaces, single quotes, 120 cols.
- Branches: `feat/…`, `fix/…`, `chore/…`. Conventional commits (`feat(api): …`). PRs need green CI.

## Contracts first

1. Add or change the zod schema in `packages/contracts/src/api.ts`.
2. Use it in the API route (`Schema.parse(req.body)`) and in the admin (types + form parsing).
3. Mirror it in Dart (`features/<x>/domain/*.dart`, `fromJson`) and add a parsing test.

## API (`services/api`)

- `domain/` = pure functions, no I/O, 100% unit-tested. `services/` = DB orchestration. `routes/` = HTTP only (parse → call → return).
- Throw `AppError` helpers (`badRequest('code')`, `notFound`, `conflict`, `forbidden('code')`). Error codes are snake_case and stable — clients depend on them.
- Every admin write: `requireAdmin([...roles])` + `audit(tx, req, …)` **inside the same transaction**.
- Never update a balance. Insert a ledger row with a unique `ref_key`.
- Schema change → `pnpm db:generate` → commit the SQL migration. Never edit an applied migration.
- Time: store `timestamptz`; compute "today" in the user's timezone (`localToday`). Calendar dates as `YYYY-MM-DD` strings.

## Admin (`apps/admin`)

- Server components fetch through `lib/api.ts` (`server-only`). Mutations are server actions returning `{ error }` for forms.
- No API tokens in client components. The API enforces RBAC; the sidebar only hides what a role can't use.
- RTL Arabic UI, Western digits (`lib/format.ts`), design tokens from `@yaqeen/design-tokens`.

## Mobile (`apps/mobile`)

- Feature-first: `features/<name>/{domain,data,presentation}`. Presentation → controller (Riverpod) → repository → `ApiClient`.
- Strings in `l10n/app_ar.arb` (template) + `app_en.arb`. No hard-coded user-facing text.
- Numbers through `YqFormat.number`. Spacing/radii/colours from `tokens.dart` only.
- Platform plugins behind interfaces in `core/` with a no-op default and a provider override in `main.dart`.
- Touch targets ≥ 44 pt; every icon-only button has a semantic label.

## Brand

- Source of truth: `packages/brand/README.md` + `packages/design-tokens/tokens.json`. Colours only from tokens.
- Logo = artwork files only (`YqLogo` in Flutter, `/brand/*.png` in the admin). Never typeset «يقين» as a logo.
- Brand fonts ZEYADA Arabic 1 / Canela Text are commercial — see `packages/brand/fonts/README.md`; code already falls back safely.

## Copy

- Calm, respectful Arabic. No urgency, no guilt about missed worship ("قضاء" not "فشلت").
- Every dua/zikr has a source (`المصدر`) and passes religious review.
