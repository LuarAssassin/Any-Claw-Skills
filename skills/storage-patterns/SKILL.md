---
name: storage-patterns
description: "Use when the user asks about conversation storage, state management, session handling, memory systems, or RAG. Reference skill pointing to storage analysis docs."
---

# Storage Patterns

Reference skill for storage, state management, and memory patterns.

## When to Use

- User asks about conversation history storage
- User asks about session management
- User asks about memory systems (short-term, long-term)
- User asks about RAG (Retrieval-Augmented Generation)
- User asks about database schema for assistants

## Key Patterns

1. **Conversation Store** — Persist message history per user/channel
2. **Session Management** — Track active sessions with TTL
3. **Memory Hierarchy** — Working memory, episodic memory, semantic memory
4. **Context Window** — Manage what fits in the LLM context
5. **RAG Pipeline** — Embed, index, retrieve relevant knowledge

## Reference Documents

- `docs/storage-schema-analysis.md` — Database schema patterns
- `docs/memory-session-state-boundary-analysis.md` — Memory and session boundaries
- `docs/memory-rag-context-engineering-analysis.md` — RAG and context engineering
- `docs/document-ingestion-pipeline-analysis.md` — Document processing pipelines

Read the relevant document for detailed analysis.
