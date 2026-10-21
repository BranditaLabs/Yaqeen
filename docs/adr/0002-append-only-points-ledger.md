# ADR 0002 — Append-only points ledger

**Status:** accepted · 2026-10

**Context.** Points convert to money (store discounts). Offline clients retry. Admins sometimes correct balances.

**Decision.** No balance column. Every change is a `points_ledger` row with a unique `(user_id, ref_key)`; balance = `SUM(delta)`. Awards and redemptions take a per-user Postgres advisory lock. Corrections are new rows (`reversal`, `admin_adjustment`) with an audit entry.

**Consequences.** Full history for support and fraud review, idempotent retries for free. Balance reads are a SUM — fine at this scale; add a materialised balance if it ever shows up in profiles.
