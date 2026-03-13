# dockerfile.md

Template for the Nano/TypeScript tier scaffold.

## Generated File: `Dockerfile`

```dockerfile
# ---------------------------------------------------------------------------
# Stage 1: Build
# ---------------------------------------------------------------------------
FROM node:20-slim AS builder

WORKDIR /app

# Copy dependency manifests first for layer caching
COPY package.json package-lock.json* ./

# Install all dependencies (including devDependencies for tsc)
RUN npm ci

# Copy source code and TypeScript config
COPY tsconfig.json ./
COPY src/ ./src/

# Compile TypeScript to JavaScript
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2: Runtime
# ---------------------------------------------------------------------------
FROM node:20-slim AS runtime

LABEL maintainer="{{MAINTAINER}}"
LABEL description="{{PROJECT_DESCRIPTION}}"

# Run as non-root for security
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --shell /bin/sh --create-home appuser

WORKDIR /app

# Copy dependency manifests
COPY package.json package-lock.json* ./

# Install production dependencies only
RUN npm ci --omit=dev \
    && npm cache clean --force

# Copy compiled output from builder
COPY --from=builder /app/dist ./dist

# Switch to non-root user
USER appuser

# Expose the default port
EXPOSE {{DEFAULT_PORT}}

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:{{DEFAULT_PORT}}{{HEALTH_CHECK_PATH}}').then(r => { if (!r.ok) throw new Error(); })" || exit 1

# Start the application
CMD ["node", "dist/index.js"]
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{MAINTAINER}}` | Maintainer contact string (e.g. `"you@example.com"`) |
| `{{PROJECT_DESCRIPTION}}` | One-line project description for the Docker label |
| `{{DEFAULT_PORT}}` | Port the container exposes, must match the app config default (e.g. `3000`) |
| `{{HEALTH_CHECK_PATH}}` | HTTP path for the health check endpoint (e.g. `/healthz`) |

## Notes

- Uses multi-stage build to keep the final image small (no `tsc`, no `devDependencies`).
- Runs as a non-root user (`appuser:appgroup`) for security.
- The health check uses Node's built-in `fetch` (available in Node 20+).
- If the project uses `pnpm` or `yarn`, replace `npm ci` with the equivalent command.
