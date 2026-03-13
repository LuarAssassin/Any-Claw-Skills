# Provider: Provider Router (TypeScript)

Template for multi-provider router with fallback chain and cost tracking.

## Generated File: `providers/router.ts`

```typescript
/**
 * Multi-provider router for {{PROJECT_NAME}}.
 */

export interface Message {
  role: "system" | "user" | "assistant" | "tool";
  content: string;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
}

export interface ToolDef {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface ToolCall {
  id: string;
  function: { name: string; arguments: string | Record<string, unknown> };
}

export interface ChatOptions {
  tools?: ToolDef[];
  stream?: boolean;
  model?: string;
}

export interface Response {
  content: string;
  tool_calls: ToolCall[];
  usage: { prompt_tokens: number; completion_tokens: number; total_tokens: number };
  model: string;
  finish_reason: string;
}

export interface Provider {
  chat(messages: Message[], options?: ChatOptions): Promise<Response>;
  chatStream(messages: Message[], options?: ChatOptions): AsyncIterable<string>;
}

/** Cost per 1M tokens [input, output] in USD. */
const COST_TABLE: Record<string, [number, number]> = {
  "gpt-4o": [2.5, 10.0],
  "gpt-4o-mini": [0.15, 0.6],
  "gpt-4.1": [2.0, 8.0],
  "gpt-4.1-mini": [0.4, 1.6],
  "claude-sonnet-4-20250514": [3.0, 15.0],
  "claude-haiku-35-20241022": [0.8, 4.0],
  "claude-opus-4-20250514": [15.0, 75.0],
};

interface UsageRecord {
  provider: string;
  model: string;
  promptTokens: number;
  completionTokens: number;
  costUsd: number;
  latencyMs: number;
  timestamp: number;
}

export interface ProviderConfig {
  name: string;
  provider: Provider;
  models: string[];
  priority?: number;
}

export class ProviderRouter implements Provider {
  private configs: ProviderConfig[];
  private modelMap = new Map<string, ProviderConfig>();
  private usage: UsageRecord[] = [];

  constructor(configs: ProviderConfig[]) {
    this.configs = [...configs].sort((a, b) => (a.priority ?? 0) - (b.priority ?? 0));
    for (const cfg of this.configs) {
      for (const model of cfg.models) {
        this.modelMap.set(model, cfg);
      }
    }
  }

  private resolve(model?: string): ProviderConfig[] {
    if (model && this.modelMap.has(model)) {
      const primary = this.modelMap.get(model)!;
      return [primary, ...this.configs.filter((c) => c !== primary)];
    }
    return this.configs;
  }

  private computeCost(model: string, prompt: number, completion: number): number {
    const rates = COST_TABLE[model];
    if (!rates) return 0;
    return (prompt * rates[0] + completion * rates[1]) / 1_000_000;
  }

  private record(config: ProviderConfig, resp: Response, latencyMs: number): void {
    this.usage.push({
      provider: config.name,
      model: resp.model,
      promptTokens: resp.usage.prompt_tokens,
      completionTokens: resp.usage.completion_tokens,
      costUsd: this.computeCost(resp.model, resp.usage.prompt_tokens, resp.usage.completion_tokens),
      latencyMs,
      timestamp: Date.now(),
    });
  }

  async chat(messages: Message[], options: ChatOptions = {}): Promise<Response> {
    const chain = this.resolve(options.model);
    let lastError: Error | null = null;

    for (const cfg of chain) {
      try {
        const start = performance.now();
        const result = await cfg.provider.chat(messages, options);
        this.record(cfg, result, performance.now() - start);
        return result;
      } catch (err) {
        lastError = err as Error;
        console.warn(`Provider ${cfg.name} failed: ${lastError.message}. Trying next.`);
      }
    }
    throw new Error(`All providers failed. Last error: ${lastError?.message}`);
  }

  async *chatStream(messages: Message[], options: ChatOptions = {}): AsyncIterable<string> {
    const chain = this.resolve(options.model);
    let lastError: Error | null = null;

    for (const cfg of chain) {
      try {
        yield* cfg.provider.chatStream(messages, options);
        return;
      } catch (err) {
        lastError = err as Error;
        console.warn(`Provider ${cfg.name} stream failed: ${lastError.message}. Trying next.`);
      }
    }
    throw new Error(`All providers failed. Last error: ${lastError?.message}`);
  }

  getTotalCost(): number {
    return this.usage.reduce((sum, r) => sum + r.costUsd, 0);
  }

  getUsageSummary(): {
    totalCostUsd: number;
    totalRequests: number;
    byProvider: Record<string, { requests: number; totalTokens: number; costUsd: number; avgLatencyMs: number }>;
  } {
    const byProvider: Record<string, { requests: number; totalTokens: number; costUsd: number; avgLatencyMs: number }> = {};
    for (const r of this.usage) {
      if (!byProvider[r.provider]) {
        byProvider[r.provider] = { requests: 0, totalTokens: 0, costUsd: 0, avgLatencyMs: 0 };
      }
      const entry = byProvider[r.provider];
      entry.requests++;
      entry.totalTokens += r.promptTokens + r.completionTokens;
      entry.costUsd += r.costUsd;
    }
    for (const [name, entry] of Object.entries(byProvider)) {
      const records = this.usage.filter((r) => r.provider === name);
      entry.avgLatencyMs = records.reduce((s, r) => s + r.latencyMs, 0) / (records.length || 1);
    }
    return { totalCostUsd: this.getTotalCost(), totalRequests: this.usage.length, byProvider };
  }
}
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `LLM_DEFAULT_PROVIDER` | No | Default provider name to route to |
| `LLM_FALLBACK_ENABLED` | No | Enable fallback chain (default: `true`) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | npm package name |

## Usage Example

```typescript
import { OpenAIProvider } from "./openai";
import { AnthropicProvider } from "./anthropic";
import { ProviderRouter } from "./router";

const router = new ProviderRouter([
  {
    name: "anthropic",
    provider: new AnthropicProvider({ model: "claude-sonnet-4-20250514" }),
    models: ["claude-sonnet-4-20250514", "claude-haiku-35-20241022"],
    priority: 0,
  },
  {
    name: "openai",
    provider: new OpenAIProvider({ model: "gpt-4o" }),
    models: ["gpt-4o", "gpt-4o-mini"],
    priority: 1,
  },
]);

const response = await router.chat(messages, { model: "claude-sonnet-4-20250514" });
console.log(router.getUsageSummary());
```
