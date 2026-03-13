# dockerfile.md

Template for the Full/TypeScript (OpenClaw-tier) scaffold.

## Generated File: `Dockerfile`

```dockerfile
# =============================================================================
# {{PROJECT_NAME}} - Multi-stage production Dockerfile
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Install dependencies
# ---------------------------------------------------------------------------
FROM node:{{NODE_VERSION}}-slim AS deps

WORKDIR /app

# Copy package manifests first for layer caching
COPY package.json package-lock.json* pnpm-lock.yaml* yarn.lock* ./

# Install with the available lock-file
RUN --mount=type=cache,target=/root/.npm \
    if [ -f pnpm-lock.yaml ]; then \
      corepack enable pnpm && pnpm install --frozen-lockfile; \
    elif [ -f yarn.lock ]; then \
      yarn install --frozen-lockfile; \
    else \
      npm ci; \
    fi

# ---------------------------------------------------------------------------
# Stage 2: Build TypeScript
# ---------------------------------------------------------------------------
FROM node:{{NODE_VERSION}}-slim AS builder

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build

# Prune dev dependencies after build
RUN --mount=type=cache,target=/root/.npm \
    if [ -f pnpm-lock.yaml ]; then \
      corepack enable pnpm && pnpm prune --prod; \
    elif [ -f yarn.lock ]; then \
      yarn install --production --frozen-lockfile; \
    else \
      npm prune --production; \
    fi

# ---------------------------------------------------------------------------
# Stage 3: Production image
# ---------------------------------------------------------------------------
FROM node:{{NODE_VERSION}}-slim AS runner

# Security: run as non-root
RUN groupadd --system --gid 1001 appgroup && \
    useradd  --system --uid 1001 --gid appgroup appuser

WORKDIR /app

# Copy only what is needed at runtime
COPY --from=builder --chown=appuser:appgroup /app/dist          ./dist
COPY --from=builder --chown=appuser:appgroup /app/node_modules  ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/package.json  ./package.json

# Optional: copy migration files if using SQL migrations
COPY --from=builder --chown=appuser:appgroup /app/migrations ./migrations

# Create data directory for SQLite (if applicable)
RUN mkdir -p /app/data && chown appuser:appgroup /app/data

ENV NODE_ENV=production
ENV {{ENV_PREFIX}}_STORAGE_PATH=/app/data

EXPOSE {{PORT}}

USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:{{PORT}}/health').then(r=>{if(!r.ok)throw 1})" || exit 1

CMD ["node", "dist/index.js"]
```

## Generated File: `docker-compose.yml`

```yaml
# =============================================================================
# {{PROJECT_NAME}} - Docker Compose (development + production profiles)
# =============================================================================

version: "3.9"

services:
  # ---------------------------------------------------------------------------
  # Application
  # ---------------------------------------------------------------------------
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: {{PROJECT_NAME}}
    restart: unless-stopped
    ports:
      - "${{{ENV_PREFIX}}_PORT:-{{PORT}}}:{{PORT}}"
    environment:
      - NODE_ENV=production
      - {{ENV_PREFIX}}_CONFIG_PATH=/app/config.yaml
      - {{ENV_PREFIX}}_STORAGE_DRIVER=postgres
      - {{ENV_PREFIX}}_STORAGE_CONNECTION_STRING=postgresql://{{DB_USER}}:{{DB_PASSWORD}}@postgres:5432/{{DB_NAME}}
      - {{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY=${{{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY}
    volumes:
      - app-data:/app/data
      - ./config.yaml:/app/config.yaml:ro
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - backend
    profiles:
      - production

  # ---------------------------------------------------------------------------
  # Application (development - hot reload)
  # ---------------------------------------------------------------------------
  app-dev:
    build:
      context: .
      dockerfile: Dockerfile
      target: deps
    container_name: {{PROJECT_NAME}}-dev
    working_dir: /app
    command: npx tsx watch src/index.ts
    ports:
      - "${{{ENV_PREFIX}}_PORT:-{{PORT}}}:{{PORT}}"
    environment:
      - NODE_ENV=development
      - {{ENV_PREFIX}}_CONFIG_PATH=/app/config.yaml
      - {{ENV_PREFIX}}_STORAGE_DRIVER=postgres
      - {{ENV_PREFIX}}_STORAGE_CONNECTION_STRING=postgresql://{{DB_USER}}:{{DB_PASSWORD}}@postgres:5432/{{DB_NAME}}
      - {{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY=${{{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY}
    volumes:
      - .:/app
      - /app/node_modules
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - backend
    profiles:
      - development

  # ---------------------------------------------------------------------------
  # PostgreSQL
  # ---------------------------------------------------------------------------
  postgres:
    image: postgres:16-alpine
    container_name: {{PROJECT_NAME}}-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: {{DB_USER}}
      POSTGRES_PASSWORD: {{DB_PASSWORD}}
      POSTGRES_DB: {{DB_NAME}}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U {{DB_USER}} -d {{DB_NAME}}"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - backend

  # ---------------------------------------------------------------------------
  # Redis (optional: caching, rate-limiting, pub/sub)
  # ---------------------------------------------------------------------------
  redis:
    image: redis:7-alpine
    container_name: {{PROJECT_NAME}}-redis
    restart: unless-stopped
    ports:
      - "${REDIS_PORT:-6379}:6379"
    volumes:
      - redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    networks:
      - backend
    profiles:
      - production
      - development

volumes:
  app-data:
  pgdata:
  redisdata:

networks:
  backend:
    driver: bridge
```

## Generated File: `.dockerignore`

```text
node_modules
dist
coverage
.git
.env
.env.*
*.md
tests
.vscode
.idea
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | NPM package / service name (kebab-case) |
| `{{ENV_PREFIX}}` | Environment variable prefix (UPPER_SNAKE, e.g. `MY_AGENT`) |
| `{{NODE_VERSION}}` | Node.js major version for the base image (e.g. `22`) |
| `{{PORT}}` | HTTP port the application listens on (e.g. `3000`) |
| `{{DB_USER}}` | PostgreSQL user name (e.g. `appuser`) |
| `{{DB_PASSWORD}}` | PostgreSQL password (should be injected from secrets) |
| `{{DB_NAME}}` | PostgreSQL database name (e.g. `myagent`) |
