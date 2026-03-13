---
name: tool-patterns
description: "Use when the user asks about tool systems, function calling, tool registration, or how AI assistants execute tools. Reference skill pointing to tool analysis docs."
---

# Tool Patterns

Reference skill for tool system and skill patterns.

## When to Use

- User asks about tool/function calling architecture
- User asks about tool registration and discovery
- User asks about tool parameter validation
- User asks about tool execution sandboxing

## Key Patterns

1. **Tool Registry** — Central registry mapping tool names to implementations
2. **Schema Validation** — Validate tool parameters against JSON Schema
3. **Execution Sandbox** — Isolate tool execution (timeout, resource limits)
4. **Result Formatting** — Normalize tool results for LLM consumption
5. **Tool Composition** — Tools that call other tools

## Reference Documents

- `docs/tool-system-skills-analysis.md` — Full tool system analysis
- `docs/plugin-architecture-analysis.md` — Plugin/extension architecture

Read these documents for detailed patterns across reference implementations.
