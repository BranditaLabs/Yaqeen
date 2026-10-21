# ADR 0001 — Monorepo with shared contracts

**Status:** accepted · 2026-10

**Context.** Three deliverables (mobile, API, admin) change together: a new field on the challenge touches all three.

**Decision.** One repository. pnpm workspaces for TypeScript (API, admin, packages); Flutter lives in `apps/mobile` with its own toolchain. Request/response shapes are zod schemas in `packages/contracts`, imported by API and admin and mirrored in Dart models with parsing tests.

**Consequences.** One PR can change the contract and every consumer. Dart mirrors are manual — a future step could generate them from JSON Schema (`z.toJSONSchema`).
