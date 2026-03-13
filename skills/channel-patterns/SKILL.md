---
name: channel-patterns
description: "Use when the user asks about channel adapter architecture, message routing, multi-channel design, or how to connect messaging platforms. Reference skill pointing to channel analysis docs."
---

# Channel Patterns

Reference skill for channel adapter architecture patterns.

## When to Use

- User asks about channel adapter design
- User asks how to support multiple messaging platforms
- User asks about message format normalization
- User asks about webhook vs polling vs WebSocket

## Key Patterns

1. **Adapter Pattern** — Common interface, platform-specific implementations
2. **Message Normalization** — Convert platform messages to unified format
3. **Media Handling** — Download, cache, and forward media across channels
4. **Rate Limiting** — Per-channel and per-user rate limits
5. **Connection Management** — Reconnection, health checks, graceful shutdown

## Adapter Interface

All channel adapters share:
- `start()` — Begin listening for messages
- `stop()` — Graceful shutdown
- `send_message(chat_id, content)` — Send response back to channel
- `on_message(callback)` — Register message handler

## Reference Documents

- `docs/channel-adapter-architecture-analysis.md` — Full channel adapter analysis across 5 implementations

Read this document for detailed patterns, code examples, and trade-offs.
