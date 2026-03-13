# Example: PicoClaw-Style Minimal CLI Assistant

## Scenario

The user wants the smallest possible personal assistant that can run locally, answer simple questions, and be extended later.

## Selected Options

| Choice | Value |
|-------|-------|
| Reference mode | `PicoClaw` |
| Tier | `Pico` |
| Stack | `Go` |
| Provider | `OpenAI` |
| Channels | `CLI` |
| Domain packs | `None` |
| Capabilities | `.env.example` only |

## Product Shape

- one small executable
- minimal dependencies
- one provider
- one local interaction surface
- no extra control plane or MCP layer

## Generated Tree

```text
pico-assistant/
├── main.go
├── go.mod
├── .env.example
└── README.md
```

## Why This Matters

This is the "start tiny" path. It proves `any-claw-skills` is not only for larger assistants. A user should be able to begin with this and later grow the project using extension skills.
