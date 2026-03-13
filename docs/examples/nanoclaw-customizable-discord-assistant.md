# Example: NanoClaw-Style Customizable Discord Assistant

## Scenario

The user wants a small, understandable assistant they can keep modifying with Claude Code, with one real messaging channel and one domain pack.

## Selected Options

| Choice | Value |
|-------|-------|
| Reference mode | `NanoClaw` |
| Tier | `Nano` |
| Stack | `TypeScript` |
| Provider | `Anthropic` |
| Channels | `Discord` |
| Domain packs | `Productivity` |
| Capabilities | `.env.example`, lightweight Docker support |

## Product Shape

- compact modular codebase
- one main external channel
- one domain pack
- easy to fork and customize
- designed for iterative Claude Code changes

## Generated Tree

```text
nano-assistant/
├── src/
│   ├── index.ts
│   ├── config.ts
│   ├── provider.ts
│   ├── channels/
│   │   └── discord.ts
│   └── tools/
│       └── productivity.ts
├── package.json
├── Dockerfile
├── .env.example
└── README.md
```

## Why This Matters

This is the "small but real" path. It sits between PicoClaw-style minimalism and CoPaw-style extensibility, which is exactly the kind of customizable assistant many Claude Code users actually want.
