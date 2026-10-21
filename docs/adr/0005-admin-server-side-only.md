# ADR 0005 — Admin calls the API only from the server

**Status:** accepted · 2026-10

**Decision.** The Next.js admin keeps the admin token in an httpOnly, SameSite=Strict cookie and calls the API from server components and server actions only. Admin tokens use a separate secret and audience from app tokens. RBAC is enforced by the API; the UI only hides what a role can't use.

**Consequences.** No tokens reachable by XSS in the browser; the admin can sit behind SSO/VPN without CORS changes.
