# Provider: Ollama (TypeScript)

Template for Ollama local LLM provider integration using fetch.

## Generated File: `providers/ollama.ts`

```typescript
/**
 * Ollama local LLM provider for {{PROJECT_NAME}}.
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

export interface OllamaModel {
  name: string;
  size: number;
  modified_at: string;
}

export class OllamaProvider implements Provider {
  private baseUrl: string;
  private model: string;

  constructor(opts: { baseUrl?: string; model?: string } = {}) {
    this.baseUrl = (opts.baseUrl ?? "http://localhost:11434").replace(/\/$/, "");
    this.model = opts.model ?? "llama3.1";
  }

  async listModels(): Promise<OllamaModel[]> {
    const resp = await fetch(`${this.baseUrl}/api/tags`);
    if (!resp.ok) throw new Error(`Ollama list failed: ${resp.status}`);
    const data = await resp.json();
    return data.models ?? [];
  }

  private buildTools(tools?: ToolDef[]) {
    if (!tools?.length) return undefined;
    return tools.map((t) => ({
      type: "function",
      function: { name: t.name, description: t.description, parameters: t.parameters },
    }));
  }

  async chat(messages: Message[], options: ChatOptions = {}): Promise<Response> {
    const body: Record<string, unknown> = {
      model: options.model ?? this.model,
      messages: messages.map((m) => ({ role: m.role, content: m.content })),
      stream: false,
    };
    const toolDefs = this.buildTools(options.tools);
    if (toolDefs) body.tools = toolDefs;

    const resp = await fetch(`${this.baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!resp.ok) throw new Error(`Ollama chat failed: ${resp.status}`);

    const data = await resp.json();
    const msg = data.message ?? {};
    const toolCalls: ToolCall[] = (msg.tool_calls ?? []).map(
      (tc: { function: { name: string; arguments: Record<string, unknown> } }) => ({
        id: `call_${tc.function.name}`,
        function: {
          name: tc.function.name,
          arguments: JSON.stringify(tc.function.arguments),
        },
      })
    );

    return {
      content: msg.content ?? "",
      tool_calls: toolCalls,
      usage: {
        prompt_tokens: data.prompt_eval_count ?? 0,
        completion_tokens: data.eval_count ?? 0,
        total_tokens: (data.prompt_eval_count ?? 0) + (data.eval_count ?? 0),
      },
      model: data.model ?? this.model,
      finish_reason: data.done_reason ?? "stop",
    };
  }

  async *chatStream(messages: Message[], options: ChatOptions = {}): AsyncIterable<string> {
    const body: Record<string, unknown> = {
      model: options.model ?? this.model,
      messages: messages.map((m) => ({ role: m.role, content: m.content })),
      stream: true,
    };
    const toolDefs = this.buildTools(options.tools);
    if (toolDefs) body.tools = toolDefs;

    const resp = await fetch(`${this.baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!resp.ok) throw new Error(`Ollama stream failed: ${resp.status}`);
    if (!resp.body) throw new Error("No response body for streaming");

    const reader = resp.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        if (!line.trim()) continue;
        const data = JSON.parse(line);
        const content = data.message?.content ?? "";
        if (content) yield content;
      }
    }
  }
}
```

## Configuration

| Env Variable | Required | Description |
|---|---|---|
| `OLLAMA_HOST` | No | Ollama server URL (default: `http://localhost:11434`) |

## Placeholders

| Placeholder | Description |
|---|---|
| `{{PROJECT_NAME}}` | Name of the project using this provider |
| `{{PACKAGE_NAME}}` | npm package name |

## Dependencies

No external dependencies. Uses built-in `fetch` (Node.js 18+).
