# Build from the repo root:  docker build -f services/api/Dockerfile -t yaqeen-api .
FROM node:26-alpine AS base
RUN corepack enable && corepack prepare pnpm@10.34.7 --activate
WORKDIR /repo

FROM base AS build
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json tsconfig.base.json ./
# Whole contracts package: its `prepare` script compiles it during install.
COPY packages/contracts packages/contracts
COPY services/api/package.json services/api/
RUN pnpm install --frozen-lockfile --filter @yaqeen/api...
COPY services/api services/api
RUN pnpm --filter @yaqeen/contracts build && pnpm --filter @yaqeen/api build
RUN pnpm --filter @yaqeen/api deploy --prod --legacy /out

FROM node:26-alpine AS runtime
# The commit this image was built from: the Sentry release and a deploy marker in logs.
ARG GIT_SHA=dev
# tsc output is plain readable JS; source maps make stack traces (logs and Sentry) point at the .ts lines.
ENV NODE_ENV=production GIT_SHA=$GIT_SHA NODE_OPTIONS=--enable-source-maps
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /out/node_modules ./node_modules
COPY --from=build /out/package.json ./package.json
COPY --from=build /repo/services/api/dist ./dist
COPY --from=build /repo/services/api/drizzle ./drizzle
USER app
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:4000/health || exit 1
CMD ["node", "dist/main.js"]
