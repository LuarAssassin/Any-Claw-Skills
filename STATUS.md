# any-claw-skills Release Status

## Release Target

- Version: `0.1.0`
- Positioning: `Claude Code first`
- Strategy: `narrow and deep`
- Golden path: `Standard + Python + OpenAI + CLI + Telegram + Productivity`

## GA

- Claude Code plugin metadata and entrypoints
- `using-any-claw-skills`
- `build-assistant`
- `add-channel`
- `add-domain`
- `add-provider`
- `add-tool`
- Support matrix, release checklist, testing guide, and product-composition docs
- Golden path documentation and release verification structure

## Beta

- Providers: `Anthropic`, `Ollama`
- Channels: `Discord`, `Slack`
- Domains: `Health`, `Finance`

## Preview

- Tiers: `Pico`, `Nano`, `Full`, `Enterprise`
- Stacks outside the golden path
- Channels: `WhatsApp`, `DingTalk`, `Feishu`, `Web UI`
- Domains: `Education`, `Social`, `Smart Home`
- Templates that have not been validated through release examples or structured verification

## Verification Assets

- [`README.md`](README.md)
- [`README.zh-CN.md`](README.zh-CN.md)
- [`docs/support-matrix.md`](docs/support-matrix.md)
- [`docs/release-checklist.md`](docs/release-checklist.md)
- [`docs/testing.md`](docs/testing.md)
- [`docs/assistant-product-composition-model.md`](docs/assistant-product-composition-model.md)
- [`docs/examples/golden-path-standard-python-productivity.md`](docs/examples/golden-path-standard-python-productivity.md)
- [`docs/examples/picoclaw-minimal-cli-assistant.md`](docs/examples/picoclaw-minimal-cli-assistant.md)
- [`docs/examples/nanoclaw-customizable-discord-assistant.md`](docs/examples/nanoclaw-customizable-discord-assistant.md)
- [`docs/examples/openclaw-multichannel-operations-assistant.md`](docs/examples/openclaw-multichannel-operations-assistant.md)

## Blockers

- Official marketplace submission and external validation are still pending
- Non-Claude clients are included, but not release-equal
- Preview templates still need deeper examples or verification before promotion

## Next Milestone

- Keep the golden path green in docs, tests, and CI
- Keep the reference-mode-first builder flow consistent across skills, commands, examples, and tests
- Promote selected Beta surfaces only after explicit verification evidence
- Add more generated-project examples before broadening GA scope
