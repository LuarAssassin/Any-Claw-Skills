# any-claw-skills

`any-claw-skills` is a Claude Code first skill package for reproducing personal AI assistant products from conversation. It gives the coding agent a guided build flow, domain packs, channel/provider templates, and reference architecture material so the agent can scaffold a concrete assistant project instead of improvising one from scratch.

## What It Is

This repository ships:

- `skills/` for build and extension flows
- `commands/` for slash-command entrypoints
- `templates/` for scaffolds, providers, channels, and domains
- `docs/` for support policy, release checks, examples, and architecture analysis
- `tests/` for release verification scripts

It does not ship a standalone code generator CLI or service.

## Claude Code First

v0.1.0 is optimized for Claude Code. The primary supported story is:

1. Install the skill package in Claude Code
2. Start a new session in an empty project directory
3. Ask to build a personal assistant or run `/build-assistant`
4. Let the skill guide the AI through project choices
5. Generate a project from repository templates and extension skills

Metadata for Cursor, Codex, OpenCode, and Gemini is included, but release verification for v0.1.0 is centered on Claude Code.

## Golden Path

The v0.1.0 golden path is the recommended first build:

| Choice | Value |
|-------|-------|
| Tier | `Standard` |
| Stack | `Python` |
| Provider | `OpenAI` |
| Channels | `CLI + Telegram` |
| Domain | `Productivity` |
| Options | `.env.example + Docker + MCP server` |

This is the only path treated as fully release-verified for v0.1.0. Other combinations remain available, but many are Beta or Preview.

## Installation

### Claude Code

The repository includes Claude plugin metadata in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) and [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json).

Common install flows:

```bash
/plugin marketplace add any-claw/any-claw-skills-marketplace
/plugin install any-claw-skills@any-claw-skills-marketplace
```

If you maintain a local or internal marketplace, point Claude Code at this repository and use the same plugin metadata.

### Secondary Clients

- Codex: [`.codex/INSTALL.md`](.codex/INSTALL.md)
- OpenCode: [`.opencode/INSTALL.md`](.opencode/INSTALL.md)
- Cursor: [`.cursor-plugin/plugin.json`](.cursor-plugin/plugin.json)
- Gemini: [`GEMINI.md`](GEMINI.md)

These are included for compatibility, not because they are release-equal to Claude Code in v0.1.0.

## Quick Start

Start a new Claude Code session and say:

> I want to build a personal assistant

Or run:

> `/build-assistant`

The skill should steer the session toward the recommended path unless you explicitly choose Beta or Preview combinations.

## Support Matrix

Release support is split into three levels:

- `GA`: recommended and release-verified
- `Beta`: included and documented, but verified less deeply
- `Preview`: reference material or starter templates without strong release guarantees

Current highlights:

| Surface | Status |
|-------|--------|
| Claude Code entrypoints | GA |
| `build-assistant` and extension skills | GA |
| `Standard / Python / OpenAI / CLI / Telegram / Productivity` | GA |
| Anthropic, Ollama, Discord, Slack, Health, Finance | Beta |
| Other tiers, stacks, and most remaining templates | Preview |

Full details: [`docs/support-matrix.md`](docs/support-matrix.md)

## Repository Guide

### Core Skills

| Skill | Purpose |
|-------|---------|
| `using-any-claw-skills` | Session-start routing and support-tier framing |
| `build-assistant` | Interactive assistant builder flow |
| `add-channel` | Expand an existing generated assistant with a new channel |
| `add-domain` | Add a vertical domain pack |
| `add-provider` | Add an LLM provider integration |
| `add-tool` | Create a custom tool that matches project conventions |

### Reference Skills

| Skill | Purpose |
|-------|---------|
| `architecture-patterns` | Agent runtime structure across reference projects |
| `channel-patterns` | Channel adapter design references |
| `provider-patterns` | Provider abstraction references |
| `tool-patterns` | Tool and skill system references |
| `storage-patterns` | Persistence and state references |
| `observability-patterns` | Logging, tracing, and replay references |

## Release Docs

- Support policy: [`docs/support-matrix.md`](docs/support-matrix.md)
- Release checklist: [`docs/release-checklist.md`](docs/release-checklist.md)
- Testing guide: [`docs/testing.md`](docs/testing.md)
- Domain pack contract: [`docs/domain-pack-contract.md`](docs/domain-pack-contract.md)
- Golden path example: [`docs/examples/golden-path-standard-python-productivity.md`](docs/examples/golden-path-standard-python-productivity.md)
- Current status: [`STATUS.md`](STATUS.md)

## Roadmap

### v0.1.0

- Ship a credible Claude Code first release
- Make the golden path explicit and testable
- Distinguish GA, Beta, and Preview surfaces
- Add repeatable release verification and CI

### After v0.1.0

- Deepen Beta domain packs
- Improve non-Claude client verification
- Add more evidence for advanced stacks and channels
- Validate official marketplace submission if desired

## Contributing

Start with [`CONTRIBUTING.md`](CONTRIBUTING.md). Keep changes aligned with the published support matrix instead of broadening scope without verification.

## License

MIT License. See [`LICENSE`](LICENSE).
