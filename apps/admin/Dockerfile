# Build from the repo root:  docker build -f apps/admin/Dockerfile -t yaqeen-admin .
FROM node:22-alpine AS base
RUN corepack enable && corepack prepare pnpm@10.34.7 --activate
WORKDIR /repo

FROM base AS build
ENV NEXT_TELEMETRY_DISABLED=1
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json tsconfig.base.json ./
COPY packages/contracts/package.json packages/contracts/
COPY packages/design-tokens/package.json packages/design-tokens/
COPY apps/admin/package.json apps/admin/
RUN pnpm install --frozen-lockfile --filter @yaqeen/admin...
COPY packages/contracts packages/contracts
COPY packages/design-tokens packages/design-tokens
COPY apps/admin apps/admin
RUN pnpm --filter @yaqeen/contracts build && pnpm --filter @yaqeen/admin build

# Next.js standalone output: only the traced runtime files.
FROM node:22-alpine AS runtime
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /repo/apps/admin/.next/standalone ./
COPY --from=build /repo/apps/admin/.next/static ./apps/admin/.next/static
COPY --from=build /repo/apps/admin/public ./apps/admin/public
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:3000/login >/dev/null || exit 1
CMD ["node", "apps/admin/server.js"]
