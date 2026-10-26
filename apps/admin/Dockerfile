# Build from the repo root:  docker build -f apps/admin/Dockerfile -t yaqeen-admin .
FROM node:22-alpine AS base
RUN corepack enable && corepack prepare pnpm@10.34.7 --activate
WORKDIR /repo

FROM base AS build
ENV NEXT_TELEMETRY_DISABLED=1
# Browser error reporting is configured at build time (public values only). The Sentry auth token for
# source-map upload comes as a BuildKit secret, so it never lands in an image layer.
ARG GIT_SHA=dev
ARG NEXT_PUBLIC_SENTRY_DSN=""
ARG NEXT_PUBLIC_SENTRY_ENVIRONMENT=""
ARG SENTRY_ORG=""
ENV GIT_SHA=$GIT_SHA NEXT_PUBLIC_GIT_SHA=$GIT_SHA NEXT_PUBLIC_SENTRY_DSN=$NEXT_PUBLIC_SENTRY_DSN \
    NEXT_PUBLIC_SENTRY_ENVIRONMENT=$NEXT_PUBLIC_SENTRY_ENVIRONMENT SENTRY_ORG=$SENTRY_ORG
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json tsconfig.base.json ./
# Whole contracts package: its `prepare` script compiles it during install.
COPY packages/contracts packages/contracts
COPY packages/design-tokens/package.json packages/design-tokens/
COPY apps/admin/package.json apps/admin/
RUN pnpm install --frozen-lockfile --filter @yaqeen/admin...
COPY packages/design-tokens packages/design-tokens
COPY apps/admin apps/admin
RUN --mount=type=secret,id=sentry_auth_token \
    SENTRY_AUTH_TOKEN="$(cat /run/secrets/sentry_auth_token 2>/dev/null || true)" \
    sh -c 'pnpm --filter @yaqeen/contracts build && pnpm --filter @yaqeen/admin build'

# Next.js standalone output: only the traced runtime files.
FROM node:22-alpine AS runtime
ARG GIT_SHA=dev
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0 GIT_SHA=$GIT_SHA
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /repo/apps/admin/.next/standalone ./
COPY --from=build /repo/apps/admin/.next/static ./apps/admin/.next/static
COPY --from=build /repo/apps/admin/public ./apps/admin/public
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:3000/login >/dev/null || exit 1
CMD ["node", "apps/admin/server.js"]
