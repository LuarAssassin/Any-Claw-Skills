# index.ts.md

Template for the Full/TypeScript (OpenClaw-tier) scaffold.

## Generated File: `src/index.ts`

```typescript
/**
 * {{PROJECT_NAME}} - Entry Point
 *
 * Wires together the core subsystems using dependency injection:
 *   - Agent runtime (message processing, tool execution)
 *   - Provider router (multi-LLM support)
 *   - Channel manager (input sources)
 *   - Tool registry (extensible capabilities)
 *   - Storage backend (conversation persistence)
 *   - Observability (structured logging, metrics, tracing)
 */

import { createAgent } from "./core/agent";
import { createProviderRouter, ProviderConfig } from "./providers/router";
import { createChannelManager } from "./channels/manager";
import { createToolRegistry } from "./tools/registry";
import { createStorage } from "./storage/factory";
import { createObservability, Logger } from "./observability";
import { loadConfig, AppConfig } from "./config";
import { gracefulShutdown } from "./lifecycle";

// ---------------------------------------------------------------------------
// Bootstrap
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  // 1. Load validated configuration
  const config: AppConfig = loadConfig({
    configPath: process.env["{{ENV_PREFIX}}_CONFIG_PATH"] ?? "./config.yaml",
    envPrefix: "{{ENV_PREFIX}}",
  });

  // 2. Observability (must be first so every other subsystem can log)
  const obs = createObservability({
    serviceName: "{{PROJECT_NAME}}",
    logLevel: config.logLevel,
    enableTracing: config.tracing.enabled,
    tracingEndpoint: config.tracing.endpoint,
    enableMetrics: config.metrics.enabled,
    metricsPort: config.metrics.port,
  });
  const log: Logger = obs.logger;

  log.info("Booting {{PROJECT_NAME}}", { version: config.version });

  // 3. Storage backend (SQLite, Postgres, or in-memory)
  const storage = await createStorage({
    driver: config.storage.driver,
    connectionString: config.storage.connectionString,
    migrationsPath: config.storage.migrationsPath,
    logger: log,
  });

  // 4. Provider router (OpenAI, Anthropic, local, etc.)
  const providerConfigs: ProviderConfig[] = config.providers.map((p) => ({
    name: p.name,
    kind: p.kind,
    apiKey: p.apiKey,
    baseUrl: p.baseUrl,
    model: p.model,
    maxTokens: p.maxTokens,
    temperature: p.temperature,
    priority: p.priority,
    rateLimitRpm: p.rateLimitRpm,
  }));

  const providerRouter = createProviderRouter({
    providers: providerConfigs,
    strategy: config.routing.strategy, // "priority" | "round-robin" | "cost"
    fallbackEnabled: config.routing.fallbackEnabled,
    logger: log,
  });

  // 5. Tool registry
  const toolRegistry = createToolRegistry({ logger: log });

  // Register built-in tools
  for (const toolPath of config.tools.builtIn) {
    const toolModule = await import(toolPath);
    toolRegistry.register(toolModule.default ?? toolModule.tool);
  }

  // Register plugin tools
  for (const pluginPath of config.tools.plugins) {
    const pluginModule = await import(pluginPath);
    toolRegistry.register(pluginModule.default ?? pluginModule.tool);
  }

  log.info("Tool registry ready", { count: toolRegistry.count() });

  // 6. Core agent runtime
  const agent = createAgent({
    providerRouter,
    toolRegistry,
    storage,
    logger: log,
    systemPrompt: config.agent.systemPrompt,
    maxTurns: config.agent.maxTurns,
    maxRetries: config.agent.maxRetries,
    retryDelayMs: config.agent.retryDelayMs,
    maxHistoryTokens: config.agent.maxHistoryTokens,
  });

  // 7. Channel manager (HTTP, WebSocket, CLI, webhooks)
  const channelManager = createChannelManager({
    agent,
    logger: log,
    channels: config.channels,
  });

  // 8. Start accepting messages
  await channelManager.start();

  log.info("{{PROJECT_NAME}} is running", {
    channels: channelManager.activeChannelNames(),
    providers: providerRouter.activeProviderNames(),
    tools: toolRegistry.listNames(),
  });

  // 9. Graceful shutdown
  gracefulShutdown({
    logger: log,
    onShutdown: async () => {
      log.info("Shutting down...");
      await channelManager.stop();
      await storage.close();
      obs.shutdown();
    },
  });
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

main().catch((err: unknown) => {
  console.error("Fatal startup error:", err);
  process.exit(1);
});
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | NPM package / service name (kebab-case, e.g. `my-agent`) |
| `{{ENV_PREFIX}}` | Environment variable prefix (UPPER_SNAKE, e.g. `MY_AGENT`) |
