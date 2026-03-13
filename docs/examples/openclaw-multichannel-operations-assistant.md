# Example: OpenClaw-Style Multi-Channel Operations Assistant

## Scenario

The user wants a more productized personal assistant that can coordinate work across multiple channels, route messages cleanly, and feel closer to an always-on assistant than a single bot entrypoint.

## Selected Options

| Choice | Value |
|-------|-------|
| Reference mode | `OpenClaw` |
| Tier | `Full` |
| Stack | `TypeScript` |
| Providers | `OpenAI`, `Anthropic` |
| Channels | `CLI`, `Telegram`, `Slack` |
| Domain packs | `Productivity`, `Finance` |
| Capabilities | `.env.example`, `Docker`, `MCP server`, `observability`, `scheduling` |

## Product Shape

- multi-channel routing from a shared assistant core
- more than one provider, with room for policy-based routing later
- domain packs that feel like first-class product modules
- stronger operational surfaces than a simple chat bot
- a structure that can keep growing without becoming a single-file tangle

## Generated Tree

```text
ops-assistant/
├── src/
│   ├── index.ts
│   ├── config.ts
│   ├── app/
│   │   ├── router.ts
│   │   ├── scheduler.ts
│   │   └── observability.ts
│   ├── providers/
│   │   ├── openai.ts
│   │   ├── anthropic.ts
│   │   └── router.ts
│   ├── channels/
│   │   ├── cli.ts
│   │   ├── telegram.ts
│   │   └── slack.ts
│   ├── tools/
│   │   ├── productivity/
│   │   └── finance/
│   └── mcp/
│       ├── productivity-server.ts
│       └── finance-server.ts
├── package.json
├── Dockerfile
├── docker-compose.yml
├── .env.example
└── README.md
```

## Why This Matters

This is the "productized assistant" path. It shows that `any-claw-skills` is not limited to tiny helpers or the GA golden path. Claude Code should be able to use the same skills package to reproduce a richer OpenClaw-style assistant that is still modular and maintainable.
