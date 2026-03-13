# Release Checklist

Use this checklist before tagging or announcing a release.

## Scope

- Confirm the release target is still `Claude Code first`
- Confirm the golden path is still `Standard + Python + OpenAI + CLI + Telegram + Productivity`
- Confirm GA, Beta, and Preview language matches [`docs/support-matrix.md`](support-matrix.md)

## Metadata

- Version matches across:
  - [`.claude-plugin/plugin.json`](../.claude-plugin/plugin.json)
  - [`.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json)
  - [`.cursor-plugin/plugin.json`](../.cursor-plugin/plugin.json)
  - [`gemini-extension.json`](../gemini-extension.json)
- Plugin descriptions match the repository positioning

## Docs

- [`README.md`](../README.md) explains what the package is and is not
- [`STATUS.md`](../STATUS.md) reflects current release truthfully
- [`RELEASE-NOTES.md`](../RELEASE-NOTES.md) matches the version and scope
- [`docs/domain-pack-contract.md`](domain-pack-contract.md) reflects current domain expectations
- [`docs/examples/golden-path-standard-python-productivity.md`](examples/golden-path-standard-python-productivity.md) still matches template structure

## Skill Routing

- `using-any-claw-skills` points new Claude Code users toward the supported flow
- `build-assistant` recommends the golden path by default
- `add-domain`, `add-channel`, `add-provider`, and `add-tool` all inspect project state before extending it

## Verification

- Run [`tests/run-all.sh`](../tests/run-all.sh)
- Review output for missing docs, broken suite wiring, or stale prompts
- Run the metadata consistency check from [`docs/testing.md`](testing.md)

## External Claims

- Do not claim official marketplace publication unless the submission has been completed and verified
- Do not claim non-Claude parity unless those flows have release evidence
- Do not promote Preview content to Beta or GA without updating docs and tests together
