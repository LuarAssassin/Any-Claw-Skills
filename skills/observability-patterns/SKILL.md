---
name: observability-patterns
description: "Use when the user asks about logging, tracing, monitoring, debugging, or replay systems for AI assistants. Reference skill pointing to observability analysis docs."
---

# Observability Patterns

Reference skill for logging, tracing, and replay patterns.

## When to Use

- User asks about logging strategies for assistants
- User asks about distributed tracing
- User asks about conversation replay/debugging
- User asks about metrics and monitoring
- User asks about error tracking

## Key Patterns

1. **Structured Logging** — JSON logs with correlation IDs
2. **Conversation Tracing** — Trace a message through channels, agent, tools, provider
3. **Replay System** — Record and replay conversations for debugging
4. **Metrics** — Token usage, latency, error rates, tool execution times
5. **Health Checks** — Channel connectivity, provider availability, storage health

## Reference Documents

- `docs/observability-tracing-replay-analysis.md` — Full observability analysis

Read this document for detailed patterns across reference implementations.
