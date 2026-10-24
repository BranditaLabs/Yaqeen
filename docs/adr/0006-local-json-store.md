# ADR 0006 — On-device user data in a versioned JSON store, not drift/SQLite

**Status:** accepted · 2026-10

**Context.** The spec (§6.6, §9.3) sketches `user.db` with drift for bookmarks, last read, wird, azkar counts, hifz, inbox and the content cache. Every one of these is a small document read whole (tens of items, a few KB): no joins, no range queries, no full-text search. Drift adds code generation, a native SQLite dependency on both platforms and migrations in SQL.

**Decision.** `LocalStore` keeps one JSON document per collection in the platform key-value store (`db.<collection>`), with a schema version and ordered Dart migrations (`LocalStore.migrations`). Repositories own their document shape (`ReadingRepository`, `AzkarStore`, `HifzRepository`, `ListenStore`, `InboxRepository`). The Quran text itself is a bundled, checksum-tested JSON asset parsed off the UI thread (ADR 0007), not a database. Writes that must reach the server go through the Outbox, never through this store.

**Consequences.** No code generation or native DB in the build; the store is trivially testable with `MemoryKvStore`. Account deletion wipes the known collections (`LocalStore.wipe`). If a collection ever needs querying at scale (e.g. full tafsir search), that collection moves to SQLite on its own without changing the others.
