---
name: add-channel
description: "Use when the user wants to add a messaging channel to an existing assistant project. Triggers on: 'add channel', 'add telegram', 'add discord', 'add slack', 'connect to whatsapp', '/add-channel'"
---

# Add Channel

Add a channel to an existing assistant project, preferably one generated from the `any-claw-skills` project contract.

## Support-Tier Rule

Before recommending a channel, tell the user whether it is:

- `GA` - `CLI`, `Telegram`
- `Beta` - `Discord`, `Slack`
- `Preview` - `WhatsApp`, `DingTalk`, `Feishu`, `Web UI`

## Checklist

1. **Inspect the current project contract** — identify tier, stack, existing channels, and whether the structure matches a generated assistant project
2. **Read compatibility guidance** — use `channel-matrix.md`
3. **Filter choices** — only show compatible and not-yet-present channels
4. **Explain support tier** — call out GA/Beta/Preview before the user chooses
5. **Generate the adapter from templates** — read `templates/channels/{{channel}}.{{stack}}.md`
6. **Integrate into the generated project** — registry, config, `.env.example`, README
7. **Verify** — check imports, registration, and config wiring

## Project Inspection

Detect:

- stack markers such as `pyproject.toml`, `package.json`, `go.mod`
- project shape under `providers/`, `channels/`, and `tools/`
- whether a channel registry already exists

If the project does not resemble the expected generated project contract, say so before generating files.
