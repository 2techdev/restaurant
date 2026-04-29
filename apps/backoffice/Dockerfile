# syntax=docker/dockerfile:1.6
# GastroCore backoffice — Next.js 15 production image
# Build: docker build -t gastrocore-backoffice -f apps/backoffice/Dockerfile apps/backoffice
# Run:   docker run -p 3001:3001 --env-file apps/backoffice/.env.production gastrocore-backoffice

# ---------- 1) deps ----------
FROM node:22-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable && pnpm install --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  else npm install; fi

# ---------- 2) build ----------
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1
RUN \
  if [ -f pnpm-lock.yaml ]; then corepack enable && pnpm build; \
  else npm run build; fi

# ---------- 3) runner ----------
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3001
ENV HOSTNAME=0.0.0.0

RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs

# Next.js standalone output (next.config.ts → output: "standalone")
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/messages ./messages

USER nextjs
EXPOSE 3001

CMD ["node", "server.js"]
