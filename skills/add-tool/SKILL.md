---
name: add-tool
description: "Use when the user wants to create a custom tool for their assistant project. Triggers on: 'add tool', 'create tool', 'new tool', 'custom function', '/add-tool'"
---

# Add Tool

Interactively create a custom tool for an existing assistant project.

## Checklist

1. **Inspect the current project contract** — detect stack, registry location, existing tool conventions, and domain boundaries
2. **Understand the tool request** — what should it do, what inputs does it need, what does it return
3. **Choose the implementation pattern** — use `tool-patterns.md`
4. **Define the tool contract** — name, parameters, return type, side effects, env vars
5. **Generate the tool** — follow project-native conventions
6. **Generate tests** — at least one happy path and one edge or failure case
7. **Register and document** — tool registry, `.env.example`, README if needed
8. **Verify** — imports, registration, and tests

## Support Rule

Custom tools inherit the support level of the target project path. If the user is extending a `Preview` project shape, say so before claiming a polished integration.

## Project Inspection

Before proposing the tool shape, inspect:

- existing registry format
- naming conventions
- whether the project uses domain-scoped tools
- what support tier the current project path belongs to
