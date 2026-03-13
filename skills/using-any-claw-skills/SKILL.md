---
name: using-any-claw-skills
description: "Use at session start - establishes how to use any-claw-skills as a Claude Code first assistant builder package"
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this skill.
</SUBAGENT-STOP>

# Using any-claw-skills

You have **any-claw-skills** installed. This package is a **Claude Code first** toolkit for reproducing personal AI assistant projects from conversation.

## What This Package Is

Use this repository when the user wants the agent to:

- scaffold a new personal assistant project
- expand an existing generated assistant with a domain, provider, channel, or tool
- reference proven architecture patterns from the included assistant repos

This package is:

- a set of `skills`
- `slash commands`
- `templates`
- `docs`
- `verification scripts`

This package is **not** a standalone generator service or CLI.

## Support Tiers

Always frame choices using the published support tiers:

- `GA` - recommended and release-verified
- `Beta` - included and documented, but validated less deeply
- `Preview` - reference or starter content without strong release guarantees

The v0.1.0 **golden path** is:

- Tier: `Standard`
- Stack: `Python`
- Provider: `OpenAI`
- Channels: `CLI + Telegram`
- Domain: `Productivity`

Prefer this path unless the user explicitly wants Beta or Preview tradeoffs.

## Reference Product Shapes

The builder is organized around five reference product shapes:

- `PicoClaw`
- `NanoClaw`
- `CoPaw`
- `OpenClaw`
- `IronClaw`

When the user wants a new assistant, establish which of these five reference product shapes is closest before diving into stack, provider, or channel details.

## Skill Catalog

| Skill | When to Invoke | Purpose |
|-------|----------------|---------|
| `build-assistant` | User wants a new assistant project | Interactive builder flow with support-tier guidance |
| `add-channel` | User wants a new channel in an existing project | Expand a generated assistant with a channel adapter |
| `add-domain` | User wants domain capabilities | Add a domain pack with tools, prompts, and optional MCP |
| `add-provider` | User wants another model provider | Add provider integration and routing |
| `add-tool` | User wants a custom capability | Create a project-native tool |
| `architecture-patterns` | User asks runtime architecture questions | Reference patterns |
| `channel-patterns` | User asks about channel adapter design | Reference patterns |
| `provider-patterns` | User asks about provider abstraction design | Reference patterns |
| `tool-patterns` | User asks about tool design | Reference patterns |
| `storage-patterns` | User asks about persistence and state | Reference patterns |
| `observability-patterns` | User asks about logging, tracing, replay | Reference patterns |

## Routing Rules

1. If the user wants to create a new assistant, invoke `build-assistant`.
2. If the current directory already looks like an assistant project, prefer `add-channel`, `add-domain`, `add-provider`, or `add-tool` over rebuilding.
3. If the user asks design questions rather than asking you to build or extend, invoke the relevant reference skill.
4. If a requested path is `Beta` or `Preview`, say so clearly before proceeding.

## Claude Code First Guidance

In Claude Code:

- use the native `Skill` tool to load the requested skill
- keep interactions sequential and explicit
- favor the golden path for examples, screenshots, and verification

For non-Claude environments, see:

- `references/codex-tools.md`
- `references/gemini-tools.md`

Those are compatibility notes, not equal support claims.
