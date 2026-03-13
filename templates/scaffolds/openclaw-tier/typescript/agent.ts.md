# agent.ts.md

Template for the Full/TypeScript (OpenClaw-tier) scaffold.

## Generated File: `src/core/agent.ts`

```typescript
/**
 * Core Agent Runtime
 *
 * Responsibilities:
 *   - Process incoming messages through a provider-routed LLM
 *   - Execute tool calls returned by the LLM via the tool registry
 *   - Manage conversation history with token-aware truncation
 *   - Retry transient provider failures with exponential back-off
 */

import { ProviderRouter, ChatMessage, ChatCompletion, ToolCall } from "../providers/router";
import { ToolRegistry, ToolResult } from "../tools/registry";
import { Storage, Conversation, StoredMessage } from "../storage/factory";
import { Logger } from "../observability";

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface AgentOptions {
  providerRouter: ProviderRouter;
  toolRegistry: ToolRegistry;
  storage: Storage;
  logger: Logger;
  systemPrompt: string;
  maxTurns: number;
  maxRetries: number;
  retryDelayMs: number;
  maxHistoryTokens: number;
}

export interface AgentRequest {
  conversationId: string;
  userId: string;
  channelId: string;
  content: string;
  attachments?: Attachment[];
  metadata?: Record<string, unknown>;
}

export interface Attachment {
  kind: "image" | "file" | "audio";
  url: string;
  mimeType: string;
  name?: string;
}

export interface AgentResponse {
  conversationId: string;
  content: string;
  toolCallResults: ToolResult[];
  turnCount: number;
  providerUsed: string;
  tokenUsage: TokenUsage;
}

export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
}

export interface Agent {
  processMessage(request: AgentRequest): Promise<AgentResponse>;
  getConversation(conversationId: string): Promise<Conversation | null>;
  clearConversation(conversationId: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

export function createAgent(opts: AgentOptions): Agent {
  const {
    providerRouter,
    toolRegistry,
    storage,
    logger,
    systemPrompt,
    maxTurns,
    maxRetries,
    retryDelayMs,
    maxHistoryTokens,
  } = opts;

  // ---- helpers ------------------------------------------------------------

  async function loadHistory(conversationId: string): Promise<ChatMessage[]> {
    const stored: StoredMessage[] = await storage.getMessages(conversationId);

    // Token-aware truncation: keep the most recent messages that fit within
    // the configured token budget.  We use a rough heuristic of 4 chars per
    // token which is close enough for planning purposes.
    const CHARS_PER_TOKEN = 4;
    let budget = maxHistoryTokens * CHARS_PER_TOKEN;
    const messages: ChatMessage[] = [];

    for (let i = stored.length - 1; i >= 0; i--) {
      const msg = stored[i]!;
      const cost = (msg.content?.length ?? 0) + (msg.role.length);
      if (budget - cost < 0 && messages.length > 0) break;
      budget -= cost;
      messages.unshift({
        role: msg.role as ChatMessage["role"],
        content: msg.content,
        name: msg.name,
        toolCallId: msg.toolCallId,
        toolCalls: msg.toolCalls,
      });
    }

    return messages;
  }

  async function persistMessage(
    conversationId: string,
    message: ChatMessage,
  ): Promise<void> {
    await storage.saveMessage(conversationId, {
      role: message.role,
      content: message.content ?? "",
      name: message.name,
      toolCallId: message.toolCallId,
      toolCalls: message.toolCalls,
      createdAt: new Date().toISOString(),
    });
  }

  async function callProviderWithRetry(
    messages: ChatMessage[],
    tools: ToolCall[],
  ): Promise<ChatCompletion> {
    let lastError: unknown;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        const completion = await providerRouter.chat({
          messages,
          tools: tools.length > 0 ? tools : undefined,
        });
        return completion;
      } catch (err: unknown) {
        lastError = err;
        const isRetryable = isTransientError(err);
        logger.warn("Provider call failed", {
          attempt,
          maxRetries,
          retryable: isRetryable,
          error: String(err),
        });

        if (!isRetryable || attempt === maxRetries) {
          break;
        }

        const delay = retryDelayMs * Math.pow(2, attempt - 1);
        await sleep(delay);
      }
    }

    throw new AgentError(
      `Provider failed after ${maxRetries} attempts: ${String(lastError)}`,
      "PROVIDER_EXHAUSTED",
      { cause: lastError },
    );
  }

  async function executeToolCalls(
    toolCalls: ToolCall[],
  ): Promise<ToolResult[]> {
    const results: ToolResult[] = [];

    for (const call of toolCalls) {
      const startMs = Date.now();
      let result: ToolResult;

      try {
        const tool = toolRegistry.get(call.function.name);
        if (!tool) {
          result = {
            toolCallId: call.id,
            name: call.function.name,
            content: `Error: unknown tool "${call.function.name}"`,
            isError: true,
            durationMs: Date.now() - startMs,
          };
        } else {
          const args = JSON.parse(call.function.arguments) as Record<string, unknown>;
          const output = await tool.execute(args);
          result = {
            toolCallId: call.id,
            name: call.function.name,
            content: typeof output === "string" ? output : JSON.stringify(output),
            isError: false,
            durationMs: Date.now() - startMs,
          };
        }
      } catch (err: unknown) {
        result = {
          toolCallId: call.id,
          name: call.function.name,
          content: `Tool execution error: ${String(err)}`,
          isError: true,
          durationMs: Date.now() - startMs,
        };
      }

      logger.debug("Tool executed", {
        tool: result.name,
        ok: !result.isError,
        durationMs: result.durationMs,
      });
      results.push(result);
    }

    return results;
  }

  // ---- main loop ----------------------------------------------------------

  async function processMessage(request: AgentRequest): Promise<AgentResponse> {
    const { conversationId, content } = request;
    logger.info("Processing message", {
      conversationId,
      userId: request.userId,
      channelId: request.channelId,
    });

    // Ensure conversation record exists
    await storage.ensureConversation(conversationId, {
      userId: request.userId,
      channelId: request.channelId,
      metadata: request.metadata,
    });

    // Build message list: system + history + new user message
    const history = await loadHistory(conversationId);
    const userMessage: ChatMessage = { role: "user", content };
    await persistMessage(conversationId, userMessage);

    const messages: ChatMessage[] = [
      { role: "system", content: systemPrompt },
      ...history,
      userMessage,
    ];

    // Gather available tool definitions for the provider
    const toolDefinitions = toolRegistry.listDefinitions();

    let turnCount = 0;
    let totalUsage: TokenUsage = { promptTokens: 0, completionTokens: 0, totalTokens: 0 };
    const allToolResults: ToolResult[] = [];
    let providerUsed = "";
    let assistantContent = "";

    while (turnCount < maxTurns) {
      turnCount++;

      const completion = await callProviderWithRetry(messages, toolDefinitions);
      providerUsed = completion.provider;
      totalUsage = addUsage(totalUsage, completion.usage);

      const assistantMsg = completion.message;
      messages.push(assistantMsg);
      await persistMessage(conversationId, assistantMsg);

      // If no tool calls, we are done
      if (!assistantMsg.toolCalls || assistantMsg.toolCalls.length === 0) {
        assistantContent = assistantMsg.content ?? "";
        break;
      }

      // Execute tool calls and feed results back
      const toolResults = await executeToolCalls(assistantMsg.toolCalls);
      allToolResults.push(...toolResults);

      for (const result of toolResults) {
        const toolMsg: ChatMessage = {
          role: "tool",
          content: result.content,
          toolCallId: result.toolCallId,
        };
        messages.push(toolMsg);
        await persistMessage(conversationId, toolMsg);
      }
    }

    if (turnCount >= maxTurns && assistantContent === "") {
      assistantContent = "I reached the maximum number of processing steps. Please try again with a simpler request.";
      logger.warn("Max turns reached", { conversationId, maxTurns });
    }

    logger.info("Message processed", {
      conversationId,
      turnCount,
      toolCalls: allToolResults.length,
      provider: providerUsed,
      tokens: totalUsage.totalTokens,
    });

    return {
      conversationId,
      content: assistantContent,
      toolCallResults: allToolResults,
      turnCount,
      providerUsed,
      tokenUsage: totalUsage,
    };
  }

  // ---- public surface -----------------------------------------------------

  return {
    processMessage,

    async getConversation(conversationId: string): Promise<Conversation | null> {
      return storage.getConversation(conversationId);
    },

    async clearConversation(conversationId: string): Promise<void> {
      await storage.deleteConversation(conversationId);
      logger.info("Conversation cleared", { conversationId });
    },
  };
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

export class AgentError extends Error {
  code: string;
  constructor(message: string, code: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "AgentError";
    this.code = code;
  }
}

function isTransientError(err: unknown): boolean {
  if (err instanceof Error) {
    const msg = err.message.toLowerCase();
    return (
      msg.includes("rate limit") ||
      msg.includes("timeout") ||
      msg.includes("econnreset") ||
      msg.includes("503") ||
      msg.includes("429")
    );
  }
  return false;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function addUsage(a: TokenUsage, b: TokenUsage): TokenUsage {
  return {
    promptTokens: a.promptTokens + b.promptTokens,
    completionTokens: a.completionTokens + b.completionTokens,
    totalTokens: a.totalTokens + b.totalTokens,
  };
}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| (none) | This file uses no direct placeholders. It depends on the interfaces exported by sibling modules (`providers/router`, `tools/registry`, `storage/factory`, `observability`) which are configured at the `index.ts` level via `{{PROJECT_NAME}}` and `{{ENV_PREFIX}}`. |
