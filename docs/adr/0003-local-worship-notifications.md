# ADR 0003 — Worship reminders are local; marketing pushes are remote and guarded

**Status:** accepted · 2026-10

**Context.** Adhan must be on time with no network, and the server should not learn when a person prays. Marketing pushes must never interrupt prayer.

**Decision.** Adhan/azkar/wird reminders are scheduled on the device from on-device prayer times (`NotificationPlanner`, iOS 64-slot budget). Remote FCM pushes are only for campaigns and go through server guardrails per user timezone: consent bucket, quiet hours, prayer windows, Jumu'ah, daily caps.

**Consequences.** No server dependency for the core habit. The dispatcher needs approximate prayer times (Cairo default until per-user coordinates are stored).
