# Provider: Anthropic (TypeScript)

Template for Anthropic LLM provider integration using the official `@anthropic-ai/sdk`.

## Generated File: `providers/anthropic.ts`

```typescript
/**
 * Anthropic LLM provider for {{PROJECT_NAME}}.
 */

import Anthropic from "@anthropic-ai/sdk";

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
  maxTokens?: number;
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

export class AnthropicProvider implements Provider {
  private client: Anthropic;
  private model: string;
  private maxTokens: number;
  private maxRetries: number;

  constructor(opts: {
    apiKey?: string;
    model?: string;
    maxTokens?: number;
    maxRetries?: number;
  } = {}) {
    this.model = opts.model ?? "claude-sonnet-4-20250514";
    this.maxTokens = opts.maxTokens ?? 4096;
    this.maxRetries = opts.maxRetries ?? 3;
    this.client = new Anthropic({ apiKey: opts.apiKey });
  }

  private buildTools(tools?: ToolDef[]): Anthropic.Tool[] | undefined {
    if (!tools?.length) return undefined;
    return tools.map((t) => ({
      name: t.name,
      description: t.description,
      input_schema: t.parameters as Anthropic.Tool.InputSchema,
    }));
  }

  private formatMessages(messages: Message[]): {
    system: string | undefined;
    formatted: Anthropic.MessageParam[];
  } {
    let system: string | undefined;
    const formatted: Anthropic.MessageParam[] = [];

    for (const m of messages) {
      if (m.role === "system") {
        system = m.content;
        continue;
      }
      if (m.role === "tool") {
        formatted.push({
          role: "user",
          content: [
            {
              type: "tool_result",
              tool_use_id: m.tool_call_id!,
              content: m.content,
            },
          ],
        });
        continue;
      }
      if (m.tool_calls?.length) {
        const content: Anthropic.ContentBlockParam[] = [];
        if (m.content) content.push({ type: "text", text: m.content });
        for (const tc of m.tool_calls) {
          const args =
            typeof tc.function.arguments === "string"
              ? JSON.parse(tc.function.arguments)
              : tc.function.arguments;
          content.push({ type: "tool_use", id: tc.id, name: tc.function.name, input: args });
        }
        formatted.push({ role: "assistant", content });
        continue;
      }
      formatted.push({ role: m.role as "user" | "assistant", content: m.content });
    }
    return { system, formatted };
  }

  private async callWithRetry(
    params: Anthropic.MessageCreateParamsNonStreaming
  ): Promise<Anthropic.Message> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < this.maxRetries; attempt++) {
      try {
        return await this.client.messages.create(params);
      } catch (err) {
        lastError = err as Error;
        const isRetryable =
          err instanceof Anthropic.RateLimitError ||
          (err instanceof Anthropic.APIError && (err.status ?? 0) >= 500);
        if (!isRetryable) throw err;
        await new Promise((r) => setTimeout(r, Math.min(2 ** attempt * 1000, 16_000)));
      }
    }
    throw lastError;
  }

  async chat(messages: Message[], options: ChatOptions = {}): Promise<Response> {
    const { system, formatted } = this.formatMessages(messages);
    const params: Anthropic.MessageCreateParamsNonStreaming = {
      model: options.model ?? this.model,
      max_tokens: options.maxTokens ?? this.maxTokens,
      messages: formatted,
      ...(system ? { system } : {}),
      ...(options.tools ? { tools: this.buildTools(options.tools) } : {}),
    };

    const resp = await this.callWithRetry(params);
    let content = "";
    const toolCalls: ToolCall[] = [];

    for (const block of resp.content) {
      if (block.type === "text") {
        content += block.text;
      } else if (block.type === "tool_use") {
        toolCalls.push({
          id: block.id,
          function: { name: block.name, arguments: block.input as Record<string, unknown> },
        });
      }
    }

    return {
      content,
      tool_calls: toolCalls,
      usage: {
        prompt_tokens: resp.usage.input_tokens,
        completion_tokens: resp.usage.output_tokens,
        total_tokens: resp.usage.input_tokens + resp.usage.output_tokens,
      },
      model: resp.model,
      finish_reason: resp.stop_reason ?? "end_turn",
    };
  }

  async *chatStream(messages: Message[], options: ChatOptions = {}): AsyncIterable<string> {
    const { system, formatted } = this.formatMessages(messages);
    const stream = this.client.messages.stream({
      model: options.model ?? this.model,
      max_tokens: options.maxTokens ?? this.maxTokens,
      messages: formatted,
      ...(system ? { system } : {}),
      ...(options.tools ? { tools: this.buildTools(options.tools) } : {}),
    });

    for await (const event of stream) {
      if (
        event.type === "content_block_delta" &&
        event.delta.type === "text_delta"
      ) {
        yield event.delta.text;
      }
    }
  }
}
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key (read automatically by SDK) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | npm package name |

## Dependencies

```json
{
  "@anthropic-ai/sdk": "^0.39.0"
}
```
