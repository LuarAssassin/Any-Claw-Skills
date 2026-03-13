# index.ts.md

Template for the Nano/TypeScript tier scaffold.

## Generated File: `src/index.ts`

```typescript
import { loadConfig, type AppConfig } from "./config";
import { createProvider, type Provider } from "./provider";
import { createChannel, type Channel, type IncomingMessage } from "./channel";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface AssistantContext {
  config: AppConfig;
  provider: Provider;
  channel: Channel;
}

// ---------------------------------------------------------------------------
// Message handling
// ---------------------------------------------------------------------------

async function handleMessage(
  ctx: AssistantContext,
  message: IncomingMessage,
): Promise<void> {
  const { provider, channel } = ctx;

  console.log(
    `[${new Date().toISOString()}] Received from ${message.userId}: ${message.text.slice(0, 80)}`,
  );

  try {
    const reply = await provider.chat({
      systemPrompt: ctx.config.systemPrompt,
      userMessage: message.text,
      conversationId: message.conversationId,
    });

    await channel.send({
      userId: message.userId,
      conversationId: message.conversationId,
      text: reply,
    });
  } catch (err) {
    const errorMessage =
      err instanceof Error ? err.message : "Unknown error occurred";
    console.error(`[error] Failed to handle message: ${errorMessage}`);

    await channel.send({
      userId: message.userId,
      conversationId: message.conversationId,
      text: "{{ERROR_REPLY_TEXT}}",
    });
  }
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

async function start(): Promise<void> {
  console.log("{{PROJECT_NAME}} starting...");

  const config = loadConfig();

  console.log(`  Provider : ${config.provider.type}`);
  console.log(`  Channel  : ${config.channel.type}`);
  console.log(`  Port     : ${config.channel.port}`);

  const provider = createProvider(config.provider);
  const channel = createChannel(config.channel);

  const ctx: AssistantContext = { config, provider, channel };

  channel.onMessage((message) => {
    handleMessage(ctx, message).catch((err) => {
      console.error("[fatal] Unhandled error in message handler:", err);
    });
  });

  await channel.listen();

  console.log(`{{PROJECT_NAME}} listening on port ${config.channel.port}`);
}

// ---------------------------------------------------------------------------
// Shutdown
// ---------------------------------------------------------------------------

function registerShutdownHooks(): void {
  const signals: NodeJS.Signals[] = ["SIGINT", "SIGTERM"];

  for (const signal of signals) {
    process.on(signal, () => {
      console.log(`\nReceived ${signal}, shutting down...`);
      process.exit(0);
    });
  }

  process.on("uncaughtException", (err) => {
    console.error("[fatal] Uncaught exception:", err);
    process.exit(1);
  });

  process.on("unhandledRejection", (reason) => {
    console.error("[fatal] Unhandled rejection:", reason);
    process.exit(1);
  });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

registerShutdownHooks();
start().catch((err) => {
  console.error("[fatal] Failed to start:", err);
  process.exit(1);
});
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | Display name of the project, used in startup logs |
| `{{ERROR_REPLY_TEXT}}` | Fallback message sent to the user when the provider fails (e.g. "Sorry, something went wrong.") |
