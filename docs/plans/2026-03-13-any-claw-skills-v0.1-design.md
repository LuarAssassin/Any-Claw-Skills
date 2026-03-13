# any-claw-skills v0.1 Design

## Goal

Ship `any-claw-skills` as a publishable, Claude Code first skill package for interactively scaffolding personal AI assistant products. The repository should feel like a real open source product, not a loose collection of templates.

## Constraints

- This repository is a `skills + commands + templates + docs + tests` package.
- It is not a standalone code generator service or CLI.
- `Claude Code` is the primary target for v0.1.
- The release bar should be modeled after `superpowers`: clear installation, strong repo framing, explicit support boundaries, and repeatable verification.
- v0.1 should be `narrow and deep`, not broad and shallow.

## Product Positioning

`any-claw-skills` is a domain-oriented assistant builder for AI coding tools. It helps the agent guide the user through project choices, then uses templates and reference skills to reproduce a personal assistant project with channels, providers, domain packs, prompts, and optional MCP surfaces.

The v0.1 promise is not "every template is equally production-ready." The promise is:

1. A new user can understand what the package does.
2. A Claude Code user can install it and follow one strong golden path.
3. A maintainer can verify release readiness with repeatable checks.
4. The repository clearly distinguishes stable, beta, and reference content.

## Recommended Release Strategy

Use a `release-kit first` strategy.

Why:

- It matches the user's request to complete the open source project against `superpowers`.
- It produces a credible public v0.1 faster than expanding more domains first.
- It creates the structure needed for future domain/tool/MCP growth without turning the repo into an uncurated template dump.

Rejected alternatives:

- `capability first`: would increase apparent scope but weaken release credibility.
- `spec first`: would produce cleaner long-term abstractions but delay a usable first release.

## v0.1 Scope

### GA

- `skills/using-any-claw-skills/SKILL.md`
- `skills/build-assistant/SKILL.md`
- `skills/add-domain/SKILL.md`
- `skills/add-channel/SKILL.md`
- `skills/add-provider/SKILL.md`
- `skills/add-tool/SKILL.md`
- Claude Code installation entrypoints under `.claude-plugin/`
- Documentation for install, support matrix, release verification, examples, and contribution flow
- Test suite structure that validates the golden path and core skill routing

### Golden Path

The release should optimize for this recommended path:

- Tier: `Standard`
- Stack: `Python`
- Provider: `OpenAI`
- Channels: `CLI + Telegram`
- Domain: `Productivity`
- Options: `.env example + Docker + MCP server`

This path is the only one that needs end-to-end release narrative, examples, and explicit verification in v0.1.

### Beta

- Additional providers: `Anthropic`, `Ollama`
- Additional channels: `Discord`, `Slack`
- Additional domains: `Health`, `Finance`

### Reference / Preview

- Other tiers and stacks
- Other channel templates
- Other domains
- Shallow Rust or lightly validated templates

These should remain in the repository but be labeled clearly in docs and status tracking.

## Support Model

The repository should publish a support matrix with three levels:

- `GA`: explicitly recommended and release-verified
- `Beta`: included and documented, but validated less deeply
- `Preview`: useful references or starter templates without release promises

This support model should drive:

- README framing
- wizard recommendations
- status tracking
- release checklist
- tests

## Skill Responsibilities

### `using-any-claw-skills`

- Frame the package as Claude Code first
- Route users to the correct builder or extension skill
- Explain support tiers and when to prefer the golden path

### `build-assistant`

- Emphasize that the package guides the AI tool through project reproduction
- Recommend the GA golden path by default
- Distinguish between GA, Beta, and Preview choices during wizard flow
- Detect whether the current directory is empty, already generated, or should be extended

### `add-domain`, `add-channel`, `add-provider`, `add-tool`

- Treat the target project as a generated assistant scaffold with an implicit contract
- Inspect project tier, stack, and current integrations before proposing changes
- Make extension flows consistent with the support matrix

## Domain Pack Contract

v0.1 should define a documented contract for every domain pack. Each domain should describe:

- required files: `system-prompt`, `knowledge`, `tools`
- optional files: `mcp-server`
- expected env vars
- integration points in generated projects
- safety/compliance notes where applicable
- validation expectations for GA/Beta/Preview status

This contract is more important than adding more domains in this iteration.

## Repository Deliverables

### Documentation

- Rewrite `README.md` into a release-facing landing page
- Add `docs/support-matrix.md`
- Add `docs/release-checklist.md`
- Add `docs/testing.md`
- Add `docs/domain-pack-contract.md`
- Add `docs/examples/` materials for the golden path
- Rework `STATUS.md` into a release-readiness board

### Repository metadata

- Add `.github/` workflow(s) and contribution templates
- Add `CONTRIBUTING.md`
- Add `CODE_OF_CONDUCT.md`
- Add `SECURITY.md`
- Align versioning across plugin metadata and release notes

### Testing

Move from manual-only test notes to a layered release verification bundle:

- install smoke checks
- skill trigger coverage
- golden path wizard verification
- expansion flow verification
- docs consistency checks

The test suite can still rely on scripted/manual validation, but it must be structured and repeatable.

## Non-Goals

- Building a separate generator CLI or service
- Reaching feature parity across Cursor, Codex, OpenCode, and Gemini in v0.1
- Declaring every template equally mature
- Expanding template breadth as the primary deliverable for this release

## Execution Order

1. Reframe the repo for release: README, support matrix, status, release notes, contribution docs.
2. Tighten skill responsibilities around the golden path and support tiers.
3. Add domain pack contract and example artifacts.
4. Upgrade tests and CI around release verification.
5. Finalize release-readiness docs and version alignment.

## Risks

- The repo currently has many templates that can imply stronger support than is actually validated.
- Overstating cross-platform support would weaken the release.
- Without a domain contract, future expansion can quickly become inconsistent.
- Without a release checklist and CI, v0.1 will still feel manual and fragile.

## Success Criteria

- A new visitor can understand the product from the README alone.
- A Claude Code user can install the package and understand the golden path.
- A maintainer can run documented verification steps for release readiness.
- The repo explicitly communicates which parts are GA, Beta, and Preview.
- The project reads as a coherent open source product rather than a collection of disconnected assets.

## Notes

- `docs/plans/` did not exist and is being introduced here for design and planning artifacts.
- This workspace is not inside a git repository, so the `brainstorming` skill's "commit the design document" step cannot be completed in this environment.
