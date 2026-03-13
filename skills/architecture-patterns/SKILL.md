---
name: architecture-patterns
description: "Use when the user asks about agent runtime architecture, event loops, message processing, or how personal assistants work internally. Reference skill pointing to architecture analysis docs."
---

# Architecture Patterns

Reference skill for agent runtime architecture patterns across personal assistant implementations.

## When to Use

- User asks how to design an agent runtime/event loop
- User asks about message processing pipelines
- User asks about agent state machines
- User asks about multi-turn conversation management

## Key Patterns

1. **Event Loop** — Single async loop processing messages from all channels
2. **Message Bus** — Pub/sub for cross-channel communication
3. **State Machine** — Conversation state transitions (idle -> processing -> responding)
4. **Tool Execution** — Interleaved LLM calls and tool invocations
5. **Context Assembly** — Building the prompt from system prompt + history + tool results

## Reference Documents

For detailed analysis across 5+ reference implementations, read these docs:

- `docs/agent-runtime-architecture-analysis.md` — Core runtime patterns
- `docs/complete-agent-architecture-analysis.md` — End-to-end architecture comparison
- `docs/context-management-analysis.md` — Context window management strategies
- `docs/workflow-task-engine-analysis.md` — Task orchestration patterns

Read the relevant document when the user's question requires detailed architectural guidance.
