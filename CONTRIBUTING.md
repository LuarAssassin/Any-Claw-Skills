# Contributing

## Scope

`any-claw-skills` is a skill package repository. Contributions should improve:

- skill routing
- template quality
- release docs
- verification scripts
- support-tier clarity

Do not add standalone generator services or unrelated framework experiments here.

## Before Opening a PR

1. Read [`README.md`](README.md)
2. Read [`docs/support-matrix.md`](docs/support-matrix.md)
3. Read [`docs/domain-pack-contract.md`](docs/domain-pack-contract.md)
4. Run [`tests/run-all.sh`](tests/run-all.sh)

## Contribution Rules

- Keep Claude Code as the primary release target unless maintainers explicitly broaden scope
- Update docs and tests together when changing support claims
- Do not upgrade Preview content to Beta or GA without proof artifacts
- When adding a domain, follow [`docs/domain-pack-contract.md`](docs/domain-pack-contract.md)
- When changing skill behavior, make sure prompts, matrices, and examples remain aligned

## Pull Requests

Include:

- what changed
- why it belongs in this repository
- affected support tier
- how you verified it
- any follow-up gaps that remain
