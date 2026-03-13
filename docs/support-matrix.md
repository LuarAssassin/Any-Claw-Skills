# Support Matrix

## Status Levels

- `GA`: recommended, documented as primary, and included in release verification
- `Beta`: usable and documented, but not validated as deeply as GA
- `Preview`: starter templates or references without strong release promises

## Client Support

| Client | Status | Notes |
|-------|--------|-------|
| Claude Code | GA | Primary release target for v0.1.0; marketplace install verification is still a manual release step |
| Cursor | Preview | Metadata included, not part of release verification |
| Codex | Preview | Install notes included, not part of release verification |
| OpenCode | Preview | Install notes included, not part of release verification |
| Gemini CLI | Preview | Extension metadata included, not part of release verification |

## Golden Path Support

| Surface | Status | Notes |
|--------|--------|-------|
| Tier: Standard | GA | Primary build tier |
| Stack: Python | GA | Primary implementation stack |
| Provider: OpenAI | GA | Primary provider for the release |
| Channel: CLI | GA | Lowest-friction validation path |
| Channel: Telegram | GA | Real messaging entrypoint for demos |
| Domain: Productivity | GA | Primary domain pack for v0.1.0 |
| Option: MCP server | GA | Supported in golden path examples |
| Option: Docker | GA | Supported in golden path examples |

## Beta Support

| Surface | Status | Notes |
|--------|--------|-------|
| Provider: Anthropic | Beta | Documented, not a golden path dependency |
| Provider: Ollama | Beta | Privacy/local option, lower release coverage |
| Channel: Discord | Beta | Included in templates and extension flow |
| Channel: Slack | Beta | Included in templates and extension flow |
| Domain: Health | Beta | Requires stronger safety framing before GA |
| Domain: Finance | Beta | Requires stronger validation before GA |

## Preview Support

| Surface | Status | Notes |
|--------|--------|-------|
| Tier: Pico | Preview | Starter only |
| Tier: Nano | Preview | Starter only |
| Tier: Full | Preview | Advanced reference, not release-verified |
| Tier: Enterprise | Preview | Stub/reference level |
| Stack: Go | Preview | Outside the golden path |
| Stack: TypeScript | Preview | Outside the golden path |
| Stack: Rust | Preview | Outside the golden path |
| Channel: WhatsApp | Preview | Template available, low verification depth |
| Channel: DingTalk | Preview | Template available, low verification depth |
| Channel: Feishu | Preview | Template available, low verification depth |
| Channel: Web UI | Preview | Template available, low verification depth |
| Domain: Education | Preview | Template available, low verification depth |
| Domain: Social | Preview | Template available, low verification depth |
| Domain: Smart Home | Preview | Template available, low verification depth |

## Promotion Rules

Move a surface from `Preview` or `Beta` only when all of the following exist:

1. Clear docs that match the current support claim
2. At least one repeatable verification path
3. A generated-project example or equivalent proof artifact
4. No contradiction with the golden path or current status board

## Release Reading Order

1. [`README.md`](../README.md)
2. [`docs/release-checklist.md`](release-checklist.md)
3. [`docs/testing.md`](testing.md)
4. [`STATUS.md`](../STATUS.md)
