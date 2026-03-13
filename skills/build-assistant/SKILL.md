---
name: build-assistant
description: "Use when the user wants to build, create, or scaffold a new personal AI assistant project. Triggers on: 'build assistant', 'create assistant', 'scaffold', 'build chatbot', 'personal AI', '/build-assistant'"
---

# Build Assistant Wizard

Interactive wizard for reproducing a personal AI assistant project from this repository's templates.

This is a **Claude Code first** flow. For v0.1.0, the primary supported path is:

- `Standard`
- `Python`
- `OpenAI`
- `CLI + Telegram`
- `Productivity`
- `.env.example + Docker + MCP server`

<HARD-GATE>
Do NOT generate files until the user has explicitly approved the final configuration summary. Follow the steps in order and ask one question per message.
</HARD-GATE>

## Support-Tier Rule

Always tell the user whether a choice is:

- `GA` - preferred and release-verified
- `Beta` - available but validated less deeply
- `Preview` - available mainly as a reference or starter

If the user does not care, steer them toward the GA golden path.

## Checklist

1. **Inspect the current directory** — detect whether it is empty, contains an unrelated project, or contains an existing assistant scaffold
2. **Decide whether this is a new build or an extension** — if it is already a generated assistant, recommend `add-channel`, `add-domain`, `add-provider`, or `add-tool`
3. **Choose project name** — suggest a default from the directory name
4. **Choose complexity tier** — read `complexity-tiers.md`; recommend `Standard` first
5. **Choose stack** — read `stack-selection.md`; respect tier constraints and explain support level
6. **Choose provider(s)** — recommend `OpenAI` first, explain Beta alternatives
7. **Choose channel(s)** — recommend `CLI + Telegram`, explain Beta or Preview channels
8. **Choose domain(s)** — recommend `Productivity`, explain Beta or Preview domains
9. **Choose options** — recommend `.env.example`, `Docker`, and `MCP server` for the golden path
10. **Confirm the full build summary** — include support-tier notes for any non-GA choices
11. **Generate scaffold files** — read templates from `templates/scaffolds/`
12. **Generate providers, channels, and domains** — read templates from `templates/providers/`, `templates/channels/`, and `templates/domains/`
13. **Integrate the generated pieces** — follow `project-structure.md` and `config-templates.md`
14. **Review and hand off** — summarize generated files, next steps, and extension commands

## Step Guidance

### Step 1: Inspect the Current Directory

Check:

- project markers such as `pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`
- assistant-specific directories such as `src/<package>/providers`, `src/<package>/channels`, `src/<package>/tools`
- any existing `README`, `CLAUDE.md`, or config files

Report whether the directory is:

- empty and ready for a new build
- an existing assistant scaffold that should be extended
- an unrelated project where generation should be done carefully

### Step 2: New Build vs Extension

If the directory already looks like an `any-claw-skills`-generated assistant or a close variant:

- stop the rebuild flow
- explain that extension skills are a better fit
- route to `add-channel`, `add-domain`, `add-provider`, or `add-tool`

### Step 4: Tier Selection

Read `skills/build-assistant/complexity-tiers.md`.

Recommendations:

- `Standard` is the `GA` tier and should be recommended first
- `Pico`, `Nano`, `Full`, and `Enterprise` are `Preview` in v0.1.0

### Step 5: Stack Selection

Read `skills/build-assistant/stack-selection.md`.

Tier constraints still apply:

- `Pico` -> `Go`
- `Nano` -> `TypeScript`
- `Standard` -> `Python`
- `Full` -> `TypeScript`
- `Enterprise` -> `Rust`

Only `Standard -> Python` is `GA`.

### Step 6: Provider Selection

Support guidance:

- `OpenAI` -> `GA`
- `Anthropic` -> `Beta`
- `Ollama` -> `Beta`

If the user chooses multiple providers, generate the router only if the selected tier and stack support it cleanly.

### Step 7: Channel Selection

Support guidance:

- `CLI` -> `GA`
- `Telegram` -> `GA`
- `Discord`, `Slack` -> `Beta`
- `WhatsApp`, `DingTalk`, `Feishu`, `Web UI` -> `Preview`

If the user does not care, prefer `CLI + Telegram`.

### Step 8: Domain Selection

Support guidance:

- `Productivity` -> `GA`
- `Health`, `Finance` -> `Beta`
- `Education`, `Social`, `Smart Home` -> `Preview`
- `None` -> valid, but outside the main v0.1.0 story

If the user does not care, prefer `Productivity`.

### Step 9: Additional Options

For the golden path, recommend:

- `.env.example`
- `Docker`
- `MCP server`

`CI/CD` can be offered, but it should not distract from the main scaffold flow.

### Step 10: Confirmation

Present a summary like this:

```text
Project: {{name}}
Tier: {{tier}} ({{tier_support}})
Stack: {{stack}} ({{stack_support}})
Providers: {{providers}}
Channels: {{channels}}
Domains: {{domains}}
Options: {{options}}
```

Ask for explicit approval before generating.

### Step 11-13: Generation

Generation is template-driven:

1. Read the selected scaffold under `templates/scaffolds/{{tier}}-tier/{{stack}}/`
2. Read selected channel templates under `templates/channels/`
3. Read selected provider templates under `templates/providers/`
4. Read selected domain templates under `templates/domains/{{domain}}/`
5. Use `skills/build-assistant/project-structure.md` and `skills/build-assistant/config-templates.md` to integrate everything cleanly

Do not improvise a new scaffold format if a template exists.

### Step 14: Review and Handoff

Summarize:

- what was generated
- which choices were `GA`, `Beta`, or `Preview`
- what environment variables need to be filled
- how to run the result
- which extension commands are now available

## Key Principles

- one question per message
- recommend the golden path by default
- keep support-tier language explicit
- prefer extension skills over rebuilding existing assistant projects
- keep generation template-driven
