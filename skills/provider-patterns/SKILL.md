---
name: provider-patterns
description: "Use when the user asks about LLM provider abstraction, model routing, multi-provider setups, or streaming. Reference skill pointing to provider analysis docs."
---

# Provider Patterns

Reference skill for model provider abstraction patterns.

## When to Use

- User asks about provider abstraction layers
- User asks about multi-model routing
- User asks about streaming responses
- User asks about fallback/retry strategies
- User asks about token counting or cost tracking

## Key Patterns

1. **Provider Interface** — Common chat/complete API across providers
2. **Streaming Adapter** — Normalize SSE/WebSocket streams to async iterators
3. **Fallback Chain** — Try providers in order on failure
4. **Model Router** — Route by model name prefix or request properties
5. **Token Tracking** — Count usage for cost monitoring

## Reference Documents

- `docs/model-provider-abstraction-analysis.md` — Full provider pattern analysis

Read this document for detailed patterns, code examples, and trade-offs across Python, TypeScript, Go, and Rust implementations.
