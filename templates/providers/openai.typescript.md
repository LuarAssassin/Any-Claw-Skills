# Provider: OpenAI (TypeScript)

Template for OpenAI LLM provider integration using the official `openai` SDK.

## Generated File: `providers/openai.ts`

```typescript
/**
 * OpenAI LLM provider for {{PROJECT_NAME}}.
 */

import OpenAI from "openai";

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
  function: { name: string; arguments: string };
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

export class OpenAIProvider implements Provider {
  private client: OpenAI;
  private model: string;
  private maxRetries: number;

  constructor(opts: {
    apiKey?: string;
    model?: string;
    baseURL?: string;
    maxRetries?: number;
    timeout?: number;
  } = {}) {
    this.model = opts.model ?? "gpt-4o";
    this.maxRetries = opts.maxRetries ?? 3;
    this.client = new OpenAI({
      apiKey: opts.apiKey,
      baseURL: opts.baseURL,
      timeout: opts.timeout ?? 60_000,
    });
  }

  private buildTools(tools?: ToolDef[]): OpenAI.ChatCompletionTool[] | undefined {
    if (!tools?.length) return undefined;
    return tools.map((t) => ({
      type: "function" as const,
      function: { name: t.name, description: t.description, parameters: t.parameters },
    }));
  }

  private async callWithRetry(
    params: OpenAI.ChatCompletionCreateParamsNonStreaming
  ): Promise<OpenAI.ChatCompletion> {
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < this.maxRetries; attempt++) {
      try {
        return await this.client.chat.completions.create(params);
      } catch (err) {
        lastError = err as Error;
        const isRetryable =
          err instanceof OpenAI.RateLimitError ||
          (err instanceof OpenAI.APIError && (err.status ?? 0) >= 500);
        if (!isRetryable) throw err;
        await new Promise((r) => setTimeout(r, Math.min(2 ** attempt * 1000, 16_000)));
      }
    }
    throw lastError;
  }

  async chat(messages: Message[], options: ChatOptions = {}): Promise<Response> {
    const model = options.model ?? this.model;
    const params: OpenAI.ChatCompletionCreateParamsNonStreaming = {
      model,
      messages: messages as OpenAI.ChatCompletionMessageParam[],
      tools: this.buildTools(options.tools),
    };

    const resp = await this.callWithRetry(params);
    const choice = resp.choices[0];
    const toolCalls: ToolCall[] = (choice.message.tool_calls ?? []).map((tc) => ({
      id: tc.id,
      function: { name: tc.function.name, arguments: tc.function.arguments },
    }));

    return {
      content: choice.message.content ?? "",
      tool_calls: toolCalls,
      usage: {
        prompt_tokens: resp.usage?.prompt_tokens ?? 0,
        completion_tokens: resp.usage?.completion_tokens ?? 0,
        total_tokens: resp.usage?.total_tokens ?? 0,
      },
      model: resp.model,
      finish_reason: choice.finish_reason,
    };
  }

  async *chatStream(messages: Message[], options: ChatOptions = {}): AsyncIterable<string> {
    const model = options.model ?? this.model;
    const stream = await this.client.chat.completions.create({
      model,
      messages: messages as OpenAI.ChatCompletionMessageParam[],
      tools: this.buildTools(options.tools),
      stream: true,
    });

    for await (const chunk of stream) {
      const delta = chunk.choices[0]?.delta?.content;
      if (delta) yield delta;
    }
  }
}
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | Yes | OpenAI API key (read automatically by SDK) |
| `OPENAI_BASE_URL` | No | Override base URL for OpenAI-compatible APIs |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | npm package name |

## Dependencies

```json
{
  "openai": "^4.0.0"
}
```
