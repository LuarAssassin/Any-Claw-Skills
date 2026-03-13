# readme.md

Template for the Full/TypeScript (OpenClaw-tier) scaffold.

## Generated File: `README.md`

```markdown
# {{PROJECT_NAME}}

> {{PROJECT_DESCRIPTION}}

---

## Architecture

```
                        +---------------------+
                        |    Channel Manager   |
                        |  (HTTP / WS / CLI)   |
                        +----------+----------+
                                   |
                                   v
+------------------+    +----------+----------+    +------------------+
|  Tool Registry   +--->+    Agent Runtime     +<---+  Provider Router |
| (built-in + ext) |    | (message loop, retry)|    | (OpenAI, Claude) |
+------------------+    +----------+----------+    +------------------+
                                   |
                        +----------+----------+
                        |      Storage         |
                        | (SQLite / Postgres)  |
                        +----------+----------+
                                   |
                        +----------+----------+
                        |   Observability      |
                        | (pino, OTel traces)  |
                        +----------------------+
```

### Module Overview

| Module | Path | Responsibility |
|--------|------|----------------|
| Entry point | `src/index.ts` | Dependency injection, bootstrap |
| Agent runtime | `src/core/agent.ts` | Message loop, tool execution, retries |
| Provider router | `src/providers/router.ts` | Multi-LLM routing, failover, rate limits |
| Channel manager | `src/channels/manager.ts` | HTTP API, WebSocket, CLI adapters |
| Tool registry | `src/tools/registry.ts` | Register / discover / invoke tools |
| Storage | `src/storage/factory.ts` | Conversation persistence (SQLite, PG) |
| Config | `src/config.ts` | YAML + env var loading with Zod validation |
| Observability | `src/observability/index.ts` | Structured logging, OTel tracing, metrics |
| Lifecycle | `src/lifecycle.ts` | Graceful shutdown, signal handling |

---

## Quick Start

### Prerequisites

- Node.js >= 20
- npm, pnpm, or yarn
- (Optional) Docker & Docker Compose
- (Optional) PostgreSQL 16+

### 1. Install

```bash
git clone {{REPO_URL}}
cd {{PROJECT_NAME}}
npm install
```

### 2. Configure

Copy the example config and fill in your API keys:

```bash
cp config.example.yaml config.yaml
```

Key settings in `config.yaml`:

```yaml
providers:
  - name: primary
    kind: anthropic          # or "openai"
    apiKey: ${{{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY}
    model: claude-sonnet-4-20250514
    priority: 1

storage:
  driver: sqlite             # or "postgres"
  connectionString: ./data/{{PROJECT_NAME}}.db

channels:
  - kind: http
    port: {{PORT}}
```

Or use environment variables exclusively:

```bash
export {{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY="sk-..."
export {{ENV_PREFIX}}_STORAGE_DRIVER="sqlite"
```

### 3. Run

```bash
# Development (hot reload)
npm run dev

# Production
npm run build
npm start
```

### 4. Verify

```bash
curl -s http://localhost:{{PORT}}/health | jq .

curl -s -X POST http://localhost:{{PORT}}/api/v1/chat \
  -H "Content-Type: application/json" \
  -d '{"conversationId": "demo", "userId": "user-1", "content": "Hello!"}' \
  | jq .
```

---

## Docker

### Build & Run (production)

```bash
docker compose --profile production up -d
```

### Development (hot reload)

```bash
docker compose --profile development up
```

### Tear Down

```bash
docker compose down -v
```

---

## Project Structure

```
{{PROJECT_NAME}}/
  src/
    index.ts                   # Entry point, DI wiring
    config.ts                  # Config loading (YAML + env)
    lifecycle.ts               # Graceful shutdown
    core/
      agent.ts                 # Agent runtime
    providers/
      router.ts                # Provider routing logic
      openai.ts                # OpenAI adapter
      anthropic.ts             # Anthropic adapter
    channels/
      manager.ts               # Channel lifecycle
      http.ts                  # Express HTTP + REST API
      websocket.ts             # WebSocket channel
      cli.ts                   # Interactive CLI channel
    tools/
      registry.ts              # Tool discovery and invocation
      builtin/
        web-search.ts          # Example built-in tool
        calculator.ts          # Example built-in tool
    storage/
      factory.ts               # Storage driver factory
      sqlite.ts                # SQLite driver
      postgres.ts              # PostgreSQL driver
      migrate.ts               # Migration runner
    observability/
      index.ts                 # Logger + OTel setup
  migrations/
    001_init.sql               # Initial schema
  tests/
    unit/
      agent.test.ts
      router.test.ts
    integration/
      api.test.ts
      storage.test.ts
  config.example.yaml
  Dockerfile
  docker-compose.yml
  tsconfig.json
  package.json
```

---

## Testing

```bash
# Run all tests
npm test

# Watch mode
npm run test:watch

# With coverage
npm run test:coverage
```

Tests use [Vitest](https://vitest.dev/). Integration tests that need PostgreSQL use [Testcontainers](https://node.testcontainers.org/) to spin up a disposable database.

---

## Adding a Custom Tool

1. Create `src/tools/builtin/my-tool.ts`:

```typescript
import { ToolDefinition } from "../registry";

export const tool: ToolDefinition = {
  name: "my_tool",
  description: "Does something useful",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", description: "The input query" },
    },
    required: ["query"],
  },
  async execute(args) {
    const { query } = args as { query: string };
    // Your logic here
    return { result: `Processed: ${query}` };
  },
};

export default tool;
```

2. Register it in `config.yaml`:

```yaml
tools:
  builtIn:
    - ./tools/builtin/my-tool.js
```

---

## Adding a Provider

1. Create `src/providers/my-provider.ts` implementing the `Provider` interface.
2. Add the provider config to `config.yaml` under `providers`.
3. The router will auto-discover it by `kind` name.

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `{{ENV_PREFIX}}_CONFIG_PATH` | No | Path to config YAML (default: `./config.yaml`) |
| `{{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY` | Yes | API key for the primary LLM provider |
| `{{ENV_PREFIX}}_STORAGE_DRIVER` | No | `sqlite` (default) or `postgres` |
| `{{ENV_PREFIX}}_STORAGE_CONNECTION_STRING` | No | DB connection string |
| `{{ENV_PREFIX}}_LOG_LEVEL` | No | `debug`, `info` (default), `warn`, `error` |
| `{{ENV_PREFIX}}_PORT` | No | HTTP port (default: `{{PORT}}`) |
| `NODE_ENV` | No | `development` or `production` |

---

## Deployment

### Fly.io

```bash
fly launch --name {{PROJECT_NAME}}
fly secrets set {{ENV_PREFIX}}_PRIMARY_PROVIDER_API_KEY="sk-..."
fly deploy
```

### Railway / Render

Point the build command to `npm run build` and the start command to `npm start`. Set the environment variables listed above in the dashboard.

### Kubernetes

A Helm chart is not included but the Docker image works with any orchestrator. Key considerations:

- Mount `config.yaml` as a ConfigMap volume.
- Store API keys in a Secret and inject as env vars.
- The `/health` endpoint returns `200` when the service is ready.

---

## License

{{LICENSE}}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | NPM package / service name (kebab-case) |
| `{{PROJECT_DESCRIPTION}}` | One-line project description |
| `{{ENV_PREFIX}}` | Environment variable prefix (UPPER_SNAKE) |
| `{{PORT}}` | HTTP port (e.g. `3000`) |
| `{{REPO_URL}}` | Git clone URL for the repository |
| `{{LICENSE}}` | License identifier (e.g. `MIT`, `Apache-2.0`) |
